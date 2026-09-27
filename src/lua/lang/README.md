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
