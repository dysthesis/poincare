(local M {})

(fn M.apply-highlights [specs ?transform]
  (each [_ spec (ipairs specs)]
    (let [[group opts] spec
          out (if ?transform (?transform opts) opts)]
      (vim.api.nvim_set_hl 0 group out))))

M
