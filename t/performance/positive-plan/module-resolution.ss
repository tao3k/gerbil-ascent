(import :gerbil-ascent/program/interface
        :gerbil-ascent/t/qualification/ascent-positive-plan-reference-evaluate)
(for-each
 (lambda (name) (displayln (gx#module-context-path (gx#import-module name))))
 '(:gerbil-ascent/core/positive-plan
   :gerbil-ascent/program/evaluate
   :gerbil-ascent/t/qualification/ascent-positive-plan-reference-analysis
   :gerbil-ascent/t/qualification/ascent-positive-plan-reference-evaluate))
(exit 0)
