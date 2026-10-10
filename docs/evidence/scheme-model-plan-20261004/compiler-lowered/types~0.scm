(declare (block) (standard-bindings) (extended-bindings))
(begin
  (define core/types::timestamp 1791072357)
  (begin
    (define core/types#poo-flow-type-classify
      (lambda (_%type2396%_ _%candidate2397%_ _%context2398%_)
        ((let ()
           (declare (not safe))
           (clan/poo/object#.ref _%type2396%_ '.classify))
         _%candidate2397%_
         _%context2398%_)))
    (define core/types#poo-flow-contract-obligations
      (lambda (_%contract2392%_ _%candidate2393%_ _%context2394%_)
        ((let ()
           (declare (not safe))
           (clan/poo/object#.ref _%contract2392%_ '.obligations))
         _%candidate2393%_
         _%context2394%_)))
    (define core/types#poo-flow-contract-admit
      (lambda (_%contract2388%_ _%candidate2389%_ _%context2390%_)
        ((let ()
           (declare (not safe))
           (clan/poo/object#.ref _%contract2388%_ '.admit))
         _%candidate2389%_
         _%context2390%_)))
    (define core/types#poo-flow-evidence-object?
      (lambda (_%value2380%_ _%expected-kind2381%_ _%required-slots2382%_)
        (if (let ()
              (declare (not safe))
              (##structure-instance-of?
               _%value2380%_
               'clan/poo/object#object::t))
            (if (every (lambda (_%$%g23832385%_)
                         (let ()
                           (declare (not safe))
                           (clan/poo/object#.slot?
                            _%value2380%_
                            _%$%g23832385%_)))
                       _%required-slots2382%_)
                (if (eq? (let ()
                           (declare (not safe))
                           (clan/poo/object#.ref _%value2380%_ 'kind))
                         _%expected-kind2381%_)
                    (if (boolean?
                         (let ()
                           (declare (not safe))
                           (clan/poo/object#.ref _%value2380%_ 'accepted?)))
                        (list? (let ()
                                 (declare (not safe))
                                 (clan/poo/object#.ref
                                  _%value2380%_
                                  'diagnostics)))
                        '#f)
                    '#f)
                '#f)
            '#f)))
    (define core/types#poo-flow-type-identity?
      (lambda (_%value2375%_)
        (let ((_%$e2377%_ (symbol? _%value2375%_)))
          (if _%$e2377%_
              _%$e2377%_
              (if (pair? _%value2375%_)
                  (let ()
                    (declare (not safe))
                    (##every core/types#poo-flow-type-identity? _%value2375%_))
                  '#f)))))
    (define core/types#poo-flow-classification-evidence-element?
      (lambda (_%value2373%_)
        (if (core/types#poo-flow-evidence-object?
             _%value2373%_
             'poo-flow.type.classification-evidence
             '(kind type-identity candidate accepted? diagnostics context))
            (core/types#poo-flow-type-identity?
             (let ()
               (declare (not safe))
               (clan/poo/object#.ref _%value2373%_ 'type-identity)))
            '#f)))
    (define core/types#PooFlowClassificationEvidence
      (let ((__obj5221
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5240
               (list (cons 'sexp
                           (let ((__tmp5241
                                  (lambda (_%@2362%_)
                                    'PooFlowClassificationEvidence)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5241)))
                     (cons '.element?
                           (let ((__tmp5242
                                  (lambda (_%@2368%_)
                                    core/types#poo-flow-classification-evidence-element?)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5242)))))
              (__tmp5239 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           clan/poo/mop#Type.
           __tmp5240
           __tmp5239
           __obj5221))
        __obj5221))
    (define core/types#poo-flow-validation-evidence-element?
      (lambda (_%value2349%_)
        (if (core/types#poo-flow-evidence-object?
             _%value2349%_
             'poo-flow.contract.validation-evidence
             '(kind contract-identity
                    candidate
                    classification
                    obligation-evidence
                    accepted?
                    diagnostics
                    context))
            (if (symbol? (let ()
                           (declare (not safe))
                           (clan/poo/object#.ref
                            _%value2349%_
                            'contract-identity)))
                (if (let ((__tmp5243
                           (let ()
                             (declare (not safe))
                             (clan/poo/object#.ref
                              _%value2349%_
                              'classification))))
                      (declare (not safe))
                      (clan/poo/mop#element?
                       core/types#PooFlowClassificationEvidence
                       __tmp5243))
                    (if (list? (let ()
                                 (declare (not safe))
                                 (clan/poo/object#.ref
                                  _%value2349%_
                                  'obligation-evidence)))
                        (if (equal? (let ()
                                      (declare (not safe))
                                      (clan/poo/object#.ref
                                       _%value2349%_
                                       'candidate))
                                    (let ((__tmp5244
                                           (let ()
                                             (declare (not safe))
                                             (clan/poo/object#.ref
                                              _%value2349%_
                                              'classification))))
                                      (declare (not safe))
                                      (clan/poo/object#.ref
                                       __tmp5244
                                       'candidate)))
                            (if (equal? (let ()
                                          (declare (not safe))
                                          (clan/poo/object#.ref
                                           _%value2349%_
                                           'context))
                                        (let ((__tmp5245
                                               (let ()
                                                 (declare (not safe))
                                                 (clan/poo/object#.ref
                                                  _%value2349%_
                                                  'classification))))
                                          (declare (not safe))
                                          (clan/poo/object#.ref
                                           __tmp5245
                                           'context)))
                                (eq? (let ()
                                       (declare (not safe))
                                       (clan/poo/object#.ref
                                        _%value2349%_
                                        'accepted?))
                                     (if (let ((__tmp5246
                                                (let ()
                                                  (declare (not safe))
                                                  (clan/poo/object#.ref
                                                   _%value2349%_
                                                   'classification))))
                                           (declare (not safe))
                                           (clan/poo/object#.ref
                                            __tmp5246
                                            'accepted?))
                                         (null? (let ()
                                                  (declare (not safe))
                                                  (clan/poo/object#.ref
                                                   _%value2349%_
                                                   'obligation-evidence)))
                                         '#f))
                                '#f)
                            '#f)
                        '#f)
                    '#f)
                '#f)
            '#f)))
    (define core/types#PooFlowValidationEvidence
      (let ((__obj5222
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5248
               (list (cons 'sexp
                           (let ((__tmp5249
                                  (lambda (_%@2338%_)
                                    'PooFlowValidationEvidence)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5249)))
                     (cons '.element?
                           (let ((__tmp5250
                                  (lambda (_%@2344%_)
                                    core/types#poo-flow-validation-evidence-element?)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5250)))))
              (__tmp5247 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           clan/poo/mop#Type.
           __tmp5248
           __tmp5247
           __obj5222))
        __obj5222))
    (define core/types#poo-flow-classification-evidence
      (lambda (_%type-identity-value2273%_
               _%candidate-value2274%_
               _%accepted-value2275%_
               _%diagnostics-value2276%_
               _%context-value2277%_)
        (let ((__obj5223
               (let ()
                 (declare (not safe))
                 (##structure
                  clan/poo/object#object::t
                  '#f
                  '#f
                  '#f
                  '#f
                  '#f
                  '#f
                  '#f))))
          (let ((__tmp5252
                 (list (cons 'kind
                             (let ((__tmp5253
                                    (lambda (_%self2295%_)
                                      'poo-flow.type.classification-evidence)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5253)))
                       (cons 'type-identity
                             (let ((__tmp5254
                                    (lambda (_%self2302%_)
                                      _%type-identity-value2273%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5254)))
                       (cons 'candidate
                             (let ((__tmp5255
                                    (lambda (_%self2307%_)
                                      _%candidate-value2274%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5255)))
                       (cons 'accepted?
                             (let ((__tmp5256
                                    (lambda (_%self2312%_)
                                      (if _%accepted-value2275%_ '#t '#f))))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5256)))
                       (cons 'diagnostics
                             (let ((__tmp5257
                                    (lambda (_%self2317%_)
                                      _%diagnostics-value2276%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5257)))
                       (cons 'context
                             (let ((__tmp5258
                                    (lambda (_%self2322%_)
                                      _%context-value2277%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5258)))))
                (__tmp5251 (list)))
            (declare (not safe))
            (clan/poo/object#object:::init!__%
             '#f
             '()
             __tmp5252
             __tmp5251
             __obj5223))
          __obj5223)))
    (define core/types#poo-flow-classification-evidence?
      (lambda (_%value2271%_)
        (let ()
          (declare (not safe))
          (clan/poo/mop#element?
           core/types#PooFlowClassificationEvidence
           _%value2271%_))))
    (define core/types#poo-flow-classification-evidence-accepted?
      (lambda (_%evidence2269%_)
        (if (core/types#poo-flow-classification-evidence? _%evidence2269%_)
            (let ()
              (declare (not safe))
              (clan/poo/object#.ref _%evidence2269%_ 'accepted?))
            '#f)))
    (define core/types#poo-flow-classification-evidence->alist
      (lambda (_%evidence2267%_)
        (if (core/types#poo-flow-classification-evidence? _%evidence2267%_)
            '#!void
            (begin
              (let ((__tmp5259
                     (let ((__obj5224
                            (let ()
                              (declare (not safe))
                              (##structure
                               clan/poo/mop#TypeError::t
                               '#f
                               '#f
                               '#f
                               '#f))))
                       (let ((__tmp5260
                              (cons 'PooFlowClassificationEvidence
                                    (cons _%evidence2267%_ '()))))
                         (declare (not safe))
                         (clan/poo/mop#TypeError:::init!
                          __obj5224
                          '"type error"
                          'where:
                          '"\"core/types.ss\"@130.23-130.52"
                          'irritants:
                          __tmp5260))
                       __obj5224)))
                (declare (not safe))
                (raise __tmp5259))
              '#!void))
        (list (cons 'kind
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2267%_ 'kind)))
              (cons 'type-identity
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2267%_ 'type-identity)))
              (cons 'accepted?
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2267%_ 'accepted?)))
              (cons 'diagnostics
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2267%_ 'diagnostics)))
              (cons 'context
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2267%_ 'context))))))
    (define core/types#poo-flow-validation-evidence
      (lambda (_%contract-identity-value2199%_
               _%candidate-value2200%_
               _%classification-value2201%_
               _%obligation-evidence-value2202%_
               _%accepted-value2203%_
               _%diagnostics-value2204%_
               _%context-value2205%_)
        (let ((__obj5225
               (let ()
                 (declare (not safe))
                 (##structure
                  clan/poo/object#object::t
                  '#f
                  '#f
                  '#f
                  '#f
                  '#f
                  '#f
                  '#f))))
          (let ((__tmp5262
                 (list (cons 'kind
                             (let ((__tmp5263
                                    (lambda (_%self2225%_)
                                      'poo-flow.contract.validation-evidence)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5263)))
                       (cons 'contract-identity
                             (let ((__tmp5264
                                    (lambda (_%self2232%_)
                                      _%contract-identity-value2199%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5264)))
                       (cons 'candidate
                             (let ((__tmp5265
                                    (lambda (_%self2237%_)
                                      _%candidate-value2200%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5265)))
                       (cons 'classification
                             (let ((__tmp5266
                                    (lambda (_%self2242%_)
                                      _%classification-value2201%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5266)))
                       (cons 'obligation-evidence
                             (let ((__tmp5267
                                    (lambda (_%self2247%_)
                                      _%obligation-evidence-value2202%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5267)))
                       (cons 'accepted?
                             (let ((__tmp5268
                                    (lambda (_%self2252%_)
                                      (if _%accepted-value2203%_ '#t '#f))))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5268)))
                       (cons 'diagnostics
                             (let ((__tmp5269
                                    (lambda (_%self2257%_)
                                      _%diagnostics-value2204%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5269)))
                       (cons 'context
                             (let ((__tmp5270
                                    (lambda (_%self2262%_)
                                      _%context-value2205%_)))
                               (declare (not safe))
                               (##structure
                                clan/poo/object#$self-slot-spec::t
                                __tmp5270)))))
                (__tmp5261 (list)))
            (declare (not safe))
            (clan/poo/object#object:::init!__%
             '#f
             '()
             __tmp5262
             __tmp5261
             __obj5225))
          __obj5225)))
    (define core/types#poo-flow-validation-evidence?
      (lambda (_%value2197%_)
        (let ()
          (declare (not safe))
          (clan/poo/mop#element?
           core/types#PooFlowValidationEvidence
           _%value2197%_))))
    (define core/types#poo-flow-validation-evidence-accepted?
      (lambda (_%evidence2195%_)
        (if (core/types#poo-flow-validation-evidence? _%evidence2195%_)
            (let ()
              (declare (not safe))
              (clan/poo/object#.ref _%evidence2195%_ 'accepted?))
            '#f)))
    (define core/types#poo-flow-validation-evidence->alist
      (lambda (_%evidence2193%_)
        (if (core/types#poo-flow-validation-evidence? _%evidence2193%_)
            '#!void
            (begin
              (let ((__tmp5271
                     (let ((__obj5226
                            (let ()
                              (declare (not safe))
                              (##structure
                               clan/poo/mop#TypeError::t
                               '#f
                               '#f
                               '#f
                               '#f))))
                       (let ((__tmp5272
                              (cons 'PooFlowValidationEvidence
                                    (cons _%evidence2193%_ '()))))
                         (declare (not safe))
                         (clan/poo/mop#TypeError:::init!
                          __obj5226
                          '"type error"
                          'where:
                          '"\"core/types.ss\"@162.23-162.48"
                          'irritants:
                          __tmp5272))
                       __obj5226)))
                (declare (not safe))
                (raise __tmp5271))
              '#!void))
        (list (cons 'kind
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2193%_ 'kind)))
              (cons 'contract-identity
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref
                       _%evidence2193%_
                       'contract-identity)))
              (cons 'accepted?
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2193%_ 'accepted?)))
              (cons 'classification
                    (core/types#poo-flow-classification-evidence->alist
                     (let ()
                       (declare (not safe))
                       (clan/poo/object#.ref
                        _%evidence2193%_
                        'classification))))
              (cons 'obligation-evidence
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref
                       _%evidence2193%_
                       'obligation-evidence)))
              (cons 'diagnostics
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2193%_ 'diagnostics)))
              (cons 'context
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%evidence2193%_ 'context))))))
    (define core/types#poo-flow-type-element?
      (lambda (_%type2190%_ _%candidate2191%_)
        (core/types#poo-flow-classification-evidence-accepted?
         (core/types#poo-flow-type-classify
          _%type2190%_
          _%candidate2191%_
          '#f))))
    (define core/types#poo-flow-type-validate
      (lambda (_%type2185%_ _%candidate2186%_)
        (let ((_%evidence2188%_
               (core/types#poo-flow-type-classify
                _%type2185%_
                _%candidate2186%_
                '#f)))
          (if (core/types#poo-flow-classification-evidence-accepted?
               _%evidence2188%_)
              _%candidate2186%_
              (begin
                (let ((__tmp5273
                       (let ((__obj5227
                              (let ()
                                (declare (not safe))
                                (##structure
                                 clan/poo/mop#TypeError::t
                                 '#f
                                 '#f
                                 '#f
                                 '#f))))
                         (let ((__tmp5274
                                (cons 'type
                                      (cons _%candidate2186%_
                                            (cons (let ()
                                                    (declare (not safe))
                                                    (clan/poo/object#.ref
                                                     _%evidence2188%_
                                                     'diagnostics))
                                                  '())))))
                           (declare (not safe))
                           (clan/poo/mop#TypeError:::init!
                            __obj5227
                            '"type error"
                            'where:
                            '"\"core/types.ss\"@186.25-186.29"
                            'irritants:
                            __tmp5274))
                         __obj5227)))
                  (declare (not safe))
                  (raise __tmp5273))
                '#!void)))))
    (define core/types#PooFlowType.
      (let ((__obj5228
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5276
               (list (cons 'sexp
                           (let ((__tmp5277
                                  (lambda (_%@2161%_) 'PooFlowType.)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5277)))
                     (cons '.element?
                           (let ((__tmp5278
                                  (lambda (_%@2167%_)
                                    (lambda (_%$%g21712173%_)
                                      (core/types#poo-flow-type-element?
                                       _%@2167%_
                                       _%$%g21712173%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5278)))
                     (cons '.validate
                           (let ((__tmp5279
                                  (lambda (_%@2176%_)
                                    (lambda (_%$%g21802182%_)
                                      (core/types#poo-flow-type-validate
                                       _%@2176%_
                                       _%$%g21802182%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5279)))))
              (__tmp5275 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           clan/poo/mop#Type.
           __tmp5276
           __tmp5275
           __obj5228))
        __obj5228))
    (define core/types#poo-flow-contract-empty-obligations
      (lambda (_%_candidate2144%_ _%_context2145%_) '()))
    (define core/types#poo-flow-contract-admit-evidence
      (lambda (_%contract2126%_
               _%identity2127%_
               _%candidate2128%_
               _%context2129%_)
        (let* ((_%classification2131%_
                (core/types#poo-flow-type-classify
                 _%contract2126%_
                 _%candidate2128%_
                 _%context2129%_))
               (_%_checked2133%_
                (if (and (core/types#poo-flow-classification-evidence?
                          _%classification2131%_)
                         (equal? _%candidate2128%_
                                 (let ()
                                   (declare (not safe))
                                   (clan/poo/object#.ref
                                    _%classification2131%_
                                    'candidate)))
                         (equal? _%context2129%_
                                 (let ()
                                   (declare (not safe))
                                   (clan/poo/object#.ref
                                    _%classification2131%_
                                    'context))))
                    '#!void
                    (begin
                      (let ((__tmp5280
                             (let ((__obj5229
                                    (let ()
                                      (declare (not safe))
                                      (##structure
                                       clan/poo/mop#TypeError::t
                                       '#f
                                       '#f
                                       '#f
                                       '#f))))
                               (let ((__tmp5281
                                      (cons 'PooFlowClassificationEvidence
                                            (cons _%classification2131%_
                                                  '()))))
                                 (declare (not safe))
                                 (clan/poo/mop#TypeError:::init!
                                  __obj5229
                                  '"type error"
                                  'where:
                                  '"\"core/types.ss\"@208.31-208.60"
                                  'irritants:
                                  __tmp5281))
                               __obj5229)))
                        (declare (not safe))
                        (raise __tmp5280))
                      '#!void)))
               (_%classification-ok?2135%_
                (core/types#poo-flow-classification-evidence-accepted?
                 _%classification2131%_))
               (_%obligation-evidence2137%_
                (if _%classification-ok?2135%_
                    (core/types#poo-flow-contract-obligations
                     _%contract2126%_
                     _%candidate2128%_
                     _%context2129%_)
                    '()))
               (_%obligations-ok?2139%_ (null? _%obligation-evidence2137%_))
               (_%diagnostics2141%_
                (append (let ()
                          (declare (not safe))
                          (clan/poo/object#.ref
                           _%classification2131%_
                           'diagnostics))
                        _%obligation-evidence2137%_)))
          (core/types#poo-flow-validation-evidence
           _%identity2127%_
           _%candidate2128%_
           _%classification2131%_
           _%obligation-evidence2137%_
           (if _%classification-ok?2135%_ _%obligations-ok?2139%_ '#f)
           _%diagnostics2141%_
           _%context2129%_))))
    (define core/types#poo-flow-contract-element?
      (lambda (_%contract2123%_ _%candidate2124%_)
        (core/types#poo-flow-validation-evidence-accepted?
         (core/types#poo-flow-contract-admit
          _%contract2123%_
          _%candidate2124%_
          '#f))))
    (define core/types#poo-flow-contract-validate
      (lambda (_%contract2118%_ _%candidate2119%_)
        (let ((_%evidence2121%_
               (core/types#poo-flow-contract-admit
                _%contract2118%_
                _%candidate2119%_
                '#f)))
          (if (core/types#poo-flow-validation-evidence-accepted?
               _%evidence2121%_)
              _%candidate2119%_
              (begin
                (let ((__tmp5282
                       (let ((__obj5230
                              (let ()
                                (declare (not safe))
                                (##structure
                                 clan/poo/mop#TypeError::t
                                 '#f
                                 '#f
                                 '#f
                                 '#f))))
                         (let ((__tmp5283
                                (cons 'contract
                                      (cons _%candidate2119%_
                                            (cons (let ()
                                                    (declare (not safe))
                                                    (clan/poo/object#.ref
                                                     _%evidence2121%_
                                                     'diagnostics))
                                                  '())))))
                           (declare (not safe))
                           (clan/poo/mop#TypeError:::init!
                            __obj5230
                            '"type error"
                            'where:
                            '"\"core/types.ss\"@238.25-238.33"
                            'irritants:
                            __tmp5283))
                         __obj5230)))
                  (declare (not safe))
                  (raise __tmp5282))
                '#!void)))))
    (define core/types#PooFlowContract.
      (let ((__obj5231
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5285
               (list (cons 'sexp
                           (let ((__tmp5286
                                  (lambda (_%@2077%_) 'PooFlowContract.)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5286)))
                     (cons '.obligations
                           (let ((__tmp5287
                                  (lambda (_%@2083%_)
                                    core/types#poo-flow-contract-empty-obligations)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5287)))
                     (cons '.admit
                           (let ((__tmp5288
                                  (lambda (_%@2088%_)
                                    (lambda (_%$%g20922095%_ _%$%g20932097%_)
                                      (core/types#poo-flow-contract-admit-evidence
                                       _%@2088%_
                                       (let ()
                                         (declare (not safe))
                                         (clan/poo/object#.ref
                                          _%@2088%_
                                          'identity))
                                       _%$%g20922095%_
                                       _%$%g20932097%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5288)))
                     (cons '.element?
                           (let ((__tmp5289
                                  (lambda (_%@2100%_)
                                    (lambda (_%$%g21042106%_)
                                      (core/types#poo-flow-contract-element?
                                       _%@2100%_
                                       _%$%g21042106%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5289)))
                     (cons '.validate
                           (let ((__tmp5290
                                  (lambda (_%@2109%_)
                                    (lambda (_%$%g21132115%_)
                                      (core/types#poo-flow-contract-validate
                                       _%@2109%_
                                       _%$%g21132115%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5290)))))
              (__tmp5284 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           core/types#PooFlowType.
           __tmp5285
           __tmp5284
           __obj5231))
        __obj5231))
    (define core/types#poo-flow-predicate-classifier
      (lambda (_%identity2021%_ _%predicate2022%_)
        (lambda (_%candidate2024%_ _%context2025%_)
          (let ((_%accepted?2027%_ (_%predicate2022%_ _%candidate2024%_)))
            (core/types#poo-flow-classification-evidence
             _%identity2021%_
             _%candidate2024%_
             _%accepted?2027%_
             (if _%accepted?2027%_
                 '()
                 (list (let ((__obj5232
                              (let ()
                                (declare (not safe))
                                (##structure
                                 clan/poo/object#object::t
                                 '#f
                                 '#f
                                 '#f
                                 '#f
                                 '#f
                                 '#f
                                 '#f))))
                         (let ((__tmp5292
                                (list (cons 'kind
                                            (let ((__tmp5293
                                                   (lambda (_%self2044%_)
                                                     'poo-flow.type.classification-failure)))
                                              (declare (not safe))
                                              (##structure
                                               clan/poo/object#$self-slot-spec::t
                                               __tmp5293)))
                                      (cons 'type-identity
                                            (let ((__tmp5294
                                                   (lambda (_%self2051%_)
                                                     _%identity2021%_)))
                                              (declare (not safe))
                                              (##structure
                                               clan/poo/object#$self-slot-spec::t
                                               __tmp5294)))
                                      (cons 'reason
                                            (let ((__tmp5295
                                                   (lambda (_%self2056%_)
                                                     'predicate-rejected)))
                                              (declare (not safe))
                                              (##structure
                                               clan/poo/object#$self-slot-spec::t
                                               __tmp5295)))))
                               (__tmp5291 (list)))
                           (declare (not safe))
                           (clan/poo/object#object:::init!__%
                            '#f
                            '()
                            __tmp5292
                            __tmp5291
                            __obj5232))
                         __obj5232)))
             _%context2025%_)))))
    (define core/types#poo-flow-predicate-type-element?
      (lambda (_%type2018%_ _%candidate2019%_)
        (if (eq? (let ()
                   (declare (not safe))
                   (clan/poo/object#.ref _%type2018%_ '.classify))
                 (let ()
                   (declare (not safe))
                   (clan/poo/object#.ref _%type2018%_ '.predicate-classify)))
            ((let ()
               (declare (not safe))
               (clan/poo/object#.ref _%type2018%_ '.predicate))
             _%candidate2019%_)
            (core/types#poo-flow-type-element?
             _%type2018%_
             _%candidate2019%_))))
    (define core/types#PooFlowPredicateType.
      (let ((__obj5233
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5297
               (list (cons 'sexp
                           (let ((__tmp5298
                                  (lambda (_%@2003%_) 'PooFlowPredicateType.)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5298)))
                     (cons '.element?
                           (let ((__tmp5299
                                  (lambda (_%@2009%_)
                                    (lambda (_%$%g20132015%_)
                                      (core/types#poo-flow-predicate-type-element?
                                       _%@2009%_
                                       _%$%g20132015%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5299)))))
              (__tmp5296 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           core/types#PooFlowType.
           __tmp5297
           __tmp5296
           __obj5233))
        __obj5233))
    (define core/types#poo-flow-predicate-type
      (lambda (_%identity1983%_ _%predicate1984%_)
        (let ((_%classifier1986%_
               (core/types#poo-flow-predicate-classifier
                _%identity1983%_
                _%predicate1984%_)))
          (declare (not safe))
          (clan/poo/object#.cc
           core/types#PooFlowPredicateType.
           'identity
           _%identity1983%_
           '.classify
           _%classifier1986%_
           '.predicate
           _%predicate1984%_
           '.predicate-classify
           _%classifier1986%_
           'sexp
           _%identity1983%_))))
    (define core/types#poo-flow-predicate-contract
      (lambda (_%identity1979%_ _%predicate1980%_ _%obligations1981%_)
        (let ((__tmp5300
               (core/types#poo-flow-predicate-classifier
                _%identity1979%_
                _%predicate1980%_)))
          (declare (not safe))
          (clan/poo/object#.cc
           core/types#PooFlowContract.
           'identity
           _%identity1979%_
           '.classify
           __tmp5300
           '.obligations
           _%obligations1981%_
           'sexp
           _%identity1979%_))))
    (define core/types#poo-flow-responsibility-evidence
      (lambda (_%candidate1948%_
               _%context1949%_
               _%responsibilities1950%_
               _%slot1951%_)
        (if (let ()
              (declare (not safe))
              (clan/poo/object#.slot? _%candidate1948%_ _%slot1951%_))
            (let ((__tmp5301
                   (core/types#poo-flow-contract-admit
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref
                       _%responsibilities1950%_
                       _%slot1951%_))
                    (let ()
                      (declare (not safe))
                      (clan/poo/object#.ref _%candidate1948%_ _%slot1951%_))
                    _%context1949%_)))
              (declare (not safe))
              (clan/poo/object#.cc __tmp5301 'responsibility _%slot1951%_))
            (let* ((_%classification1977%_
                    (core/types#poo-flow-classification-evidence
                     (let ((__tmp5302
                            (let ()
                              (declare (not safe))
                              (clan/poo/object#.ref
                               _%responsibilities1950%_
                               _%slot1951%_))))
                       (declare (not safe))
                       (clan/poo/object#.ref __tmp5302 'identity))
                     '#f
                     '#f
                     (list (let ((__obj5234
                                  (let ()
                                    (declare (not safe))
                                    (##structure
                                     clan/poo/object#object::t
                                     '#f
                                     '#f
                                     '#f
                                     '#f
                                     '#f
                                     '#f
                                     '#f))))
                             (let ((__tmp5304
                                    (list (cons 'kind
                                                (let ((__tmp5305
                                                       (lambda (_%self1965%_)
                                                         'missing-responsibility)))
                                                  (declare (not safe))
                                                  (##structure
                                                   clan/poo/object#$self-slot-spec::t
                                                   __tmp5305)))
                                          (cons 'responsibility
                                                (let ((__tmp5306
                                                       (lambda (_%self1972%_)
                                                         _%slot1951%_)))
                                                  (declare (not safe))
                                                  (##structure
                                                   clan/poo/object#$self-slot-spec::t
                                                   __tmp5306)))))
                                   (__tmp5303 (list)))
                               (declare (not safe))
                               (clan/poo/object#object:::init!__%
                                '#f
                                '()
                                __tmp5304
                                __tmp5303
                                __obj5234))
                             __obj5234))
                     _%context1949%_))
                   (__tmp5307
                    (core/types#poo-flow-validation-evidence
                     (let ((__tmp5308
                            (let ()
                              (declare (not safe))
                              (clan/poo/object#.ref
                               _%responsibilities1950%_
                               _%slot1951%_))))
                       (declare (not safe))
                       (clan/poo/object#.ref __tmp5308 'identity))
                     '#f
                     _%classification1977%_
                     '()
                     '#f
                     (let ()
                       (declare (not safe))
                       (clan/poo/object#.ref
                        _%classification1977%_
                        'diagnostics))
                     _%context1949%_)))
              (declare (not safe))
              (clan/poo/object#.cc __tmp5307 'responsibility _%slot1951%_)))))
    (define core/types#poo-flow-object-admit
      (lambda (_%descriptor1923%_ _%candidate1924%_ _%context1925%_)
        (let* ((_%classification1927%_
                (core/types#poo-flow-type-classify
                 _%descriptor1923%_
                 _%candidate1924%_
                 _%context1925%_))
               (_%_checked1929%_
                (if (and (core/types#poo-flow-classification-evidence?
                          _%classification1927%_)
                         (eq? (let ()
                                (declare (not safe))
                                (clan/poo/object#.ref
                                 _%descriptor1923%_
                                 'identity))
                              (let ()
                                (declare (not safe))
                                (clan/poo/object#.ref
                                 _%classification1927%_
                                 'type-identity)))
                         (equal? _%candidate1924%_
                                 (let ()
                                   (declare (not safe))
                                   (clan/poo/object#.ref
                                    _%classification1927%_
                                    'candidate)))
                         (equal? _%context1925%_
                                 (let ()
                                   (declare (not safe))
                                   (clan/poo/object#.ref
                                    _%classification1927%_
                                    'context))))
                    '#!void
                    (begin
                      (let ((__tmp5309
                             (let ((__obj5235
                                    (let ()
                                      (declare (not safe))
                                      (##structure
                                       clan/poo/mop#TypeError::t
                                       '#f
                                       '#f
                                       '#f
                                       '#f))))
                               (let ((__tmp5310
                                      (cons 'PooFlowClassificationEvidence
                                            (cons _%classification1927%_
                                                  '()))))
                                 (declare (not safe))
                                 (clan/poo/mop#TypeError:::init!
                                  __obj5235
                                  '"type error"
                                  'where:
                                  '"\"core/types.ss\"@324.31-324.60"
                                  'irritants:
                                  __tmp5310))
                               __obj5235)))
                        (declare (not safe))
                        (raise __tmp5309))
                      '#!void)))
               (_%responsibilities1931%_
                (let ()
                  (declare (not safe))
                  (clan/poo/object#.ref _%descriptor1923%_ 'responsibilities)))
               (_%evidence1937%_
                (if (core/types#poo-flow-classification-evidence-accepted?
                     _%classification1927%_)
                    (map (lambda (_%$%g19321934%_)
                           (core/types#poo-flow-responsibility-evidence
                            _%candidate1924%_
                            _%context1925%_
                            _%responsibilities1931%_
                            _%$%g19321934%_))
                         (let ()
                           (declare (not safe))
                           (clan/poo/object#.all-slots
                            _%responsibilities1931%_)))
                    '()))
               (_%rejections1941%_
                (let ((__tmp5311
                       (lambda (_%item1939%_)
                         (not (core/types#poo-flow-validation-evidence-accepted?
                               _%item1939%_)))))
                  (declare (not safe))
                  (##filter __tmp5311 _%evidence1937%_)))
               (_%obligations1943%_
                (if (and (core/types#poo-flow-classification-evidence-accepted?
                          _%classification1927%_)
                         (null? _%rejections1941%_))
                    (core/types#poo-flow-contract-obligations
                     _%descriptor1923%_
                     _%candidate1924%_
                     _%context1925%_)
                    '()))
               (_%failures1945%_
                (append _%rejections1941%_ _%obligations1943%_))
               (__tmp5312
                (core/types#poo-flow-validation-evidence
                 (let ()
                   (declare (not safe))
                   (clan/poo/object#.ref _%descriptor1923%_ 'identity))
                 _%candidate1924%_
                 _%classification1927%_
                 _%failures1945%_
                 (if (core/types#poo-flow-classification-evidence-accepted?
                      _%classification1927%_)
                     (null? _%failures1945%_)
                     '#f)
                 (let ((__tmp5313
                        (let ()
                          (declare (not safe))
                          (clan/poo/object#.ref
                           _%classification1927%_
                           'diagnostics))))
                   (declare (not safe))
                   (##append __tmp5313 _%failures1945%_))
                 _%context1925%_)))
          (declare (not safe))
          (clan/poo/object#.cc
           __tmp5312
           'responsibility-evidence
           _%evidence1937%_))))
    (define core/types#PooFlowResponsibilityContract.
      (let ((__obj5236
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5315
               (list (cons 'sexp
                           (let ((__tmp5316
                                  (lambda (_%@1905%_)
                                    'PooFlowResponsibilityContract.)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5316)))
                     (cons '.admit
                           (let ((__tmp5317
                                  (lambda (_%@1911%_)
                                    (lambda (_%$%g19151918%_ _%$%g19161920%_)
                                      (core/types#poo-flow-object-admit
                                       _%@1911%_
                                       _%$%g19151918%_
                                       _%$%g19161920%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5317)))))
              (__tmp5314 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           core/types#PooFlowContract.
           __tmp5315
           __tmp5314
           __obj5236))
        __obj5236))
    (define core/types#poo-flow-native-classify
      (lambda (_%identity1861%_
               _%proto1862%_
               _%candidate1863%_
               _%context1864%_)
        (let ((_%accepted?1866%_
               (if (let ()
                     (declare (not safe))
                     (##structure-instance-of?
                      _%candidate1863%_
                      'clan/poo/object#object::t))
                   (if (memq _%proto1862%_
                             (let ()
                               (declare (not safe))
                               (clan/poo/object#compute-precedence-list!__0
                                _%candidate1863%_)))
                       '#t
                       '#f)
                   '#f)))
          (core/types#poo-flow-classification-evidence
           _%identity1861%_
           _%candidate1863%_
           _%accepted?1866%_
           (if _%accepted?1866%_
               '()
               (list (let ((__obj5237
                            (let ()
                              (declare (not safe))
                              (##structure
                               clan/poo/object#object::t
                               '#f
                               '#f
                               '#f
                               '#f
                               '#f
                               '#f
                               '#f))))
                       (let ((__tmp5319
                              (list (cons 'kind
                                          (let ((__tmp5320
                                                 (lambda (_%self1881%_)
                                                   'prototype-mismatch)))
                                            (declare (not safe))
                                            (##structure
                                             clan/poo/object#$self-slot-spec::t
                                             __tmp5320)))
                                    (cons 'type-identity
                                          (let ((__tmp5321
                                                 (lambda (_%self1888%_)
                                                   _%identity1861%_)))
                                            (declare (not safe))
                                            (##structure
                                             clan/poo/object#$self-slot-spec::t
                                             __tmp5321)))))
                             (__tmp5318 (list)))
                         (declare (not safe))
                         (clan/poo/object#object:::init!__%
                          '#f
                          '()
                          __tmp5319
                          __tmp5318
                          __obj5237))
                       __obj5237)))
           _%context1864%_))))
    (define core/types#PooFlowNativeObjectContract.
      (let ((__obj5238
             (let ()
               (declare (not safe))
               (##structure
                clan/poo/object#object::t
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f
                '#f))))
        (let ((__tmp5323
               (list (cons 'sexp
                           (let ((__tmp5324
                                  (lambda (_%@1843%_)
                                    'PooFlowNativeObjectContract.)))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5324)))
                     (cons '.classify
                           (let ((__tmp5325
                                  (lambda (_%@1849%_)
                                    (lambda (_%$%g18531856%_ _%$%g18541858%_)
                                      (core/types#poo-flow-native-classify
                                       (let ()
                                         (declare (not safe))
                                         (clan/poo/object#.ref
                                          _%@1849%_
                                          'identity))
                                       (let ()
                                         (declare (not safe))
                                         (clan/poo/object#.ref
                                          _%@1849%_
                                          'proto))
                                       _%$%g18531856%_
                                       _%$%g18541858%_)))))
                             (declare (not safe))
                             (##structure
                              clan/poo/object#$self-slot-spec::t
                              __tmp5325)))))
              (__tmp5322 (list)))
          (declare (not safe))
          (clan/poo/object#object:::init!__%
           '#f
           core/types#PooFlowResponsibilityContract.
           __tmp5323
           __tmp5322
           __obj5238))
        __obj5238))))
