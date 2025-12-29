(require-macros :plugins.helpers)

(fn inc-rename []
  (let [cmd (.. ":IncRename " (vim.fn.expand "<cword>"))]
    (vim.api.nvim_feedkeys
      (vim.api.nvim_replace_termcodes cmd true false true)
      "n"
      false)))

(use "inc-rename.nvim"
     :cmd "IncRename"
     :keys
     [(keymap "<leader>cr" inc-rename "[C]ode [R]ename")]
     :after
     (fn []
       ((. (require :inc_rename) :setup))))
