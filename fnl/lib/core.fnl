(require-macros :lib.utils)

(local M {})

;; -------------------- ;;
;;        UTILS         ;;
;; -------------------- ;;
(lambda set* [name val]
  "sets variable 'name' to 'val' and returns its value."
  `(do (set-forcibly! ,name ,val) ,name))


;; -------------------- ;;
;;       GENERAL        ;;
;; -------------------- ;;
(fun or= [val ...]
  "checks if 'val' is equal to any one of '...'"
  (local eq [])
  (each [_ arg (ipairs [...])]
    (table.insert eq `(= ,(sym :__val__) ,arg)))
  `(let [,(sym :__val__) ,val]
    (or ,(unpack eq))))


;; -------------------- ;;
;;       CHECKING       ;;
;; -------------------- ;;
(fun string? [x]
  "checks if 'x' is of string type."
  `(= :string (type ,x)))

(fun number? [x]
  "checks if 'x' is of number type."
  `(= :number (type ,x)))

(fun table? [x]
  "checks if 'x' is of table type."
  `(= :table (type ,x)))

(fun odd? [x]
  "checks if 'x' is mathematically of odd parity."
  `(and ,(number? x)
        (= 1 (% ,x 2))))


;; -------------------- ;;
;;        NUMBER        ;;
;; -------------------- ;;
(lun inc! [int]
  "increments 'int' by 1."
  `(+ ,int 1))


;; -------------------- ;;
;;        STRING        ;;
;; -------------------- ;;
(lun append! [v str]
  "appends 'str' to variable 'v'."
  (check [:sym (as var v)])
  (set* v (list `.. v str)))


:return M
