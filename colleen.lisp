#|
  This file is a part of Colleen
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :org.tymoonnext.colleen)

(defun start-module (module-name)
  (let ((module (gethash module-name *bot-modules*)))
    (assert (not (null module)) () "Module ~a not found!" module-name)
    (v:info (intern (string-upcase (format NIL "MODULE.~a" module-name))) "Starting...")
    (start module)
    module))

(defun stop-module (module-name)
  (let ((module (gethash module-name *bot-modules*)))
    (assert (not (null module)) () "Module ~a not found!" module-name)
    (v:info (intern (string-upcase (format NIL "MODULE.~a" module-name))) "Stopping...")
    (stop module)
    module))

(defun auth-p (nick)
  (find nick (auth-users *current-server*) :test #'equal))

(defun remove-from-auth (nick &optional reason)
  (v:info (name *current-server*) "Removing ~a from authenticated list (~a)." nick reason)
  (setf (auth-users *current-server*)
        (delete nick (auth-users *current-server*) :test #'equal))
  nick)

(defun add-to-auth (nick &optional reason)
  (v:info (name *current-server*) "Adding ~a to authenticated list (~a)." nick reason)
  (pushnew nick (auth-users *current-server*) :test #'equal)
  NIL)

(defun handle (command prefix arguments)
  (let ((event (make-event command *current-server* prefix arguments)))
    (when event
      (v:debug (name *current-server*) "HANDLE EVENT: ~a" event)
      (handler-case
          (process-event event)
        (disconnect (err)
          (error err))
        (not-authorized (err)
          (v:warn (name *current-server*) "User ~a attempted to execute ~a, but is not authorized!" (nick (event err)) (command (event err)))
          (respond (event err) (fstd-message (event err) :not-authorized)))
        (invalid-arguments (err)
          (v:warn (name *current-server*) "Invalid arguments to ~a, expected ~a" (command err) (argslist err))
          (respond event "Invalid arguments. Expected: ~a" (argslist err)))
        #|(error (err)
          (v:warn (name *current-server*) "Unhandled condition: ~a" err))|#))))

(defun process-event (event)
  (loop for module being the hash-values of *bot-modules*
     if (active module)
     do (dispatch module event))

  (labels ((make-command (message prefix)
             (let ((args (split-sequence #\Space (string-trim '(#\Space) (subseq message (length prefix))))))
               (make-instance 'command-event
                              :server (server event)
                              :arguments (arguments event)
                              :prefix (prefix event)
                              :command (string-downcase (first args))
                              :cmd-args (cdr args))))

           (check-prefix-and-build (event)
             (loop for prefix in (config-tree :command :prefix)
                do (when (string= prefix "$NICK$") 
                     (setf prefix (format NIL "~a:" (server-config (name *current-server*) :nick))))
                  (if (and (> (length (message event)) (length prefix))
                           (string= (message event) prefix :end1 (length prefix)))
                      (return (make-command (message event) prefix))))))

    (when (eql (class-name (class-of event)) 'privmsg-event)
      (let ((event (check-prefix-and-build event)))
        (when event
          (v:debug (name (server event)) "Received command: ~a ~a" (command event) (arguments event))
          (unless (loop for module being the hash-values of *bot-modules*
                     for result = (when (active module) (dispatch module event))
                     if result do (return T))
            (respond event (fstd-message event :no-command))))))))

(define-module core () ())
(start (get-module :core))

(define-handler welcome core (welcome-event event)
  (let ((nickservpw (server-config (name (server event)) :nickservpw)))
    (when nickservpw
      (v:info (name (server event)) "Sending Nickserv: IDENTIFY ~a" nickservpw)
      (irc:privmsg "NickServ" (format NIL "IDENTIFY ~a" nickservpw))))
  
  (loop for chan in (server-config (name *current-server*) :channels)
     do (irc:join chan)
       (irc:privmsg chan (standard-message :join))))

(define-handler ping-reply core (ping-event event)
  (irc:pong (server1 event)))
