(import (only-in :std/make make))
(make '("core/positive-plan" "program/index" "program/actor-round" "program/evaluate"
        "t/qualification/ascent-positive-plan-reference-analysis"
        "t/qualification/ascent-positive-plan-reference-evaluate")
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_POSITIVE_PLAN_LIB")
      build-deps: ".gerbil/positive-plan/build-deps")
(exit 0)
