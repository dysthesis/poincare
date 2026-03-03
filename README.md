# Poincare

This is my personal Neovim configuration that has the twin goals of being 

- as minimal as possible, but not more, and
- as fast as possible.

The former means that minimality is achieved with respect to functionality: a
configuration is minimal if it achieves the required functionality with the
least amount of code possible. Any less, and it is not minimal -- it is simply
insufficient.

Of course, I don't think, at the moment, that there is such a thing as being
"too fast". Therefore, we aim to make it as fast as possible without sacrificing
functionality or minimality.

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

#### Syntax awareness

I think tree-sitter integration is a must.
