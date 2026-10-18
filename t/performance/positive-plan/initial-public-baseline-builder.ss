(import (only-in :std/make make))
(make '("program/evaluate")
      srcdir: "/private/tmp/ascent-positive-plan-baseline"
      libdir: ".gerbil/positive-plan-baseline/lib"
      build-deps: ".gerbil/positive-plan-baseline/build-deps")
(exit 0)
