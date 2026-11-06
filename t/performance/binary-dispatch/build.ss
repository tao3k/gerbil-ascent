(import (only-in :std/make make))
(make '("core/binary-relation" "table/expression" "core/binary-program"
        "t/performance/binary-dispatch/reference-expression"
        "t/performance/binary-dispatch/reference-program")
      srcdir: (current-directory) libdir: (getenv "ASCENT_BINARY_DISPATCH_LIB")
      build-deps: (getenv "ASCENT_BINARY_DISPATCH_BUILD_DEPS"))
(exit 0)
