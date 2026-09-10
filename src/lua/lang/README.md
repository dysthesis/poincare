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
