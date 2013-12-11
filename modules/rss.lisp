#|
  This file is a part of Colleen
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :org.tymoonnext.colleen)
(defpackage org.tymoonnext.colleen.mod.rss
  (:use :cl :colleen :lquery))
(in-package :org.tymoonnext.colleen.mod.rss)

(defparameter *save-file* (merge-pathnames "rss-feed-save.json" (merge-pathnames "config/" (asdf:system-source-directory :colleen))))

(define-module rss () 
  ((%feeds :initform (make-hash-table :test 'equalp) :accessor feeds)
   (%thread :accessor thread))
  (:documentation "Update about new RSS feed items."))

(defclass feed ()
  ((%name :initarg :name :initform (error "Name required.") :accessor name)
   (%url :initarg :url :initform (error "URL required.") :accessor url)
   (%report-to :initarg :report-to :initform () :accessor report-to)
   (%last-item :initarg :last-item :initform NIL :accessor last-item))
  (:documentation "Class representation of an RSS feed."))

(defmethod print-object ((feed feed) stream)
  (print-unreadable-object (feed stream :type T)
    (format stream "~a" (name feed))))

(defclass feed-item ()
  ((%title :initarg :title :accessor title)
   (%description :initarg :description :accessor description)
   (%link :initarg :link :accessor link)
   (%guid :initarg :guid :accessor guid)
   (%publish-date :initarg :publish-date :accessor publish-date))
  (:documentation "Class representation of an RSS feed item."))

(defmethod print-object ((item feed-item) stream)
  (print-unreadable-object (item stream :type T)
    (format stream "~a ~a~@[ ~a~]" (guid item) (title item) (publish-date item))))

(defmethod start ((rss rss))
  (load-feeds rss)
  (dolist (feed (feeds rss))
    (update feed))
  (setf (thread rss) (bordeaux-threads:make-thread 
                      #'(lambda () (check-loop rss))
                      :initial-bindings `((*servers* . ,*servers*)))))

(defmethod stop ((rss rss))
  (save-feeds rss))

(defmethod save-feeds ((rss rss))
  (v:info :rss "Saving feeds...")
  (with-open-file (stream *save-file* :direction :output :if-exists :supersede :if-does-not-exist :create)
    (let ((data (loop for feed being the hash-values of (feeds rss)
                   collect (cons (intern (name feed) :KEYWORD)
                                 (list (cons :URL (url feed))
                                       (cons :REPORT (list (report-to feed))))))))
      (json:encode-json data stream)
      (v:info :rss "~a feeds saved." (length (feeds rss))))))

(defmethod load-feeds ((rss rss))
  (v:info :rss "Loading feeds...")
  (with-open-file (stream *save-file* :if-does-not-exist NIL)
    (when stream
      (let ((feeds (loop for feed in (json:decode-json stream)
                      for name = (car feed)
                      for url = (cdr (assoc :URL (cdr feed)))
                      for report = (first (cdr (assoc :REPORT (cdr feed))))
                      collect (make-instance 'feed :name name :url url :report-to report))))
        (setf (feeds rss) feeds)
        (v:info :rss "~a feeds loaded." (length feeds))))))

(defmethod check-loop ((rss rss))
  (v:debug :rss "Starting check-loop.")
  (loop while (active rss)
     do (sleep (* 60 5)) 
       (loop for feed being the hash-values of (feeds rss)
          do (handler-case 
                 (let ((update (update feed)))
                   (when update
                     (v:info :rss "~a New item: ~a" feed update)
                     (dolist (channel (report-to feed))
                       (irc:privmsg (cdr channel) 
                                    (format NIL "[RSS UPDATE] ~a: ~a ~a" 
                                            (name feed) (title update) (link update)) 
                                    :server (get-server (car channel))))))
               (error (err)
                 (v:warn :rss "Error in check-loop: ~a" err)))))
  (v:debug :rss "Leaving check-loop."))

(defmethod update ((feed feed))
  (v:debug :rss "~a updating." feed)
  (let ((newest (first (get-items feed :limit 1))))
    (unless (and (last-item feed) (string-equal (guid (last-item feed)) (guid newest)))
      (setf (last-item feed) newest)
      newest)))

(defmethod get-items ((feed feed) &key limit)
  (let ((lquery:*lquery-master-document*)
        (drakma:*text-content-types* (cons '("application" . "xml")
                                           drakma:*text-content-types*)))
    ($ (initialize (drakma:http-request (url feed)) :type :XML))
    (loop for node in ($ "item")
       for i from 0
       while (or (not limit) (< i limit))
       collect (make-instance 'feed-item 
                              :title ($ node "title" (text) (node))
                              :description ($ node "description" (text) (node))
                              :link ($ node "link" (text) (node))
                              :guid ($ node "guid" (text) (node))
                              :publish-date ($ node "pubDate" (text) (node))))))

(define-group rss :documentation "Manage RSS feeds.")

(define-command (rss add) (name url &optional (report-here T)) (:authorization T :documentation "Add a new RSS feed to check for updates.")
  (when (string-equal report-here "nil") (setf report-here NIL))
  (if (gethash name (feeds module))
      (respond event "A feed with name \"~a\" already exists!" name)
      (let ((feed (make-instance 'feed :name name :url url :report-to (when report-here (list (cons (name (server event)) (channel event)))))))
        (update feed)
        (setf (gethash name (feeds module)) feed)
        (v:info :rss "Added feed: ~a" feed)
        (respond event "Feed ~a added!" name))))

(define-command (rss remove) (name) (:authorization T :documentation "Remove an RSS feed.")
  (if (gethash name (feeds module))
      (progn 
        (remhash name (feeds module))
        (respond event "Feed ~a removed!" name))
      (respond event "No feed called \"~a\" could be found!" name)))

(define-command (rss watch) (name) (:authorization T :documentation "Start watching a feed on this channel.")
  (pushnew (cons (name (server event)) (channel event)) (report-to module))
  (respond event "Now watching ~a on this channel." name))

(define-command (rss unwatch) (name) (:authorization T :documentation "Stop watching a feed on this channel.")
  (setf (report-to module) (delete-if #'(lambda (el) (and (eql (name (server event)) (car el))
                                                          (string-equal (channel event) (cdr el))))
                                      (report-to module)))
  (respond event "No longer watching ~a on this channel." name))

(define-command (rss latest) (name) (:documentation "Get the latest feed item.")
  (let ((item (first (get-items (gethash name (feeds module)) :limit 1))))
    (respond event "~a: ~a ~a~@[ ~a~]" (nick event) (title item) (link item) (publish-date item))))
