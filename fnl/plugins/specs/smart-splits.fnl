(require-macros :plugins.helpers)

(local km (require :utils.keymap))

(local resize-left (km.lazy-call :smart-splits [:resize_left]))
(local resize-down (km.lazy-call :smart-splits [:resize_down]))
(local resize-up (km.lazy-call :smart-splits [:resize_up]))
(local resize-right (km.lazy-call :smart-splits [:resize_right]))
(local move-left (km.lazy-call :smart-splits [:move_cursor_left]))
(local move-down (km.lazy-call :smart-splits [:move_cursor_down]))
(local move-up (km.lazy-call :smart-splits [:move_cursor_up]))
(local move-right (km.lazy-call :smart-splits [:move_cursor_right]))
(local move-prev (km.lazy-call :smart-splits [:move_cursor_previous]))

(use "smart-splits.nvim"
   :keys
   [(keymap "<A-h>" resize-left "Resize left")
    (keymap "<A-j>" resize-down "Resize down")
    (keymap "<A-k>" resize-up "Resize up")
    (keymap "<A-l>" resize-right "Resize right")

    (keymap "<C-h>" move-left "Move cursor left")
    (keymap "<C-j>" move-down "Move cursor down")
    (keymap "<C-k>" move-up "Move cursor up")
    (keymap "<C-l>" move-right "Move cursor right")
    (keymap "<C-\\>" move-prev "Move cursor to previous split")]

   :after
   (fn []
     ((. (require :smart-splits) :setup) {})))
