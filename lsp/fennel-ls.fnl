;; lsp/fennel-ls.fnl

(local api vim.api)

(fn has-fls-project? [path]
  (let [fnlpath (vim.fs.joinpath path "flsproject.fnl")
        stat (vim.uv.fs_stat fnlpath)]
    (= "file" (?. stat :type))))

(fn root-dir [bufnr on-dir]
  (let [fname (api.nvim_buf_get_name bufnr)
        iter (vim.iter (vim.fs.parents fname))
        root (iter:find has-fls-project?)]
    (on-dir (or root (vim.fs.root 0 ".git")))))

{:cmd ["fennel-ls"]
 :filetypes ["fennel"]
 :root_dir root-dir
 :settings {}
 :capabilities {:offsetEncoding ["utf-8" "utf-16"]}}
