#|
 This file is a part of Colleen
 (c) 2014 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :org.tymoonnext.colleen)
(defpackage org.tymoonnext.colleen.mod.markov-twitter-bridge
  (:use :cl :colleen :events))
(in-package :org.tymoonnext.colleen.mod.markov-twitter-bridge)

(define-module markov-twitter-bridge () ()
  (:documentation "A very simple module that outputs a string generated by the markov module every now and again."))

(defmethod start ((mod markov-twitter-bridge))
  (with-module-thread (mod)
    (loop do (progn
               (markov-tweet)
               (sleep (+ (* 60 15) (random (* 8 (* 60 60)))))))))

(define-command markov-tweet () (:documentation "Tweets a markov message.")
  (markov-tweet))

(defun markov-tweet ()
  (let ((message (loop for msg = (org.tymoonnext.colleen.mod.markov::generate-string (get-module :markov))
                       until (<= (length msg) 140)
                       finally (return msg))))
    (chirp:tweet message)))
