;; config/codelldb.fnl
;; Optional codelldb paths injected via environment variables.

(local luv (require :luv))

(fn getenv [name]
  (let [value (luv.os_getenv name)]
    (if (and value (not= value "")) value nil)))

(fn set-if-unset [k v]
  (when (and v (or (= nil (. vim.g k)) (= "" (. vim.g k))))
    (tset vim.g k v)))

(set-if-unset :codelldb_path (getenv "CODELLDB_PATH"))
(set-if-unset :liblldb_path (getenv "LIBLLDB_PATH"))
