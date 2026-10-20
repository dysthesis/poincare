"""Small synchronous MessagePack-RPC client with causal redraw evidence.

MessagePack is imported only when a real collection is started. This module
contains no replacement editor or synthetic workload implementation.
"""

from __future__ import annotations

import os
import selectors
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


class AcquisitionError(RuntimeError):
    pass


class AcquisitionTimeout(AcquisitionError):
    pass


def kill_process_group(
    process: subprocess.Popen[bytes], grace: float = 0.3
) -> dict[str, Any]:
    """Bound cleanup even after the root exits; its children still share its PGID."""
    evidence: dict[str, Any] = {
        "pgid": process.pid,
        "signals": [],
        "returncode_before_cleanup": process.poll(),
    }
    try:
        os.killpg(process.pid, signal.SIGTERM)
        evidence["signals"].append("SIGTERM")
    except ProcessLookupError:
        pass
    # poll()/wait() on the root alone cannot establish that child servers died.
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.01)
    try:
        os.killpg(process.pid, signal.SIGKILL)
        evidence["signals"].append("SIGKILL")
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        evidence["root_reap_timeout"] = True
    evidence["returncode"] = process.poll()
    return evidence


class Screen:
    """Apply ext_linegrid events without pretending to render a physical display."""

    def __init__(self) -> None:
        self.grids: dict[int, list[list[str]]] = {}
        self.attributes: dict[int, list[list[int]]] = {}
        self.cursor: list[int] | None = None
        self.flushes = 0

    def apply(self, event: str, arguments: list[Any]) -> bool:
        if event == "grid_resize":
            grid, width, height = arguments
            previous = self.grids.get(grid, [])
            attrs = self.attributes.get(grid, [])
            self.grids[grid] = [
                (previous[row][:width] if row < len(previous) else [])
                + [" "]
                * max(0, width - (len(previous[row]) if row < len(previous) else 0))
                for row in range(height)
            ]
            self.attributes[grid] = [
                (attrs[row][:width] if row < len(attrs) else [])
                + [0] * max(0, width - (len(attrs[row]) if row < len(attrs) else 0))
                for row in range(height)
            ]
        elif event == "grid_clear":
            grid = arguments[0]
            if grid in self.grids:
                self.grids[grid] = [[" "] * len(row) for row in self.grids[grid]]
                self.attributes[grid] = [
                    [0] * len(row) for row in self.attributes[grid]
                ]
        elif event == "grid_destroy":
            self.grids.pop(arguments[0], None)
            self.attributes.pop(arguments[0], None)
        elif event == "grid_line":
            grid, row, column, cells = arguments[:4]
            highlight = 0
            for cell in cells:
                text = cell[0]
                if len(cell) > 1:
                    highlight = cell[1]
                repeat = cell[2] if len(cell) > 2 else 1
                for _ in range(repeat):
                    if (
                        grid in self.grids
                        and row < len(self.grids[grid])
                        and column < len(self.grids[grid][row])
                    ):
                        self.grids[grid][row][column] = text
                        self.attributes[grid][row][column] = highlight
                    column += 1
        elif event == "grid_scroll":
            grid, top, bottom, left, right, rows, columns = arguments
            if grid in self.grids:
                old = [row[:] for row in self.grids[grid]]
                old_attrs = [row[:] for row in self.attributes[grid]]
                for row in range(top, bottom):
                    for column in range(left, right):
                        source_row, source_column = row + rows, column + columns
                        inside = (
                            top <= source_row < bottom and left <= source_column < right
                        )
                        self.grids[grid][row][column] = (
                            old[source_row][source_column] if inside else " "
                        )
                        self.attributes[grid][row][column] = (
                            old_attrs[source_row][source_column] if inside else 0
                        )
        elif event == "grid_cursor_goto":
            self.cursor = arguments
        elif event == "flush":
            self.flushes += 1
            return True
        return False

    def snapshot(self) -> dict[str, Any]:
        return {
            "grids": {
                str(grid): ["".join(row) for row in rows]
                for grid, rows in self.grids.items()
            },
            "highlight_ids": {
                str(grid): [row[:] for row in rows]
                for grid, rows in self.attributes.items()
            },
            "cursor": self.cursor[:] if self.cursor else None,
            "flush_count": self.flushes,
            "boundary": "remote-UI ext_linegrid flush, not terminal/compositor/physical display",
        }


class Nvim:
    def __init__(
        self, command: list[str], cwd: Path, environment: dict[str, str], timeout: float
    ) -> None:
        try:
            import msgpack
        except ImportError as error:
            raise AcquisitionError(
                "real collection requires the maintained msgpack Python package (use nix develop)"
            ) from error
        self.msgpack = msgpack
        self.msgpack_version = getattr(msgpack, "__version__", None)
        self.unpacker = msgpack.Unpacker(
            raw=False, strict_map_key=False, max_buffer_size=64 * 1024 * 1024
        )
        self.timeout = timeout
        self.operation_deadline: float | None = None
        self.next_id = 1
        self.responses: dict[int, tuple[Any, Any]] = {}
        self.completions: dict[str, dict[str, Any]] = {}
        self.notifications: list[dict[str, Any]] = []
        self.startup_prompt_handling = True
        self.startup_prompt_acknowledgements: list[dict[str, Any]] = []
        self.startup_prompt_stopped_ns: int | None = None
        self._startup_mode_request: int | None = None
        self._startup_input_request: int | None = None
        self._startup_next_mode_check = 0.0
        self._startup_return_latched = False
        self._startup_last_prompt: list[str] | None = None
        self.startup_last_mode: dict[str, Any] | None = None
        self.screen = Screen()
        self.last_message_ns: int | None = None
        self.selector = selectors.DefaultSelector()
        self.stderr_file = tempfile.TemporaryFile()
        self.process: subprocess.Popen[bytes] | None = None
        try:
            self.process = subprocess.Popen(
                command,
                cwd=cwd,
                env=environment,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=self.stderr_file,
                start_new_session=True,
                bufsize=0,
            )
            assert self.process.stdout is not None and self.process.stdin is not None
            os.set_blocking(self.process.stdout.fileno(), False)
            os.set_blocking(self.process.stdin.fileno(), False)
            self.selector.register(self.process.stdout, selectors.EVENT_READ)
        except BaseException:
            if self.process is not None:
                kill_process_group(self.process)
            self.selector.close()
            self.stderr_file.close()
            raise

    def send(self, payload: list[Any], deadline: float | None = None) -> None:
        assert self.process is not None and self.process.stdin is not None
        data = self.msgpack.packb(payload, use_bin_type=True)
        view = memoryview(data)
        deadline = deadline or (time.monotonic() + self.timeout)
        while view:
            try:
                written = os.write(self.process.stdin.fileno(), view)
                view = view[written:]
            except BlockingIOError:
                # A full input pipe must not turn an observation timeout into an
                # unbounded write. Drain redraws while Neovim reads the request.
                if time.monotonic() >= deadline:
                    raise AcquisitionTimeout("timed out writing an RPC request")
                self.pump(min(deadline, time.monotonic() + 0.01), allow_idle=True)
            except (BrokenPipeError, OSError) as error:
                raise AcquisitionError(f"Neovim RPC input closed: {error}") from error

    def notify(self, method: str, *args: Any) -> None:
        self.send([2, method, list(args)])

    def request(self, method: str, *args: Any, timeout: float | None = None) -> Any:
        message_id = self.next_id
        self.next_id += 1
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        if self.operation_deadline is not None:
            deadline = min(deadline, self.operation_deadline)
        self.send([0, message_id, method, list(args)], deadline)
        while message_id not in self.responses:
            self.pump(deadline)
        error, value = self.responses.pop(message_id)
        if error is not None:
            raise AcquisitionError(f"{method}: {error}")
        return value

    def lua(self, source: str, *args: Any, timeout: float | None = None) -> Any:
        return self.request("nvim_exec_lua", source, list(args), timeout=timeout)

    def input(self, keys: str) -> None:
        accepted = self.request("nvim_input", keys)
        if accepted != len(keys.encode("utf-8")):
            raise AcquisitionError(
                f"nvim_input accepted {accepted} of {len(keys.encode('utf-8'))} bytes; no automatic input retry"
            )

    def _startup_mode_response(self, mode: dict[str, Any], received_ns: int) -> None:
        self.startup_last_mode = mode
        if not self.startup_prompt_handling:
            return
        if mode.get("mode") != "r":
            self._startup_return_latched = False
            return
        # "r" is the documented Hit-enter mode. No arbitrary input is sent
        # for normal, more, confirm, command-line, or other blocking states.
        prompt = [
            "".join(row).rstrip()
            for row in self.screen.grids.get(1, [])
            if "".join(row).strip()
        ]
        if self._startup_return_latched and prompt == self._startup_last_prompt:
            return
        self._startup_return_latched = True
        self._startup_last_prompt = prompt
        request_id = self.next_id
        self.next_id += 1
        self._startup_input_request = request_id
        evidence = {
            "number": len(self.startup_prompt_acknowledgements) + 1,
            "detected_at_perf_ns": received_ns,
            "detected_at_unix_ns": time.time_ns(),
            "detector": "fast nvim_get_mode mode=r (Hit-enter prompt)",
            "mode": mode,
            "rendered_prompt_lines": prompt,
            "flush_count": self.screen.flushes,
            "input": "<CR>",
            "input_request_id": request_id,
            "dispatched_at_perf_ns": time.perf_counter_ns(),
        }
        self.startup_prompt_acknowledgements.append(evidence)
        # nvim_input is api-fast, so it can answer even while nvim_ui_attach
        # or the first deferred Lua observer is still awaiting initialization.
        self.send([0, request_id, "nvim_input", ["<CR>"]], self.operation_deadline)

    def _deadline_error(self) -> AcquisitionTimeout:
        rows = ["".join(row).rstrip() for row in self.screen.grids.get(1, [])]
        prompt = next(
            (
                row
                for row in reversed(rows)
                if "Press ENTER" in row or "type command to continue" in row
            ),
            None,
        )
        suffix = (
            f"; UI is blocked at return prompt: {prompt!r}; startup acknowledgements={len(self.startup_prompt_acknowledgements)}"
            if prompt
            else ""
        )
        return AcquisitionTimeout("Neovim RPC/readiness deadline expired" + suffix)

    def _dispatch(self, message: Any, received_ns: int) -> None:
        kind = message[0]
        if kind == 1:
            if message[1] == self._startup_mode_request:
                self._startup_mode_request = None
                if message[2] is not None:
                    raise AcquisitionError(f"startup fast nvim_get_mode: {message[2]}")
                self._startup_mode_response(message[3], received_ns)
                return
            if message[1] == self._startup_input_request:
                self._startup_input_request = None
                evidence = self.startup_prompt_acknowledgements[-1]
                evidence["input_response_at_perf_ns"] = received_ns
                evidence["accepted_bytes"] = message[3]
                if message[2] is not None or message[3] != 4:
                    raise AcquisitionError(
                        f"startup return-prompt acknowledgement rejected: {message[2] or message[3]}"
                    )
                return
            self.responses[message[1]] = (message[2], message[3])
            return
        if kind == 0:
            # No client-side functions are advertised; fail honest unexpected
            # requests instead of leaving Neovim blocked forever.
            self.send(
                [
                    1,
                    message[1],
                    [0, "benchmark client does not implement requests"],
                    None,
                ]
            )
            return
        if kind != 2:
            raise AcquisitionError(f"invalid RPC message type: {kind!r}")
        method, arguments = message[1:]
        if method == "poincare_benchmark":
            token, status, evidence = arguments
            if token in self.completions:
                raise AcquisitionError(f"duplicate completion token: {token}")
            self.completions[token] = {
                "status": status,
                "oracle": evidence,
                "oracle_received_ns": received_ns,
                "flush_received_ns": None,
            }
            if token == "startup":
                self.startup_prompt_handling = False
                self.startup_prompt_stopped_ns = received_ns
        elif method == "redraw":
            for event in arguments:
                for event_arguments in event[1:]:
                    if self.screen.apply(event[0], event_arguments):
                        # Only ordered RPC notification -> later redraw flush
                        # establishes causality. Earlier flushes cannot qualify.
                        for completion in self.completions.values():
                            if completion["flush_received_ns"] is None:
                                completion["flush_received_ns"] = received_ns
                                completion["screen"] = self.screen.snapshot()
        elif len(self.notifications) < 100:
            self.notifications.append({"method": method, "arguments": arguments})

    def pump(self, deadline: float, *, allow_idle: bool = False) -> None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            if allow_idle:
                return
            raise self._deadline_error()
        if self.startup_prompt_handling:
            now = time.monotonic()
            if (
                self._startup_mode_request is None
                and self._startup_input_request is None
                and now >= self._startup_next_mode_check
            ):
                request_id = self.next_id
                self.next_id += 1
                self._startup_mode_request = request_id
                self._startup_next_mode_check = now + 0.001
                self.send([0, request_id, "nvim_get_mode", []], deadline)
            events = self.selector.select(min(remaining, 0.001))
        else:
            events = self.selector.select(remaining)
        if not events:
            if allow_idle or self.startup_prompt_handling:
                return
            raise self._deadline_error()
        assert self.process is not None and self.process.stdout is not None
        data = os.read(self.process.stdout.fileno(), 262144)
        if not data:
            raise AcquisitionError(
                f"Neovim exited/closed RPC output (returncode={self.process.poll()})"
            )
        self.unpacker.feed(data)
        for message in self.unpacker:
            received_ns = time.perf_counter_ns()
            self.last_message_ns = received_ns
            self._dispatch(message, received_ns)

    def wait_completion(
        self, token: str, timeout: float | None = None
    ) -> dict[str, Any]:
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        if self.operation_deadline is not None:
            deadline = min(deadline, self.operation_deadline)
        while (
            token not in self.completions
            or self.completions[token]["flush_received_ns"] is None
        ):
            self.pump(deadline)
        return self.completions.pop(token)

    def close(self) -> dict[str, Any]:
        assert self.process is not None
        cleanup = kill_process_group(self.process)
        self.selector.close()
        for pipe in (self.process.stdin, self.process.stdout):
            if pipe is not None:
                pipe.close()
        self.stderr_file.seek(0)
        stderr = self.stderr_file.read().decode("utf-8", errors="replace")
        self.stderr_file.close()
        return {
            "cleanup": cleanup,
            "stderr": stderr,
            "notifications": self.notifications,
            "startup_prompts": {
                "policy": "only documented Hit-enter mode=r during startup; real <CR>; no human think time; no later automatic acknowledgement",
                "count": len(self.startup_prompt_acknowledgements),
                "acknowledgements": self.startup_prompt_acknowledgements,
                "last_mode": self.startup_last_mode,
                "handling_stopped_at_perf_ns": self.startup_prompt_stopped_ns,
            },
        }
