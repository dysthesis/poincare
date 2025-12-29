(local M {})

(fn buffer-path [bufnr]
  (let [name (vim.api.nvim_buf_get_name bufnr)]
    (if (and name (not= name ""))
        name
        (vim.fn.getcwd))))

(fn M.root-from [markers ?fallback]
  (fn [bufnr on-dir]
    (let [base (buffer-path bufnr)
          root (vim.fs.root base markers)
          fallback
          (if (= (type ?fallback) :function)
              (?fallback bufnr base)
              ?fallback
              (vim.fs.root base ?fallback)
              nil)]
      (on-dir (or root fallback)))))

(fn M.server [spec]
  (vim.tbl_deep_extend "force" {:capabilities {}} spec))

M
