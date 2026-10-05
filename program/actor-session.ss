;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss" GerbilAscentSessionContract)
        (only-in "evaluate.ss" gerbil-ascent-make-engine gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?))
(export gerbil-ascent-open-actor-session gerbil-ascent-session-cancel!
        gerbil-ascent-session-last-completed gerbil-ascent-session-close!
        gerbil-ascent-session-state)

(def Session. (.ref GerbilAscentSessionContract 'proto))

(def (session-failure message)
  (with-catch (lambda (failure) failure) (lambda () (error message))))

;;; Only the owner mutates source cuts, generation and publication. A run owns
;;; a fresh evaluator; its monitor cannot publish. Cancel credit is observed by
;;; the evaluator's round owner at traversal/batch checkpoints, never by polling
;;; the Session mailbox from a compute worker. Generation Naturals are unbounded.
(def (gerbil-ascent-open-actor-session program workers: (workers 2))
  (unless (and (exact-integer? workers) (> workers 0))
    (error "invalid ASCENT actor Session capacity" workers))
  (let* ((admitted (gerbil-ascent-make-engine program #t))
         (schema (.ref admitted '.schema)) (analysis (.ref admitted '.analysis))
         (relations (.ref program 'relations))
         (input-limit (.ref program 'max-input-facts)))
    (unless (and (andmap gerbil-ascent-canonical-set-storage-provider? (vector->list (vector-ref schema 9)))
                 (andmap gerbil-ascent-canonical-hash-index-provider? (vector->list (vector-ref schema 5)))
                 (andmap not (vector->list (vector-ref schema 7)))
                 (andmap not (vector->list (vector-ref schema 3)))
                 (andmap (lambda (rules) (andmap (lambda (rule) (vector-ref rule 5)) rules))
                         (vector->list (vector-ref analysis 5))))
      (error "ASCENT actor Session requires pure positive Set rules"))
    (def (copy-rows name rows)
      (let (slot (hash-get (vector-ref schema 4) name))
        (unless slot (error "unknown ASCENT relation" name))
        (let (width (vector-ref (vector-ref schema 2) (- slot 1)))
          (unless (and (list? rows) (andmap (lambda (row) (and (list? row) (= (length row) width))) rows))
            (error "invalid ASCENT actor Session source rows" name rows))
          (map (lambda (row) (map (lambda (value) value) row)) rows))))
    (let* ((initial (map (lambda (relation) (cons (.ref relation 'name) (copy-rows (.ref relation 'name) (.ref relation 'rows)))) relations))
           (gate (make-mutex 'ascent-session-lifecycle)) (closed? #f)
           (owner
            (spawn/name 'ascent-session-owner
             (lambda ()
               (let ((pending initial) (committed initial) (published #f)
                     (generation 0) (running #f) (closing []))
                 (def (reply! channel value) (thread-send channel value))
                 (def (snapshot)
                   ;; Compute outside the POO slot scope: `relations` inside its
                   ;; own slot expression would resolve recursively to that slot.
                   (let (next-relations
                         (map (lambda (relation)
                                (.o (:: @ relation) rows: (cdr (assq (.ref relation 'name) pending)))) relations))
                     (.o (:: @ program) relations: next-relations)))
                 (def (mark-canceled!)
                   (when running
                     (set! generation (+ generation 1))
                     (let (token (vector-ref running 1))
                       (mutex-lock! (vector-ref token 0))
                       (vector-set! token 1 #t)
                       (mutex-unlock! (vector-ref token 0)))))
                 (def (update! replacements append?)
                   (when running (error "ASCENT actor Session source update while running"))
                   (let* ((owned (map (lambda (replacement)
                                       (cons (car replacement) (copy-rows (car replacement) (cdr replacement)))) replacements))
                          (names (map car owned)))
                     (unless (= (length names) (length (delete-duplicates/hash names)))
                       (error "duplicate ASCENT actor Session replacement"))
                     (let (next (map (lambda (entry)
                                      (let (replacement (assq (car entry) owned))
                                        (if replacement
                                          (cons (car entry) (if append? (append (cdr entry) (cdr replacement)) (cdr replacement))) entry))) pending))
                       (when (> (apply + (map (lambda (entry) (length (cdr entry))) next)) input-limit)
                         (error "ASCENT actor Session input fact budget exceeded"))
                       (set! pending next) (set! generation (+ generation 1)) (void))))
                 (let loop ()
                   (match (thread-receive)
                     (['request channel operation args]
                      (with-catch (lambda (failure) (reply! channel (vector #f failure)))
                       (lambda ()
                         (case operation
                           ((run)
                            (when (or running (pair? closing)) (error "ASCENT actor Session is busy"))
                            (set! generation (+ generation 1))
                            (let* ((cut (snapshot)) (epoch generation)
                                   (token (vector (make-mutex) #f))
                                   (session-owner (current-thread))
                                   (worker (spawn/name 'ascent-session-evaluation
                                            (lambda ()
                                              (with-catch (lambda (failure) (vector #f failure))
                                               (lambda ()
                                                 (vector #t (gerbil-ascent-evaluate-program cut workers: workers
                                                            canceled?: (lambda ()
                                                                         (mutex-lock! (vector-ref token 0))
                                                                         (let (canceled (vector-ref token 1))
                                                                           (mutex-unlock! (vector-ref token 0)) canceled)))))))))
                                   (monitor (spawn/name 'ascent-session-monitor
                                             (lambda ()
                                               (let (outcome (with-catch (lambda (failure) (vector #f failure))
                                                              (lambda () (thread-join! worker))))
                                                 (thread-send session-owner ['terminal epoch worker outcome]))))))
                              (set! running (vector epoch token worker monitor channel))))
                           ((append) (update! (list (cons (car args) (list (cadr args)))) #t) (reply! channel (vector #t (void))))
                           ((replace) (update! (list (cons (car args) (cadr args))) #f) (reply! channel (vector #t (void))))
                           ((replace-many) (update! (car args) #f) (reply! channel (vector #t (void))))
                           ((cancel) (mark-canceled!) (reply! channel (vector #t (if running 'draining 'idle))))
                           ((result) (reply! channel (vector #t published)))
                           ((state) (reply! channel (vector #t (list generation (if running (if (= generation (vector-ref running 0)) 'running 'draining) 'idle)))))
                           ((close) (mark-canceled!) (set! closing (cons channel closing)))))))
                     (['terminal epoch worker outcome]
                      (when (and running (= epoch (vector-ref running 0)) (eq? worker (vector-ref running 2)))
                        (thread-join! (vector-ref running 3))
                        (if (and (= epoch generation) (vector-ref outcome 0))
                          (begin (set! committed pending) (set! published (vector-ref outcome 1))
                                 (reply! (vector-ref running 4) outcome))
                          (begin
                            (set! pending committed)
                            (reply! (vector-ref running 4)
                              (if (= epoch generation) outcome
                                (vector #f (session-failure "ASCENT actor Session canceled"))))))
                        (set! running #f))))
                   (if (and (pair? closing) (not running))
                     (begin
                       (mutex-lock! gate) (set! closed? #t) (mutex-unlock! gate)
                       ;; No requests accepted after closed? is set. Drain requests
                       ;; already admitted through gate before terminating owner.
                       (let drain ()
                         (match (thread-receive 0 #f)
                           (['request channel operation args]
                            (if (eq? operation 'close) (set! closing (cons channel closing))
                                (reply! channel (vector #f (session-failure "ASCENT actor Session closed"))))
                            (drain)) (else (void))))
                       (for-each (lambda (channel) (reply! channel (vector #t (void)))) closing))
                     (loop))))))))
      (def (request operation . args)
        ;; A private reply actor leaves the caller's mailbox untouched.
        (let (outcome
              (thread-join! (spawn/name 'ascent-session-request
                (lambda ()
                  (mutex-lock! gate)
                  (if closed?
                    (begin (mutex-unlock! gate) (vector #f (session-failure "ASCENT actor Session closed")))
                    (begin (thread-send owner ['request (current-thread) operation args])
                           (mutex-unlock! gate) (thread-receive)))))))
          (if (vector-ref outcome 0) (vector-ref outcome 1) (raise (vector-ref outcome 1)))))
      (validate GerbilAscentSessionContract
                (.o (:: @ Session.)
                    (.append-source! (lambda (name row) (request 'append name row)))
                    (.replace-source! (lambda (name rows) (request 'replace name rows)))
                    (.replace-sources! (lambda (replacements) (request 'replace-many replacements)))
                    (.run (lambda () (request 'run)))
                    (.cancel! (lambda () (request 'cancel)))
                    (.last-completed (lambda () (request 'result)))
                    (.state (lambda () (request 'state)))
                    (.close! (lambda () (request 'close) (thread-join! owner))))))))

(def (gerbil-ascent-session-cancel! session) ((.ref session '.cancel!)))
(def (gerbil-ascent-session-last-completed session) ((.ref session '.last-completed)))
(def (gerbil-ascent-session-state session) ((.ref session '.state)))
(def (gerbil-ascent-session-close! session) ((.ref session '.close!)))
