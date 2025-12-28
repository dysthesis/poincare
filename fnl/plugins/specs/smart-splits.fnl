(require-macros :plugins.helpers)

(local lazy-call (. (require :utils.keymap) :lazy-call))

(local resize-left (lazy-call :smart-splits [:resize_left]))
(local resize-down (lazy-call :smart-splits [:resize_down]))
(local resize-up (lazy-call :smart-splits [:resize_up]))
(local resize-right (lazy-call :smart-splits [:resize_right]))
(local move-left (lazy-call :smart-splits [:move_cursor_left]))
(local move-down (lazy-call :smart-splits [:move_cursor_down]))
(local move-up (lazy-call :smart-splits [:move_cursor_up]))
(local move-right (lazy-call :smart-splits [:move_cursor_right]))
(local move-prev (lazy-call :smart-splits [:move_cursor_previous]))

(use "smart-splits.nvim"
     :event "DeferredUIEnter"
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
       ((. (require :smart-splits) :setup) {:at_edge "stop"})))
