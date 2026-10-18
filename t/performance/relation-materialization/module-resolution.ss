(import :gerbil-ascent/table/expression
        :gerbil-ascent/t/qualification/ascent-materialization-reference)
(for-each (lambda (name) (displayln (gx#module-context-path (gx#import-module name))))
          '(:gerbil-ascent/table/expression :gerbil-ascent/t/qualification/ascent-materialization-reference))
(exit 0)
