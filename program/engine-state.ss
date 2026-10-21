;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Evaluator-owned state and the complete public Session projection.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss" GerbilAscentSessionContract))
(export make-engine-state engine-state-public
        engine-state-append-source! engine-state-replace-source! engine-state-run
        engine-state-run-timeout engine-state-analysis engine-state-schema
        engine-state-publication engine-state-recomputed?
        engine-state-source-additions engine-state-source-overrides)

;; This record never accepts caller-supplied methods. The evaluator below owns
;; every closure and buffer. Public Engine and Session publication still uses
;; the original full Contract; private recovery does not publish another facade.
(defstruct engine-state
  (append-source! replace-source! run run-timeout analysis schema publication
   recomputed? source-additions source-overrides) final: #t)

(def (engine-state-public state)
  (validate GerbilAscentSessionContract
    (.o (:: @ (.ref GerbilAscentSessionContract 'proto))
      (.append-source! (engine-state-append-source! state))
      (.replace-source! (engine-state-replace-source! state))
      (.run (engine-state-run state))
      (.run-timeout (engine-state-run-timeout state))
      (.analysis (engine-state-analysis state))
      (.schema (engine-state-schema state))
      (.native-publication (engine-state-publication state))
      (.recomputed? (engine-state-recomputed? state))
      (.source-additions (engine-state-source-additions state))
      (.source-overrides (engine-state-source-overrides state)))))
