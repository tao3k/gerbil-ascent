(import (only-in :std/make make))
(make '("program/result" "program/evaluate"
        "t/qualification/ascent-result-reference-evaluate")
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_RESULT_LIB")
      build-deps: ".gerbil/result-publication/build-deps")
(exit 0)
