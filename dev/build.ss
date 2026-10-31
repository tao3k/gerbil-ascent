#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit policy qualification over the production build's source inputs.
(import (only-in "../build-modules.ss" gerbil-ascent-build-input-modules)
        (only-in :std/source this-source-file)
        (only-in :std/string/path path-default-extension)
        (only-in :asp-gerbil-scheme/src/build-api/policy-runner
                 asp-gerbil-scheme-run-selected-policy))
(export main)
(def (main . _)
  (current-directory (path-expand ".." (path-directory (this-source-file))))
  (asp-gerbil-scheme-run-selected-policy
    (map (cut path-default-extension <> ".ss") (gerbil-ascent-build-input-modules))))
