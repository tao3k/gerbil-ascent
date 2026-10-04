(import (only-in :std/make make))
(make '("table/funs" "table/access" "program/evaluate"
        "t/qualification/ascent-index-reference-funs"
        "t/qualification/ascent-index-reference-provider"
        "t/qualification/ascent-index-reference-evaluate")
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_INDEX_LIFECYCLE_LIB")
      build-deps: ".gerbil/index-lifecycle/build-deps")
(exit 0)
