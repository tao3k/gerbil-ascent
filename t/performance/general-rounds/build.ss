(import (only-in :std/make make))
(make '("core/binary-relation" "table/expression" "core/binary-program"
        "t/performance/general-rounds/reference-expression"
        "t/performance/general-rounds/reference-program")
      srcdir: (current-directory) libdir: (getenv "ASCENT_GENERAL_ROUNDS_LIB")
      build-deps: (getenv "ASCENT_GENERAL_ROUNDS_BUILD_DEPS"))
(exit 0)
