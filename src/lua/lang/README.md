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
