(import :gerbil-ascent/program/evaluate
        :gerbil-ascent/table/funs
        :gerbil-ascent/t/qualification/ascent-index-reference-evaluate
        :gerbil-ascent/t/qualification/ascent-index-reference-funs
        :gerbil-ascent/t/qualification/ascent-index-reference-provider)
(for-each (lambda (name) (displayln (gx#module-context-path (gx#import-module name))))
          '(:gerbil-ascent/program/evaluate :gerbil-ascent/table/funs
            :gerbil-ascent/t/qualification/ascent-index-reference-evaluate
            :gerbil-ascent/t/qualification/ascent-index-reference-funs
            :gerbil-ascent/t/qualification/ascent-index-reference-provider))
(exit 0)
