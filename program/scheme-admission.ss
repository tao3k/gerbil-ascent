;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Public checked-runtime facade. Each lifecycle phase owns its state and checks.
(import "scheme-admit.ss" "scheme-query.ss" "scheme-session.ss")

(export relational-export relational-compose relational-admit
        relational-admit/report
        relational-admission-report? relational-admission-report-admission
        relational-admission-report-diagnostic
        relational-diagnostic? relational-diagnostic-code
        relational-diagnostic-path relational-diagnostic-detail
        relational-solve relational-query relational-query-name
        relational-open-session relational-session-append-source!
        relational-session-replace-source!
        relational-session-replace-sources!
        relational-session-transaction!
        relational-session-run relational-open-program-session
        relational-program-append-source!
        relational-program-replace-source!
        relational-program-transaction!
        relational-program-session-run relational-program-query)
