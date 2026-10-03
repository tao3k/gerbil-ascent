;;; Build the complete production module list into a private qualification library.
(import (only-in :std/make make))
(make (call-with-input-file (getenv "ASCENT_PERFORMANCE_MODULES") read)
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_TEST_LIBRARY")
      build-deps: (getenv "ASCENT_PERFORMANCE_BUILD_DEPS"))
(exit 0)
