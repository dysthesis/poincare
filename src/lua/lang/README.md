Programming language support
============================

This module defines how support for different languages by separating mechanism
for policy. That is,

- `modules/` defines the _mechanisms_ that are used to support some language;
  for example, `modules/formatter.lua` defines how the formatter for a language
  is executed, and
- `specs/` defines the _policies_ for these mechanisms for different 
  languages; for example, `specs/lua.lua` provides a table which defines,
  among others, what _formatter_ to use for Lua.

## LSP display

Server inlay-hint refreshes retain the displayed hints until a current response
replaces them; a current empty or nil response removes them. Request-local
identity rejects canceled or superseded replies, even when an in-process server
responds inline during cancellation or replacement issuance. Current synchronous
responses and customized client handlers remain supported. Hidden buffers
refresh when shown again. Disabling hints or detaching the client still clears
them.
Diagnostics keep their previous decorations while automatic updates are
deferred in Insert mode (`update_in_insert = false`); the latest cached update,
including an empty list, is displayed on `InsertLeave`, not `CursorHoldI`.
Deferred empty updates keep their namespace enumerable without contributing to
`vim.diagnostic.get()` or `count()`. Explicit hide/reset/disable operations,
including buffer-wide and global operations, still clear immediately and cancel
the deferred display. Enabling `update_in_insert` also applies a pending empty
update immediately.

These are native runtime fixes in `nix/neovim-display.patch`, applied after the
nightly overlay by `nix/neovim-display-overlay.nix` to the packaged, dev-shell
and test Neovim. The patch targets pin `d039f19`; when updating that pin, review
the three patched Lua modules and run `just test-regression lsp_display` to check
request identity/reentrancy, retained decorations, accepted-empty results,
unscoped cleanup and option changes.

## Lua workspace libraries

Ordinary Lua projects do not automatically index Neovim's runtime. Their LuaLS
client library is empty, including the unscoped configuration LuaLS uses as a
fallback. LuaJIT, module search paths, hints and the other LuaLS settings are
unchanged.

The function-based root resolver adds no event-loop turn when it resolves
synchronously. `nix/neovim-root.patch` changes the pinned `d039f19` runtime to
start only after the resolver returns; asynchronous replies are still scheduled,
including callbacks from fast events. Omitting the callback still skips
activation. Native root-marker fallback, workspace requirements and client reuse
remain unchanged. `nix/neovim-display-overlay.nix` applies this patch to the
packaged, dev-shell and test Neovim alongside the display fixes. When updating
the pin, review native root startup and run `just unit-test` for real LuaLS
synchronous/asynchronous startup and library-isolation coverage.

The runtime is added automatically only when the client's root is exactly
`stdpath('config')`, after path normalization and symlink resolution. Root
discovery keeps the ordered `.luarc.json`, `.luarc.jsonc`, then `.git` search.
When none is found, a file whose canonical containing directory is inside
`stdpath('config')` gets that config root, so markerless configurations and
unsaved files below new config subdirectories retain runtime support. Literal
`$NAME` path components are not expanded by this fallback. Without a marker,
other named buffers and unnamed buffers stay rootless; the working directory
alone does not opt them into config support. Native marker discovery for an
unnamed buffer still starts at the working directory. A marker selecting a root
above the config directory, or a separate project rooted below it, does not
qualify. A similarly named sibling directory does not qualify either.

An external Neovim plugin or configuration repository can opt in with a
project-root `.luarc.json` (or `.luarc.jsonc`):

```json
{
  "workspace.library": ["${env:VIMRUNTIME}"]
}
```

LuaLS expands `${env:VIMRUNTIME}` using the environment inherited from Neovim;
no absolute runtime path needs to be committed. Additional library paths can
be included in that list; this repository opts in through `.luarc.jsonc`, leaving
the ignored local `.luarc.json` available for overrides. Merely having an
`init.lua` or a plugin-like folder name does not opt a repository in.

An explicitly supplied client `settings.Lua.workspace.library` is preserved,
including an empty Lua list `{}`. LuaLS applies project configuration after
client settings: `.luarc.json` takes priority over `.luarc.jsonc`, and its
`workspace.library` replaces the client library for that project. The fallback
scope still uses client settings; an explicit empty client library disables
automatic runtime loading there as well. These defaults are selected per
client before initialization, not changed during buffer attachment.

## Linting

Language specs register nvim-lint names through `modules/linters.lua` (one name
or a list of names). nvim-lint loads on the first buffer read or write and runs
available executables on reads and writes. If the initial file has not yet
received its filetype at load time, linting waits for its `FileType` event; this
also covers a file supplied as the first Neovim command-line argument. A later
`FileType` event can lint a buffer after its filetype changes. Clean results
replace earlier diagnostics from the same linter.

## SQLite

For SQL buffers, `:SQLiteUse {file}` sets the buffer's Dadbod database URL to
the normalized absolute filesystem path. URL-sensitive path characters,
including literal `%`, `?`, `#`, and spaces, are percent-encoded before Dadbod
decodes the URL; a filename containing `%20` is not redirected to a filename
containing a space. SQL queries then use the selected physical database file.
