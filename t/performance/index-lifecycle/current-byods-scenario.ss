(import :gerbil-ascent/program/evaluate)
(displayln "ENGINE-PATH " (gx#module-context-path (gx#import-module ':gerbil-ascent/program/evaluate)))
(load "t/scenarios/performance/ascent-byods-trrel/scenario.ss")
