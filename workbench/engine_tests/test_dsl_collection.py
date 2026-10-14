"""Order and hygiene at the upstream DSL collection boundaries."""
import unittest
from ascent import Engine, EngineError
from test_module_calls import decode


class DSLCollectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.engine = Engine()

    @classmethod
    def tearDownClass(cls): cls.engine.shutdown()

    def answer(self, source):
        with self.engine.dsl(source, trusted=True) as owner:
            with owner.call('answer') as result:
                return decode(result.graph)

    def test_include_effects_and_declaration_order(self):
        self.assertEqual(self.answer('''
          (def observed [])
          (def (note x) (set! observed (append observed (list x))) [])
          (def (answer)
            (let (p (ascent
                      (relation early (x) (note "early"))
                      (include (begin (note "include")
                        (ascent-fragment (relation nested (x) (note "nested")))))
                      (relation late (x) (note "late"))))
              (list observed (map (lambda (r) (symbol->string (.ref r 'name))) (.ref p 'relations)))))
        '''), [['include', 'nested', 'early', 'late'], ['early', 'nested', 'late']])

    def test_macro_scope_default_storage_and_rule_order(self):
        with self.engine.evidence('''
          (define-evidence (make)
            (let (p (ascent
              (relation input ((x exact-integer?)) '((1)))
              (macro copied ((target ident))
                (relation target ((x exact-integer?)))
                ((target x) <-- (input x)))
              (copied middle)
              (relation output ((x exact-integer?)))
              ((output x) <-- (middle x))))
              (gerbil-ascent-program (.ref p 'relations) (.ref p 'rules) +inf.0 +inf.0 +inf.0 '(input))))
        ''', 'make', trusted=True) as session:
            with session.result(session.run(queries=['output'])) as result:
                self.assertEqual(decode(result.rows('output')['value']), [[1]])
            session.replace({'input': [[7]]})
            with session.result(session.run(queries=['output'])) as result:
                self.assertEqual(decode(result.rows('output')['value']), [[7]])

    def test_hygienic_relation_and_rule_identifiers(self):
        self.assertEqual(self.answer('''
          (defrules scene () ((_ n)
            (ascent-fragment (relation n ((x exact-integer?))))))
          (def (answer)
            (let ((declared 1) (lowered 2) (mode 3) (provider 4) (fragment-value 5))
              (let (p (ascent (include (scene input))
                         (relation output ((x exact-integer?)))
                         ((output x) <-- (input x))))
                (map (lambda (r) (symbol->string (.ref r 'name))) (.ref p 'relations)))))
        '''), ['input', 'output'])

    def test_empty_program_and_explicit_bounds(self):
        self.assertEqual(self.answer('''
          (def (answer)
            (let (p (ascent (relation input (x)) (bounds 2 3 4)))
              (list (.ref p 'max-input-facts) (.ref p 'max-derived-facts) (.ref p 'max-output-facts))))
        '''), [2, 3, 4])
        self.assertEqual(self.answer('(def (answer) (.ref (ascent-fragment) \'relations))'), [])

    def test_malformed_declarations_still_rejected(self):
        for source in ['(def (answer) (ascent (bounds 1 2 3) (relation x (v))))',
                       '(def (answer) (ascent (relation x (v) [] (unknown 1))))']:
            with self.assertRaises(EngineError): self.engine.dsl(source, trusted=True)

    def test_retained_callable_reads_mutable_export_and_keeps_scope_isolation(self):
        source = '''
          (def answer (lambda () 1))
          (def (replace value)
            (set! answer (if value (lambda () value) #f)) (void))
          (def (reader) (lambda () (answer)))
        '''
        with self.engine.dsl(source, trusted=True) as owner, \
                self.engine.dsl('(def (answer) 99)', trusted=True) as other:
            with owner.call('reader') as reader:
                for value in (1, 7, 8):
                    with owner.call('replace', value): pass
                    with owner.call('answer') as result:
                        self.assertEqual(decode(result.graph), value)
                    with reader.apply() as result:
                        self.assertEqual(decode(result.graph), value)
                    with other.call('answer') as result:
                        self.assertEqual(decode(result.graph), 99)
                with owner.call('replace', False): pass
                with self.assertRaisesRegex(EngineError, 'not a procedure'):
                    owner.call('answer')
                with owner.call('replace', 11): pass
                with owner.call('answer') as result:
                    self.assertEqual(decode(result.graph), 11)

    def test_public_typed_higher_order_dsl_without_downstream_import(self):
        self.assertEqual(self.answer('''
          (def (answer)
            (let* ((type (relational-relation-type 2 '(0 1 2)))
                   (close (relational-typed-function type
                     (lambda (edge)
                       (relational-typed-fix (relational-typed-function type
                         (lambda (path)
                           (relational-typed-union edge
                             (relational-typed-project
                               (relational-typed-join path edge 1 0) '(0 3)))))))))
                   (input (relational-typed-source 'input type '((0 1) (1 2)))))
              (let-values (((program output)
                (relational-typed-compile (relational-typed-apply close input)
                                          +inf.0 +inf.0 +inf.0)))
                (let (rows (relational-query-name
                            (relational-solve (relational-admit program)) output))
                  (and (= (length rows) 3)
                       (andmap (lambda (row) (if (member row rows) #t #f))
                               '((0 1) (1 2) (0 2))))))))
        '''), True)

    def test_declarative_evidence_rules_sources_aliases_and_owned_explanation(self):
        source = '''
          (define-evidence (make-study)
            (sources input)
            (outputs (visible copied) count best)
            (relation input ((x exact-integer?)))
            (macro copy ((target ident))
              (relation target ((x exact-integer?)))
              ((target x) <-- (input x)))
            (copy copied)
            (relation count (n))
            (lattice best (key score) [] max)
            ((count n) <-- (aggregate n gerbil-ascent-count () (input x)))
            ((best (lit 'input) x) <-- (input x)))
        '''
        with self.engine.evidence(source, 'make-study', trusted=True) as session:
            self.assertEqual([r['name'] for r in session.descriptors if r['source']], ['input'])
            with session.result(session.run(queries=[])):
                pass
            session.replace({'input': [[2], [7]]})
            with session.result(session.run(queries=['visible', 'count', 'best'])) as result:
                self.assertEqual(sorted(decode(result.rows('visible')['value'])), [[2], [7]])
                self.assertEqual(decode(result.rows('count')['value']), [[2]])
                self.assertEqual(decode(result.rows('best')['value']), [['input', 7]])
                explanation = result.explanation('visible')
            try:
                self.assertIn('recorded-only', str(explanation.graph))
                self.assertIn('per-row proof', str(explanation.graph))
            finally:
                explanation.close()
            session.replace({'input': [[2]]})
            with session.result(session.run(queries=['visible', 'count', 'best'])) as result:
                self.assertEqual(decode(result.rows('visible')['value']), [[2]])
                self.assertEqual(decode(result.rows('count')['value']), [[1]])
                self.assertEqual(decode(result.rows('best')['value']), [['input', 2]])
            session.replace({'input': [[2], [7]]})
            with session.result(session.run(queries=['visible'])) as result:
                self.assertEqual(sorted(decode(result.rows('visible')['value'])), [[2], [7]])

    def test_declarative_evidence_binding_errors_do_not_infer_sources(self):
        for clauses in (
                '(sources input) (outputs absent) (relation input (x))',
                '(sources input input) (outputs input) (relation input (x))',
                '(sources input) (outputs (input \'other)) (relation input (x)) (relation other (x))',
                '(sources input) (relation input (x))',
                '(sources input) (outputs (answer \'input) (other \'input)) (relation input (x))'):
            with self.assertRaises(EngineError):
                self.engine.evidence('(define-evidence (make-study) ' + clauses + ')',
                                     'make-study', trusted=True)
        source = '''
          (define-evidence (make-study)
            (sources) (outputs derived)
            (relation derived (x)) (fact (derived (lit 3))))
        '''
        with self.engine.evidence(source, 'make-study', trusted=True) as session:
            self.assertFalse(any(r['source'] for r in session.descriptors))
            with session.result(session.run(queries=['derived'])) as result:
                self.assertEqual(decode(result.rows('derived')['value']), [[3]])
            with self.assertRaises(EngineError):
                session.replace({'derived': [[9]]})


if __name__ == '__main__': unittest.main()
