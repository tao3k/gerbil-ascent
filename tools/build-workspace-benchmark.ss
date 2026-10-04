(import (only-in :std/make make))
(make '("core/positive-plan" "program/evaluate"
        "t/qualification/ascent-workspace-reference-analysis"
        "t/qualification/ascent-workspace-reference-positive"
        "t/qualification/ascent-workspace-reference-evaluate")
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_WORKSPACE_LIB")
      build-deps: ".gerbil/execution-workspace/build-deps")
(exit 0)
