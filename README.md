# Poincare

This is my personal Neovim configuration that has the twin goals of being

- as minimal as possible, but not more, and
- as fast as possible.

This document is to be updated with justifications for each feature addition
made.

I've been reading [a] [few] [posts] about having a minimal configuration for
Neovim. While each of them made good cases on keeping your configuration minimal,
I don't believe they provide the complete picture. These configurations and
plugins provides do provide some functionality, at the cost of complexity and
perhaps some maintenance burden. It is therefore a trade-off, and whether it is
worth making depends on the intended functionality. In other words,

> "Everything should be made as simple as possible, but not simpler."
>
> — Albert Einstein

## Usage

This is a Nix flake packaging my Neovim configuration -- thus, one may run it
using Nix by running `nix run`.

The packaged editor only includes editor-intrinsic tools, such as file search,
text search, Tree-sitter support, and the debugger adapter. Project-specific
tools, including language servers, formatters, linters, compilers, and build
tools, are expected to come from the active project environment, usually a Nix
development shell.

### Development

The development toolchain is installed using Nix shells. To enter the
development shell, either run `nix develop`, or, if one uses Direnv, permit it
to load the environment by running `direnv allow`.

## Minimality

Minimality is achieved with respect to functionality: a configuration is minimal
if it achieves the required functionality with the least amount of code possible.
Any less, and it is not minimal -- it is simply insufficient.

In general, the goal of minimality is robustness, stability, and reliability.
I understand the Lua layer to be, while extremely useful to extend the
capabilities of Neovim, necessarily more brittle than the C core itself.

Of course, I don't think, at the moment, that there is such a thing as being
"too fast". Therefore, we aim to make it as fast as possible without sacrificing
functionality or minimality.

### Use of plugins

I think that a plugin should be used if a given functional requirement cannot
be solved in a simple manner that requires only a modest amount of code, for
some definition of modest. I think that there exist a threshold such that, if
the addition of a sufficiently large amount of Lua code cannot be avoided,
relying on plugins would be preferable, as it would provide community support
and maintenance.

A custom solution is considered _modest_, and thus preferable to a plugin, if

- it is _stateless_,
- it relies strictly on standard Neo(vim) API, _and_
- it is under 100 lines of code.

If any of the above criterion is not fulfilled, then a plugin should be used
(unless, of course, one does not exist!).

## Speed

Speed refers to two distinct but related factors, namely

- the speed and responsiveness of Neovim itself, and
- the speed of the user (me) writing code.

It should be self-evident that a faster Neovim would result in faster
development of code -- if nothing else, the editor's responsiveness is conducive
to focus. But the editor's responsiveness is not the only factor relevant to
development speed.

## On editing

Editing can be split into

- navigation,
- selection, and
- insertion.

Technically, there is also _deletion_, but I consider that a trivial operation
with respect to selection; the two can be considered synonymous, as the former
is one keystroke away from the latter.

### Vim motions enhancement

I think that the first two, namely navigation and selection, are the domain of
Vim motions, which allows the manipulation of text as "objects". These can be
further refined with syntax comprehension, which is the justification for the
inclusion of nvim-textobject

### Completion menu

Neovim has a decent enough built-in completion menu -- if not for the minor
inconvenience of its sorting algorithm, which I have found to suggest irrelevant
results before relevant ones. For example, when typing `Decidable` in

```lean
inductive NodeKind
  | note
  | task
  | event
  | account
  | transaction
  | posting
  deriving Decidable, Repr
```

the suggestions

- `Array.instDecidableEmpEq`,
- `Array.instDecidableEmpEqImpl`,
- ...

...and 29 other such entries were suggested before `Decidable` or `DecidableEq`.

Hence, I have decided to use `blink.cmp`, additionally giving me a bonus of
completion speed. One day I will revisit the use of the native completion menus.

### Delimiter manipulation

Delimiter manipulation can be further decomposed into two components: that is,

- auto-pairing, and
- adding, removing, or changing surrounding delimiters.

While a naïve auto-pairing solution -- simply inserting a closing delimiter . The solution is to implement asynchrony, which, again, renders
it nontrivial. We therefore use
after the cursor whenever an opening delimiter is typed in -- having it handle
edge cases would cause the complexity of such a module to explode; an example of
this would be to have it not insert the closing delimiter if an un-opened one is
found. That is, it's not difficult to implement a dumb auto-pair, but it's
considerably more difficult to make a smart one. Hence, I opted to use a plugin
for this. I selected [ultimate-autopair.nvim] as it seems to work exactly as I
would imagine it to. Admittedly, though, I haven't tried [nvim-autopairs].

Adding, removing, or changing surrounding delimiters is even more difficult
outright, and I think [mini.surround] does an excellent job with an acceptable
size of code.

## On development iteration

Unique to editing code is the iterative nature of development -- after changes
are made, the developer would generally run static analyses, tests, debugging
tools, _etc._ I think this component is particularly interesting as, though it
should be self-evident that integrating the capabilities to do these in-editor
should provide _some_ boon to development speed, Neovim itself is a terminal
editor, and thus there is only a trivial barrier between the editor and the
command line, where these checks can be executed natively, without adding any
burden of complexity on the editor. Thus, I think the value of such an
integration with respect to its complexity costs remain more subtle and less
clear than those of other components.

### Static analysis

The integration of static analysis in the editor has been made rather trivial
with the advent of the [Language Server Protocol]. While some have claimed to
have flaky experiences with them, I have had no such experience so far, so I
will continue using them. Maybe I've just been using well-made LSP servers.

#### Linting and formatting

Similar to what I have found with auto-pairing setup, while naïve
implementations of formatting (and to a lesser extent, linting, as it involves
interacting with the diagnostic and virtual text APIs) is trivial to implement
(hook some function that runs the appropriate formatter and linter, say, on
save), such an implementation causes Neovim to stutter (much like Emacs, Neovim
is single-threaded as well; it just gets away with it more due to its smaller
and leaner size). The solution is to implement asynchrony, which, again, renders
it nontrivial. We therefore use [nvim-lint] and [conform.nvim].

### Dynamic analysis

I would guess that the cost to complexity might be worth it for testing
integration if we can make it such that tests are run asynchronously, in the
background, on every save, with its results being displayed in inline hints
and an optional toggleable pane, such that we get as immediate of a feedback
as possible.

#### Debugging integration

I like to have my debugger with me at all times, and even moreso to have it
in my editor, allowing it to show the values of variables during execution as
virtual text. It is much nicer to use than debug printing, though also a bit
more of a pain in the ass to set up (though you only have to do it once!). I do
not imagine implementing support for DAP (an entire protocol!) to consist of a
trivial amount of code (though I'm open to be proven wrong), and thus I defer
again to plugins ([nvim-dap], [nvim-dap-ui], [nvim-dap-virtual-text]).

### Formatting

Technically, formatting without plugins [is possible], but not without a
nontrivial amount of code. Therefore, we rely on plugins instead.

## On reading

Reading code is just as important as writing it, but I currently do not see any
way of "optimising" it beyond syntax highlighting to create emphasis. I agree
with [tonsky's take on syntax highlighting], though the exact colours used in
Alabaster isn't exactly to my taste, so I might fork [lackluster.nvim] and
adjust it accordingly (though it is plenty minimal enough, anyways!).

## Miscellaneous notes

The `nixd` LSP server is configured to find host-dependent options by assuming
that the NixOS configuration is packaged under the same name as the hostname.

## References

- [yobibyte - why I got rid of all my neovim plugins]
- [How to get human rights in Neovim without plugins (2025 edition)]

[a]: https://yobibyte.github.io/vim.html
[conform.nvim]: https://github.com/stevearc/conform.nvim
[few]: https://blog.erikwastaken.dev/posts/2023-05-06-a-case-for-neovim-without-plugins.html
[how to get human rights in neovim without plugins (2025 edition)]: https://boltless.me/posts/neovim-config-without-plugins-2025/
[is possible]: https://github.com/neovim/neovim/discussions/35602
[lackluster.nvim]: https://github.com/slugbyte/lackluster.nvim
[language server protocol]: https://microsoft.github.io/language-server-protocol/overviews/lsp/overview/
[mini.surround]: https://github.com/nvim-mini/mini.surround
[nvim-autopairs]: https://github.com/windwp/nvim-autopairs
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[nvim-dap-ui]: https://github.com/theHamsta/nvim-dap-virtual-text
[nvim-dap-virtual-text]: https://github.com/theHamsta/nvim-dap-virtual-text
[nvim-lint]: https://github.com/mfussenegger/nvim-lint
[posts]: https://wickstrom.tech/2024-08-12-a-flexible-minimalist-neovim.html
[tonsky's take on syntax highlighting]: https://tonsky.me/blog/syntax-highlighting/
[ultimate-autopair.nvim]: https://github.com/altermo/ultimate-autopair.nvim
[yobibyte - why i got rid of all my neovim plugins]: https://yobibyte.github.io/vim.html
