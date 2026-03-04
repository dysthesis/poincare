# Poincare

This is my personal Neovim configuration that has the twin goals of being 

- as minimal as possible, but not more, and
- as fast as possible.

The former means that minimality is achieved with respect to functionality: a
configuration is minimal if it achieves the required functionality with the
least amount of code possible. Any less, and it is not minimal -- it is simply
insufficient.

In general, the goal of minimality is robustness, stability, and reliability.
I understand the Lua layer to be, while extremely useful to extend the 
capabilities of Neovim, necessarily more brittle than the C core itself.

Of course, I don't think, at the moment, that there is such a thing as being
"too fast". Therefore, we aim to make it as fast as possible without sacrificing
functionality or minimality.

## Use of plugins

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

## Requirements

In order to evaluate minimality, we would necessarily require a specification of
the required functionality to satisfy.

I use Neovim as an editor for code and prose. Hence, the specification expands
on three general categories:

- editing in general,
- editing code, and
- editing prose.

### General editing

Without going into specifically _code_ or _text_, we can ascertain that in what
we are editing in Neovim is _text_ -- in general, we are not going to be editing
binary files, databases, _etc._ (strictly speaking, I'm sure plugins for those
exist, but they are not what I believe Neovim is made for).

Text, by itself, forms structure, and while (Neo)vim inherently provides ample
primitives to work with text structures, given its text-as-objects paradigm, we
can (and should!) improve on that.

#### Lines

One of the most basic structures of text is lines. (Neo)vim provides motions as
navigation primitives to move around with respect to it. However, to be able to
determine the most efficient motions to navigate to a given target line, it helps
to know the exact offset of it relative to the current cursor's position. Hence,
relative line numbering is always enabled.

#### Syntax awareness

I think tree-sitter integration is a must.

## References

- [yobibyte - why I got rid of all my neovim plugins]
