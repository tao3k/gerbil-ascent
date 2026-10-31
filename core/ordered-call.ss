;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One syntax contract for admitted callback inputs. The wrapper determines
;;; whether dispatch executes now or publishes a frame reader. Small calls
;;; resolve operands once, in order, before invoking user code. Larger shapes
;;; retain the ordered map/apply protocol. No callback value is cached.
(export dispatch-ordered-call)

(defrules ordered-call-values ()
  ((_ procedure (input read) (value ...) ())
   (procedure value ...))
  ((_ procedure (input read) (value ...) (argument rest ...))
   (let* ((input argument) (next read))
     (ordered-call-values procedure (input read) (value ... next) (rest ...)))))

(defrules dispatch-ordered-call ()
  ((_ (wrap ...) procedure inputs (input read))
   (match inputs
     ([] (wrap ... (ordered-call-values procedure (input read) () ())))
     ([one] (wrap ... (ordered-call-values procedure (input read) () (one))))
     ([one two] (wrap ... (ordered-call-values procedure (input read) () (one two))))
     ([one two three] (wrap ... (ordered-call-values procedure (input read) () (one two three))))
     ([one two three four] (wrap ... (ordered-call-values procedure (input read) () (one two three four))))
     (else (wrap ... (apply procedure (map (lambda (input) read) inputs)))))))
