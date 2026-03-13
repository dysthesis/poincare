std = "lua51"

globals = {
  "vim",
}

exclude_files = {
  "nix/**",
  ".direnv/**",
  "result/**",
}

max_line_length = 120

-- Reduce noise: ignore missing fields on the `vim` table that plugins add at runtime.
ignore = {
  "212/_G.vim.*",
}
