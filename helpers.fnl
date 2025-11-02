;; This file defines some helper functions that are used throughout this
;; configuration.

(macro plugin [name & kvs]
  "Declare and configure a plugin"
  ;; Validate the arguments
  (when (not (= :string (type name)))
    ;; check that the first argument is a string
    (error "[plugin] the first argument must be a string representing the plugin name"))
  (when (not (= 0 (% (length kvs) 2)))
    ;; check that the number of kvs is even
    (error "[plugin] keyword arguments must come in pairs")))
