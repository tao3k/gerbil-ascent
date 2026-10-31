(import :gerbil-ascent/program/interface)
(displayln "ENGINE-PATH " (gx#module-context-path (gx#import-module ':gerbil-ascent/program/evaluate)))
(load "t/scenarios/performance/ascent-nonpositive-session-update/scenario.ss")
