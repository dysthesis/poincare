(require-macros :plugins.helpers)
(use "smart-splits.nvim"
   :keys
   [(keymap "<A-h>"
      (fn []
        ((. (require :smart-splits) :resize_left)))
      "Resize left")

    (keymap "<A-j>"
      (fn []
        ((. (require :smart-splits) :resize_down)))
      "Resize down")

    (keymap "<A-k>"
      (fn []
        ((. (require :smart-splits) :resize_up)))
      "Resize up")

    (keymap "<A-l>"
      (fn []
        ((. (require :smart-splits) :resize_right)))
      "Resize right")

    (keymap "<C-h>"
      (fn []
        ((. (require :smart-splits) :move_cursor_left)))
      "Move cursor left")

    (keymap "<C-j>"
      (fn []
        ((. (require :smart-splits) :move_cursor_down)))
      "Move cursor down")

    (keymap "<C-k>"
      (fn []
        ((. (require :smart-splits) :move_cursor_up)))
      "Move cursor up")

    (keymap "<C-l>"
      (fn []
        ((. (require :smart-splits) :move_cursor_right)))
      "Move cursor right")

    (keymap "<C-\\>"
      (fn []
        ((. (require :smart-splits) :move_cursor_previous)))
      "Move cursor to previous split")]

   :after
   (fn []
     ((. (require :smart-splits) :setup) {})))
