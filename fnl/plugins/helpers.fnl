(local M {})

(fn M.create [name opts]
  "Create a new plugin specification"
  (assert (= (type name) :string)
          "Plugin name must be a string!")
  (local spec (or opts {}))
  (tset spec 1 name)
  spec)

(fn M.use [name & kvs]
  "Macro entry point for defining plugin specifications."
  (assert (= (type name) :string)
          "Plugin name must be a string!")
  (assert (= 0 (% (# kvs) 2))
          "Expected even number of key/value pairs!")
  (local spec {})
  (tset spec 1 name)
  (for [i 1 (# kvs) 2]
    (let [k (. kvs i)
          v (. kvs (+ i 1))]
      (tset spec k v)))
  spec)

(fn M.keymap [lhs rhs desc]
  (local entry [lhs rhs])
  (when desc
    (set entry.desc desc))
  entry)

(fn M.normalise [modval]
  (if (not modval)
      []
      (= (type (. modval 1)) :string)
      [modval]
      modval))

(fn M.collect [modules]
  (local acc [])
  (each [_ name (ipairs modules)]
    (let [val (require name)
          specs (M.normalise val)]
      (each [_ spec (ipairs specs)]
        (table.insert acc spec))))
  acc)
      
(fn M.setup [modules]
  (local specs (M.collect modules))
  (local lz (require :lz.n))
  (lz.load specs))

M
