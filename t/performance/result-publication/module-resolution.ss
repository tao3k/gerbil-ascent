(import :gerbil-ascent/program/evaluate
        :gerbil-ascent/program/result
        :gerbil-ascent/t/qualification/ascent-result-reference-evaluate)
(for-each (lambda (name) (displayln (gx#module-context-path (gx#import-module name))))
          '(:gerbil-ascent/program/evaluate :gerbil-ascent/program/result
            :gerbil-ascent/t/qualification/ascent-result-reference-evaluate))
(exit 0)
