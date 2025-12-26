# Notes

## Fennel refactoring

Instead of relying on plugins providing runtime environment to configure Neovim
with Fennel, we can instead rely on Nix to construct a build pipeline, compiling
them into Lua. From the perspective of Neovim, it is as if the Fennel code never
existed. We therefore construct three subcomponents for the final derivation:

- a Fennel builder, which finds any `**.fnl` into the corresponding `**.lua`;
  the `fnl/` directory should also be outputted as `lua/` instead, and the final
  derivation must be a directory whose structure mirrors the original Fennel
  codebase, but with Lua instead,
- a [Neovim wrapper](https://ayats.org/blog/neovim-wrapper), ideally one which
  exposes a passthru helper to declare plugins to install (_e.g._ 
  `wrapper.withPlugins (p: with p; [...])`), and
- a final derivation which puts it all together; it pulls the source directory,
  feeds it to the Fennel builder, and feeds the resulting Lua configuration path
  to the Neovim wrapper.

### Notes on language server configuration

For `fennel-ls` to behave properly, we'd need to export a `flsproject.fnl`
informing it on where to find "libraries". We can achieve this by constructing
a text derivation,

```nix
  fennelProject = pkgs.writeText "flsproject.fnl" ''
    {:fennel-path "${poincareConfig.runtimePath}/?.fnl;${poincareConfig.runtimePath}/?/init.fnl;./?.fnl;./?/init.fnl;fnl/?.fnl;fnl/?/init.fnl"
     :extra-globals "vim vim.api vim.fn vim.loop fennel.sym?"}
  '';

and constructing a shell hook to symlink it to the project root directory

```nix
pkgs.mkShell {
  # ...other stuff
  shellHook = ''
    ln -sf ${fennelProject} flsproject.fnl
  '';
}
```
