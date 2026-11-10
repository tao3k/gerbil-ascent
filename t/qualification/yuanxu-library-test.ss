;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "../../build.ss" gerbil-ascent-library-modules)
        :std/test
        (only-in :clan/poo/object .get .ref .all-slots object?)
        (only-in :clan/poo/mop validate)
        "../../init.ss")
(export yuanxu-library-test)

(def owners '(core table program rules candidate temporal interface applications))
(def yuanxu-library-test
  (test-suite "Actual Library directories own Yuanxu publication and execution"
    (test-case "init publishes the actual owners without aggregate shell modules"
      (let* ((library (.get gerbil-ascent.init.exports Library))
             (names (.all-slots library)))
        (check-equal? (length names) (length owners))
        (for-each (lambda (owner)
                    (check-equal? (and (memq owner names) #t) #t)
                    ;; Demand actual source-bound scope admission for EVERY owner.
                    (check-equal? (object? (.ref (.ref library owner) 'scope)) #t)) owners)
        (check-equal? (and (memq 'relations names) #t) #f)
        (check-equal? (and (memq 'inference names) #t) #f)
        (check-equal? (and (memq 'evidence names) #t) #f)
        ;; Source epochs own nominal prototypes. Use the actual published
        ;; Types, never a different native import's lookalike prototype.
        (let ((table (.get library table scope)) (program (.get library program scope)))
          (validate (.get table types scope) table)
          (validate (.get program types scope) program))
        (let* ((rules (.get library rules scope))
               (capacity ((.ref rules 'capacity)
                          (list (hash ("relation" "seed") ("rows" '((7))))) 1)))
          (check-equal? (procedure? (.ref rules 'recorded-module)) #t)
          (check-equal? (hash-ref capacity "status") "WITHIN_CAPACITY"))))
    (test-case "published native Program scope preserves sibling and revision isolation"
      (let* ((scope (.get gerbil-ascent.init.exports Library program scope))
             (table (.get gerbil-ascent.init.exports Library table scope))
             (provider (.ref table 'hash-index-provider))
             (storage (.ref table 'set-storage-provider))
             (_provider (validate (.get table types index-provider) provider))
             (_storage (validate (.get table types storage-provider) storage))
             (relation ((.ref scope 'relation) 'seed 1 '((7)) provider storage))
             (program ((.ref scope 'program) (list relation) [] 8 8 8))
             (left ((.ref scope 'open-session) program))
             (right ((.ref scope 'open-session) program))
             (first ((.ref left '.run))))
        (check-equal? ((.ref first 'rows-of) 'seed) '((7)))
        ((.ref left '.source-replacement) 'seed '((8)))
        (check-equal? ((.ref ((.ref left '.run)) 'rows-of) 'seed) '((8)))
        (check-equal? ((.ref ((.ref right '.run)) 'rows-of) 'seed) '((7)))
        (check-equal? ((.ref first 'rows-of) 'seed) '((7)))
        ((.ref left '.source-replacement) 'seed [])
        (check-equal? ((.ref ((.ref left '.run)) 'rows-of) 'seed) [])
        ((.ref left '.source-replacement) 'seed '((7)))
        (check-equal? ((.ref ((.ref left '.run)) 'rows-of) 'seed) '((7)))))
    (test-case "native compiler projection derives every owner from the same init"
      (let (modules (gerbil-ascent-library-modules))
        ;; The published Rules operations must own their native implementation;
        ;; a linked ABI import must not rely on a previous package installation.
        (check-equal? (and (member "init" modules) #t) #t)
        (check-equal? (and (member "rules/module" modules) #t) #t)
        (for-each (lambda (owner)
          (let (entry (string-append (symbol->string owner) "/interface"))
            (check-equal? (and (member entry modules) #t) #t))) owners)
        (check-equal? (ormap (lambda (entry)
          (or (string-prefix? "modules/" entry)
              (string-prefix? "relations/" entry)
              (string-prefix? "inference/" entry)
              (string-prefix? "evidence/" entry))) modules) #f)))))
