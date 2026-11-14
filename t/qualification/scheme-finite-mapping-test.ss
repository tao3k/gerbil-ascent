;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .ref .o)
        (only-in :clan/poo/mop element?)
        (only-in :gerbil-ascent/program/types GerbilAscentRelationContract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract gerbil-ascent-hash-index-provider
                 gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract gerbil-ascent-set-storage-provider
                 gerbil-ascent-canonical-set-storage-provider?)
        (only-in :gerbil-ascent/table/access gerbil-ascent-physical-index-build
                 gerbil-ascent-physical-index-extend! gerbil-ascent-physical-index-rows)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-finite-rows relational-finite-view relational-source)
        (rename-in :gerbil-ascent/t/performance/finite-mapping/reference
                   (relational-finite-rows old-rows)
                   (relational-finite-view old-view)
                   (relational-source old-source)))
(export scheme-finite-mapping-test)
(def (view-rows view) (.ref (car (.ref view 'relations)) 'rows))
(def (observe thunk)
  (with-catch (lambda (failure) (list 'error (error-message failure))) thunk))
(def scheme-finite-mapping-test
  (test-suite "finite mapping ownership boundaries"
    (test-case "rebinding public defaults cannot change admission or physical representation"
      (let* ((index-provider gerbil-ascent-hash-index-provider)
             (storage-provider gerbil-ascent-set-storage-provider)
             (slots (.ref GerbilAscentRelationContract 'responsibilities))
             (index (gerbil-ascent-physical-index-build index-provider '((1 a)) '(0))))
        (try
         (set! gerbil-ascent-hash-index-provider #f)
         (set! gerbil-ascent-set-storage-provider #f)
         (check-equal? (gerbil-ascent-canonical-hash-index-provider? index-provider) #t)
         (check-equal? (gerbil-ascent-canonical-set-storage-provider? storage-provider) #t)
         (check-equal? (gerbil-ascent-canonical-hash-index-provider? #f) #f)
         (check-equal? (gerbil-ascent-canonical-set-storage-provider? #f) #f)
         (check-equal? (element? (.ref slots 'index-provider) #f) #f)
         (check-equal? (element? (.ref slots 'storage-provider) #f) #f)
         (check-equal? (gerbil-ascent-physical-index-rows index-provider index '(1)) '((1 a)))
         (gerbil-ascent-physical-index-extend! index-provider index '((2 b)) '(0))
         (check-equal? (gerbil-ascent-physical-index-rows index-provider index '(2)) '((2 b)))
         (finally
          (set! gerbil-ascent-hash-index-provider index-provider)
          (set! gerbil-ascent-set-storage-provider storage-provider)))))
    (test-case "canonical, derived and malformed receivers preserve slot admission"
      (let (slots (.ref GerbilAscentRelationContract 'responsibilities))
        (for-each
         (lambda (spec)
           (let* ((contract (car spec)) (slot (cadr spec)) (canonical (caddr spec))
                  (derived (.o (:: @ canonical) test-tag: 'derived)))
             (check-equal? (eq? derived canonical) #f)
             (for-each
              (lambda (value)
                (check-equal? (element? slot value) (element? contract value)))
              (list canonical derived (.o) #f))))
         (list (list GerbilAscentIndexProviderContract (.ref slots 'index-provider)
                     gerbil-ascent-hash-index-provider)
               (list GerbilAscentStorageProviderContract (.ref slots 'storage-provider)
                     gerbil-ascent-set-storage-provider)))))
    (test-case "all small signatures preserve duplicates and exact row order"
      (for-each
       (lambda (left)
         (for-each
          (lambda (right)
            (let* ((entry (list (make-list left #f) (make-list right #\a)))
                   (entries (list entry entry)))
              (check-equal? (relational-finite-rows left right entries)
                            (old-rows left right entries))
              (check-equal? (view-rows (relational-finite-view 'mapping left right entries))
                            (view-rows (old-view 'mapping left right entries)))))
          (iota 5)))
       (iota 5)))
    (test-case "mapping and view own both halves of aliased caller rows"
      (let* ((row (list 1 2)) (entry (list row row)) (entries (list entry entry))
             (copied (relational-finite-rows 2 2 entries))
             (view (relational-finite-view 'mapping 2 2 entries)))
        (set-car! row 99) (set-cdr! row 'bad)
        (set-car! entry 'bad) (set-cdr! entries 'bad)
        (check-equal? copied '((1 2 1 2) (1 2 1 2)))
        (check-equal? (view-rows view) copied)
        (set-car! (car copied) 88)
        (check-equal? (cadr copied) '(1 2 1 2))
        (check-equal? (view-rows view) '((1 2 1 2) (1 2 1 2)))))
    (test-case "malformed signatures and entries retain diagnostic precedence"
      (for-each
       (lambda (args)
         (check-equal? (observe (lambda () (apply relational-finite-rows args)))
                       (observe (lambda () (apply old-rows args)))))
       (list (list -1 1 []) (list 1 1 'bad)
             (list 1 1 '((bad))) (list 1 1 '(((1 2) ("bad"))))
             (list 1 1 '(((1) ("bad")))) (list 0 0 '((() ()) bad))
             (list 1 1 (list (list (cons 1 'bad) '(2))))))
      (let (cycle (list 1))
        (set-cdr! cycle cycle)
        (check-equal? (observe (lambda () (relational-finite-rows 1 1 (list (list cycle '(2))))))
                      (observe (lambda () (old-rows 1 1 (list (list cycle '(2)))))))))
    (test-case "ordinary sources still copy every caller spine"
      (let* ((row (list #f 'tag #\a 7)) (rows (list row row))
             (source (relational-source 'source 4 rows)))
        (check-equal? (.ref source 'rows) (.ref (old-source 'source 4 rows) 'rows))
        (set-car! row 99) (set-cdr! rows 'bad)
        (check-equal? (.ref source 'rows) '((#f tag #\a 7) (#f tag #\a 7)))))
    (test-case "failed scalar copies leave caller rows untouched"
      (for-each
       (lambda (row)
         (let (before (map values row))
           (check-equal? (observe (lambda () (relational-source 'bad 3 (list row))))
                         (observe (lambda () (old-source 'bad 3 (list row)))))
           (check-equal? row before)))
       (list (list "bad" 1 2) (list 1 (vector 'bad) 2) (list 1 2 0.5))))))
