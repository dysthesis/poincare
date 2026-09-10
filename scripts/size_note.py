#!/usr/bin/env python3
"""Compatibility entry point for exact-commit size notes."""

from __future__ import annotations

import sys

try:
    from scripts import pipeline
except ModuleNotFoundError:
    import pipeline  # type: ignore[no-redef]


def main(argv: list[str] | None = None) -> int:
    return pipeline.main(["size-note", *(sys.argv[1:] if argv is None else argv)])


if __name__ == "__main__":
    raise SystemExit(main())
