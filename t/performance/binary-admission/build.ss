(import (only-in :std/make make))
(make '("table/expression" "core/binary-program"
        "t/performance/binary-admission/reference-expression"
        "t/performance/binary-admission/reference-program")
      srcdir: (current-directory) libdir: (getenv "ASCENT_BINARY_ADMISSION_LIB")
      build-deps: (getenv "ASCENT_BINARY_ADMISSION_BUILD_DEPS"))
(exit 0)
