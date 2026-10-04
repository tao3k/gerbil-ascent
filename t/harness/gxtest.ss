;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (rename-in (only-in :gerbil/tools/gxtest main) (main run-tests))
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(assert-native-library!)
(exit (apply run-tests (cddr (command-line))))
