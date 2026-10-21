-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
/-! Closed expression lowering under the same canonical primitive bindings.
Primitive results include errors. This theorem covers the expression transform,
not Gerbil expansion, reader admission, or arbitrary Scheme syntax. Scheme tests
must establish those representation and ownership obligations separately. -/
namespace Ascent.ClosedDslLowering
inductive Value where
  | boolean (b : Bool)
  | scalar (n : Int)
  | text (s : String)
  | empty
  | pair (head tail : Value)
  deriving DecidableEq, Repr
abbrev Result := Except String Value
def truth : Value → Bool
  | .boolean false => false
  | _ => true
inductive Expr where
  | literal (v : Value)
  | variable (n : Nat)
  | unary (op : Nat) (a : Expr)
  | binary (op : Nat) (a b : Expr)
  | andThen (a b : Expr)
  | orElse (a b : Expr)
abbrev Env := Nat → Result
abbrev Unary := Nat → Value → Result
abbrev Binary := Nat → Value → Value → Result
def eval (u : Unary) (b : Binary) (env : Env) : Expr → Result
  | .literal v => .ok v
  | .variable n => env n
  | .unary op a => (eval u b env a).bind (u op)
  | .binary op a c => (eval u b env a).bind fun x => (eval u b env c).bind (b op x)
  | .andThen a c => (eval u b env a).bind fun x => if truth x then eval u b env c else .ok x
  | .orElse a c => (eval u b env a).bind fun x => if truth x then .ok x else eval u b env c
def compile (u : Unary) (b : Binary) : Expr → Env → Result
  | .literal v => fun _ => .ok v
  | .variable n => fun env => env n
  | .unary op a => let child := compile u b a; fun env => (child env).bind (u op)
  | .binary op a c => let left := compile u b a; let right := compile u b c
                     fun env => (left env).bind fun x => (right env).bind (b op x)
  | .andThen a c => let left := compile u b a; let right := compile u b c
                      fun env => (left env).bind fun x => if truth x then right env else .ok x
  | .orElse a c => let left := compile u b a; let right := compile u b c
                     fun env => (left env).bind fun x => if truth x then .ok x else right env
 theorem equivalent (u : Unary) (b : Binary) (e : Expr) :
    ∀ env, compile u b e env = eval u b env e := by
  induction e <;> intro env <;> simp_all [compile, eval]
example : truth (.scalar 0) = true := rfl
example (u : Unary) (b : Binary) (env : Env) (e : Expr) :
    eval u b env (.andThen (.literal (.boolean false)) e) = .ok (.boolean false) := rfl
example (u : Unary) (b : Binary) (env : Env) (e : Expr) :
    eval u b env (.orElse (.literal (.scalar 0)) e) = .ok (.scalar 0) := rfl
def structuralEquality (_ : Nat) (left right : Value) : Result :=
  .ok (.boolean (decide (left = right)))
example (u : Unary) (env : Env) :
    compile u structuralEquality
      (.binary 0 (.literal (.pair (.text "a") (.pair (.scalar 1) .empty)))
                 (.literal (.pair (.text "a") (.pair (.scalar 1) .empty)))) env =
      .ok (.boolean true) := rfl
example (u : Unary) (env : Env) :
    compile u structuralEquality (.binary 0 (.literal (.text "1"))
      (.literal (.scalar 1))) env = .ok (.boolean false) := rfl
-- Closed Evidence selection is all-or-nothing. Admission stores declarations,
-- not a previously constructed result. Every accepted call invokes the same
-- declaration constructor as the macro, with its current invocation identity.
def closedScope {D V : Type} (construct : D → Nat → V)
    (declarations : List D) (index : Nat) (invocation : Nat) : Option V :=
  (declarations[index]?).map (fun declaration => construct declaration invocation)
theorem scope_constructor_equivalent {D V : Type} (construct : D → Nat → V)
    (declarations : List D) (index invocation : Nat) :
    closedScope construct declarations index invocation =
      (declarations[index]?).map (fun declaration => construct declaration invocation) := rfl
theorem distinct_invocations {D : Type} (declarations : List D) (index first second : Nat)
    (present : ∃ declaration, declarations[index]? = some declaration)
    (different : first ≠ second) :
    closedScope (fun (_ : D) invocation => invocation) declarations index first ≠
      closedScope (fun (_ : D) invocation => invocation) declarations index second := by
  obtain ⟨declaration, found⟩ := present
  simp [closedScope, found, different]
-- A compiler-resolved reader takes the current store on every invocation.
-- Replacing lookup by a previously read value would not satisfy this contract.
def exportReader {S V : Type} (lookup : S → V) : S → V := fun store => lookup store
theorem export_current_binding {S V : Type} (lookup : S → V) (store : S) :
    exportReader lookup store = lookup store := rfl
-- Source-linked construction/workload costs. Complete root admission remains
-- mandatory; the native Contract implementation and macro recognizer are premises.
def publicTermChecks (terms : Nat) : Nat := 4 * terms
def ownedTermChecks (terms : Nat) : Nat := terms
 theorem owned_checks_no_more (terms : Nat) :
    ownedTermChecks terms ≤ publicTermChecks terms := by
  simp [ownedTermChecks, publicTermChecks]; omega

def exhaustiveEvaluations : Nat := 512 * 2 * (1 + 2)
def exhaustiveOracleCalls : Nat := 512 * 2 * (1 + 2)
 theorem complete_exhaustive_matrix :
    exhaustiveEvaluations = 3072 ∧ exhaustiveOracleCalls = 3072 := by decide

-- The checked corpus asserts fourteen variable Terms per rule graph.
-- Public constructors recheck them at Term/Atom/Rule/Program boundaries;
-- the closed tree path retains the complete Program-root traversal.
def oldCorpusTermChecks : Nat := 3072 * publicTermChecks 14
def newCorpusTermChecks : Nat := 1024 * publicTermChecks 14 + 2048 * ownedTermChecks 14
 theorem corpus_term_check_reduction : newCorpusTermChecks * 2 = oldCorpusTermChecks := by decide

-- Successful positive snapshots check the complete caller root and copied
-- root. The frozen copier additionally checks Term/Atom/Rule intermediates.
-- No theorem here identifies validation callbacks with arbitrary pure functions.
def publicSnapshotTermChecks (terms : Nat) : Nat := terms + publicTermChecks terms
def capturedSnapshotTermChecks (terms : Nat) : Nat := terms + ownedTermChecks terms

theorem snapshot_both_roots_retained (terms : Nat) :
    capturedSnapshotTermChecks terms = terms + terms := rfl

theorem snapshot_intermediate_checks_removed (terms : Nat) :
    capturedSnapshotTermChecks terms + 3 * terms = publicSnapshotTermChecks terms := by
  simp [capturedSnapshotTermChecks, publicSnapshotTermChecks, publicTermChecks, ownedTermChecks]
  omega

-- A state-level TLC invariant keeps the complete cost predicate and adds
-- a real nonnegative work counter. This is conjunction, never conditional
-- admission: every state satisfying the new invariant satisfies the old one.
theorem snapshot_state_invariant_not_weakened (cost : Prop) (attempts : Int) :
    (cost ∧ 0 ≤ attempts) → cost := And.left

-- Canonical construction is pure after captures. Capture failure propagates
-- before construction, and complete root rejection cannot publish a value.
def admittedConstruction {E C P : Type} (capture : Except E C)
    (construct : C → P) (check : P → Except E P) : Except E P :=
  capture.bind (fun captured => check (construct captured))
 theorem failed_capture_prevents_construction {E C P : Type} (failure : E)
    (construct : C → P) (check : P → Except E P) :
    admittedConstruction (.error failure) construct check = .error failure := rfl
 theorem rejected_root_not_published {E C P : Type} (captured : C)
    (construct : C → P) (check : P → Except E P) (failure : E)
    (rejected : check (construct captured) = .error failure) :
    admittedConstruction (.ok captured) construct check = .error failure := rejected

def selectorSchemeSource : String :=
  "(defsyntax (relational-program stx)\n" ++
  "  (def (closed-positive? clauses)\n" ++
  "    (def has-rule? #f)\n" ++
  "    (def names\n" ++
  "      (let (index (make-hash-table-eq))\n" ++
  "        (for-each (lambda (form)\n" ++
  "          ;; Source/limit expressions stay opaque syntax, never datum copies.\n" ++
  "          (syntax-case form (relation rule)\n" ++
  "            ((relation name (column ...) rows)\n" ++
  "             (identifier? (syntax name))\n" ++
  "             (hash-put! index (syntax->datum (syntax name)) #t))\n" ++
  "            ((relation name (column ...))\n" ++
  "             (identifier? (syntax name))\n" ++
  "             (hash-put! index (syntax->datum (syntax name)) #t))\n" ++
  "            ((rule head body ...) (set! has-rule? #t))\n" ++
  "            (_ (void)))) clauses)\n" ++
  "        index))\n" ++
  "    (def (term? term)\n" ++
  "      (if (identifier? term)\n" ++
  "        (let (name (symbol->string (syntax->datum term)))\n" ++
  "          (and (> (string-length name) 1) (char=? (string-ref name 0) #\\?)))\n" ++
  "        (syntax-case term ()\n" ++
  "          ((head . tail) #f)\n" ++
  "          (_ (let (datum (syntax->datum term))\n" ++
  "               (or (exact-integer? datum) (boolean? datum) (char? datum)))))))\n" ++
  "    (def (atom? form)\n" ++
  "      (syntax-case form ()\n" ++
  "        ((name term ...)\n" ++
  "         (identifier? (syntax name))\n" ++
  "         (let (name (syntax->datum (syntax name)))\n" ++
  "           (and (hash-get names name) (not (memq name '(where compute not reduce)))\n" ++
  "                (andmap term? (syntax->list (syntax (term ...)))))))\n" ++
  "        (_ #f)))\n" ++
  "    (and has-rule?\n" ++
  "      (andmap (lambda (form)\n" ++
  "        (syntax-case form (relation rule limits)\n" ++
  "          ((relation name (column ...) rows)\n" ++
  "           (and (identifier? (syntax name))\n" ++
  "                (andmap identifier? (syntax->list (syntax (column ...))))))\n" ++
  "          ((relation name (column ...))\n" ++
  "           (and (identifier? (syntax name))\n" ++
  "                (andmap identifier? (syntax->list (syntax (column ...))))))\n" ++
  "          ((limits input derived output) #t)\n" ++
  "          ((rule head body ...) (andmap atom? (syntax->list (syntax (head body ...)))))\n" ++
  "          (_ #f))) clauses)))\n" ++
  "  (syntax-case stx ()\n" ++
  "    ((_ clause ...)\n" ++
  "     (if (closed-positive? (syntax->list (syntax (clause ...))))\n" ++
  "       (syntax (relational-collect relational-owned-program () () clause ...))\n" ++
  "       (syntax (relational-collect gerbil-ascent-program () () clause ...))))))\n"

def rootSchemeSource : String :=
  "(def (receive-inert-declarations construct receive)\n" ++
  "  (call-with-values\n" ++
  "   (lambda ()\n" ++
  "     (parameterize ((current-declaration-check (lambda (_contract value) value)))\n" ++
  "       (construct)))\n" ++
  "   receive))\n" ++
  "\n" ++
  ";;; Empty roots have no shared Terms. Rule-bearing roots borrow a fresh POO\n" ++
  ";;; refinement only while validating; the published value retains no checker.\n" ++
  ";; : (forall (c a) (-> c a a))\n" ++
  ";; : (-> DeclarationRootContract OwnedDeclarationRoot ValidatedRoot)\n" ++
  "(def (validate-inert-root contract value (memoize-terms? #t))\n" ++
  "  (validate (if (or (not memoize-terms?) (null? (.ref value 'rules))) contract\n" ++
  "              (gerbil-ascent-owned-root-contract contract)) value))\n" ++
  ";; A canonical tree can use the ordinary complete root contract without a\n" ++
  ";; fresh shared-Term memo descriptor. Both modes perform full root admission.\n" ++
  ";; The producer may return a Program alone or a Program and its output handle.\n" ++
  ";; Receive both outside the construction extent, validating before publication.\n" ++
  ";; : (forall (p a) (-> (-> (Values p a)) (Values p a)))\n" ++
  ";; : (-> InertProgramConstructor (Values ValidatedProgram OutputHandle))\n" ++
  "(def (gerbil-ascent-construct-inert-program construct (memoize-terms? #t))\n" ++
  "  (receive-inert-declarations construct\n" ++
  "   (case-lambda\n" ++
  "     ((program) (validate-inert-root GerbilAscentProgramContract program memoize-terms?))\n" ++
  "     ((program output)\n" ++
  "      (let (checked (validate-inert-root GerbilAscentProgramContract program memoize-terms?))\n" ++
  "        (values checked output))))))\n" ++
  "\n"

def ownedMacroSchemeSource : String :=
  "(defsyntax (relational-owned-program stx)\n" ++
  "  (syntax-case stx ()\n" ++
  "    ((_ relations rules input derived output handles)\n" ++
  "     ;; All user expressions run before the private construction extent.\n" ++
  "     ;; The selected rule syntax contains only canonical atoms and scalars.\n" ++
  "     (syntax (let ((relation-values relations)\n" ++
  "                   (input-limit input) (derived-limit derived)\n" ++
  "                   (output-limit output) (source-handles handles))\n" ++
  "               (gerbil-ascent-construct-inert-program\n" ++
  "                (lambda ()\n" ++
  "                  (gerbil-ascent-program relation-values rules input-limit derived-limit\n" ++
  "                                         output-limit source-handles)) #f))))))\n" ++
  "\n"

def workloadSchemeSource : String :=
  "(def (declaration edges rules)\n" ++
  " (def (atom form) (gerbil-ascent-atom (car form) (map gerbil-ascent-variable (cdr form))))\n" ++
  " (gerbil-ascent-program\n" ++
  "  (list (gerbil-ascent-relation 'edge 2 edges) (gerbil-ascent-relation 'p 2 []) (gerbil-ascent-relation 'q 2 []))\n" ++
  "  (map (lambda (rule) (gerbil-ascent-rule (list (atom (car rule))) (map atom (cdr rule)))) rules)\n" ++
  "  10000 10000 10000))\n" ++
  "(def (owned-declaration edges rules)\n" ++
  " ;; This fixture supplies only closed integer rows and fixed rule data.\n" ++
  " ;; Preserve the exact public schema, including callback-free Actor fields.\n" ++
  " (gerbil-ascent-construct-inert-program (lambda () (declaration edges rules)) #f))\n" ++
  "(def (verify mask rules workers)\n" ++
  " (let* ((edges (graph-input mask)) (program (if (= workers 1) (declaration edges rules) (owned-declaration edges rules)))\n" ++
  "        (actual (gerbil-ascent-evaluate-program program workers: workers)))\n" ++
  "  (let-values (((expected _) (naive-positive (graph-input mask) rules)))\n" ++
  "   (check-equal? (.ref actual 'finished) #t)\n" ++
  "   (for-each (lambda (name)\n" ++
  "     (check-equal? (canonical-rows ((.ref actual 'rows-of) name))\n" ++
  "                   (canonical-rows (cdr (assq name expected))))) '(edge p q)))))\n" ++
  "(def ascent-semi-naive-test\n" ++
  " (test-suite \"Independent least fixed point and disjoint delta witnesses\"\n" ++
  "  (test-case \"all three-node graphs agree with independent naive consequences\"\n" ++
  "   (for-each (lambda (mask) (verify mask naive-rules 1)\n" ++
  "     (verify mask (reverse naive-rules) 1)) (iota 512)))\n" ++
  "  (test-case \"Actor reschedules empty consumers and nonlinear mutual recursion\"\n" ++
  "   (check-equal? (foldl (lambda (rule total)\n" ++
  "     (+ total (foldl (lambda (atom n) (+ n (length (cdr atom)))) 0 rule))) 0 naive-rules) 14)\n" ++
  "   (let* ((sample (owned-declaration (graph-input 511) naive-rules))\n" ++
  "          (relations (.ref sample 'relations))\n" ++
  "          (schema (gerbil-ascent-program-schema sample relations))\n" ++
  "          (analysis (gerbil-ascent-prepare-program relations (.ref sample 'rules) schema #f)))\n" ++
  "     (check-equal? (gerbil-ascent-actor-round-eligible?\n" ++
  "                    (apply append (vector->list (gerbil-ascent-activate-rules analysis))) (vector-ref schema 9) (vector-ref schema 5)\n" ++
  "                    (vector-ref schema 7) (vector-ref schema 3)) #t))\n" ++
  "   (for-each (lambda (workers)\n" ++
  "    (for-each (lambda (mask)\n" ++
  "     (verify mask naive-rules workers)\n" ++
  "     (verify mask (reverse naive-rules) workers)) (iota 512))) '(2 4)))\n"

def snapshotSchemeSource : String :=
  ";;; -*- Gerbil -*-\n" ++
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n" ++
  ";;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n" ++
  "\n" ++
  "\n" ++
  ";;; Rebuild caller declarations into the checked scalar grammar before planning.\n" ++
  ";;; This owner constructs no evaluator or retained session.\n" ++
  "(import \"objects.ss\" \"scheme-checked.ss\"\n" ++
  "        (only-in \"types.ss\" GerbilAscentProgramContract)\n" ++
  "        (only-in :clan/poo/object .ref)\n" ++
  "        (only-in :clan/poo/mop validate))\n" ++
  "(export relational-snapshot-program)\n" ++
  "\n" ++
  ";;; Admission rebuilds only the checked relational grammar. This removes\n" ++
  ";;; caller-owned row/rule lists before planning and rejects old host callbacks.\n" ++
  "(def (relational-copy-term term)\n" ++
  "  (case (.ref term 'kind)\n" ++
  "    ((variable) (gerbil-ascent-variable (.ref term 'value)))\n" ++
  "    ((wildcard) (gerbil-ascent-wildcard))\n" ++
  "    ((literal)\n" ++
  "     (let (value (.ref term 'value))\n" ++
  "       (unless (relational-scalar? value)\n" ++
  "         (error \"non-scalar relational literal\" value))\n" ++
  "       (gerbil-ascent-literal value)))\n" ++
  "    (else (error \"unsupported relational term\" (.ref term 'kind)))))\n" ++
  "\n" ++
  ";;; Rebuild from the descriptor, never from the callback stored for the old\n" ++
  ";;; evaluator. An unmarked guard or binding cannot cross admission.\n" ++
  "(def (relational-copy-clause clause)\n" ++
  "  (case (.ref clause 'ascent-clause-kind)\n" ++
  "    ((negation)\n" ++
  "     (gerbil-ascent-negation\n" ++
  "      (.ref clause 'relation)\n" ++
  "      (map relational-copy-term (.ref clause 'terms))))\n" ++
  "    ((aggregate)\n" ++
  "     (let ((descriptor (.ref clause 'checked-operator))\n" ++
  "           (terms (.ref clause 'terms)))\n" ++
  "       (unless (and (vector? descriptor)\n" ++
  "                    (= (vector-length descriptor) 6)\n" ++
  "                    (eq? (vector-ref descriptor 0) 'reduce)\n" ++
  "                    (eq? (vector-ref descriptor 2)\n" ++
  "                         (.ref clause 'variable))\n" ++
  "                    (eq? (vector-ref descriptor 3)\n" ++
  "                         (.ref clause 'relation))\n" ++
  "                    (equal? (vector-ref descriptor 4)\n" ++
  "                            (.ref clause 'variables))\n" ++
  "                    (equal? (vector-ref descriptor 5)\n" ++
  "                            (relational-term-fingerprint terms))\n" ++
  "                    (not (.ref clause 'output-pattern)))\n" ++
  "         (error \"untrusted relational reduction\"))\n" ++
  "       (relational-reducer\n" ++
  "        (vector-ref descriptor 2) (vector-ref descriptor 1)\n" ++
  "        (vector-ref descriptor 4) (vector-ref descriptor 3)\n" ++
  "        (map relational-copy-term terms))))\n" ++
  "    ((guard)\n" ++
  "     (let (descriptor (.ref clause 'checked-operator))\n" ++
  "       (unless (and (vector? descriptor)\n" ++
  "                    (= (vector-length descriptor) 3)\n" ++
  "                    (eq? (vector-ref descriptor 0) 'where)\n" ++
  "                    (equal? (relational-operand-variables\n" ++
  "                             (vector-ref descriptor 2))\n" ++
  "                            (.ref clause 'variables)))\n" ++
  "         (error \"untrusted relational filter\"))\n" ++
  "       (relational-where (vector-ref descriptor 1)\n" ++
  "                         (vector-ref descriptor 2))))\n" ++
  "    ((binding)\n" ++
  "     (let (descriptor (.ref clause 'checked-operator))\n" ++
  "       (unless (and (vector? descriptor)\n" ++
  "                    (= (vector-length descriptor) 4)\n" ++
  "                    (eq? (vector-ref descriptor 0) 'compute)\n" ++
  "                    (equal? (relational-operand-variables\n" ++
  "                             (vector-ref descriptor 2))\n" ++
  "                            (.ref clause 'variables))\n" ++
  "                    (eq? (vector-ref descriptor 3)\n" ++
  "                         (.ref clause 'variable)))\n" ++
  "         (error \"untrusted relational projection\"))\n" ++
  "       (relational-compute (vector-ref descriptor 3)\n" ++
  "                            (vector-ref descriptor 1)\n" ++
  "                            (vector-ref descriptor 2))))\n" ++
  "    (else (error \"unsupported relational clause\"\n" ++
  "                 (.ref clause 'ascent-clause-kind)))))\n" ++
  "\n" ++
  ";;; Capture caller slots outside the private construction extent. Only closed\n" ++
  ";;; canonical builders may execute inside it; no caller getter or supplied\n" ++
  ";;; callback is retained. Nonatom descriptors keep their ordinary checked copy.\n" ++
  "(def (relational-capture-term term)\n" ++
  "  (case (.ref term 'kind)\n" ++
  "    ((variable)\n" ++
  "     (let (name (.ref term 'value))\n" ++
  "       (unless (symbol? name) (error \"ASCENT variable name must be a symbol\" name))\n" ++
  "       (lambda () (gerbil-ascent-variable name))))\n" ++
  "    ((wildcard) (lambda () (gerbil-ascent-wildcard)))\n" ++
  "    ((literal)\n" ++
  "     (let (value (.ref term 'value))\n" ++
  "       (unless (relational-scalar? value)\n" ++
  "         (error \"non-scalar relational literal\" value))\n" ++
  "       (lambda () (gerbil-ascent-literal value))))\n" ++
  "    (else (error \"unsupported relational term\" (.ref term 'kind)))))\n" ++
  "\n" ++
  "(def (relational-capture-atom atom)\n" ++
  "  (unless (eq? (.ref atom 'ascent-clause-kind) 'atom)\n" ++
  "    (error \"unsupported relational clause\"))\n" ++
  "  (let ((name (.ref atom 'relation))\n" ++
  "        (terms (map relational-capture-term (.ref atom 'terms))))\n" ++
  "    (lambda () (gerbil-ascent-atom name (map (lambda (build) (build)) terms)))))\n" ++
  "\n" ++
  "(def (relational-capture-clause clause)\n" ++
  "  (if (eq? (.ref clause 'ascent-clause-kind) 'atom)\n" ++
  "    (relational-capture-atom clause)\n" ++
  "    (let (copied (relational-copy-clause clause)) (lambda () copied))))\n" ++
  "\n" ++
  "(def (relational-capture-rule rule)\n" ++
  "  (let ((heads (map relational-capture-atom (.ref rule 'heads)))\n" ++
  "        (body (map relational-capture-clause (.ref rule 'body))))\n" ++
  "    (lambda ()\n" ++
  "      (gerbil-ascent-rule (map (lambda (build) (build)) heads)\n" ++
  "                         (map (lambda (build) (build)) body)))))\n" ++
  "\n" ++
  ";;; The engine constructor checks relation names, arities, rule bindings,\n" ++
  ";;; dependencies and budgets before the admission value becomes observable.\n" ++
  "(def (relational-snapshot-program program)\n" ++
  "  (validate GerbilAscentProgramContract program)\n" ++
  "  (let* ((relations\n" ++
  "   (map (lambda (relation)\n" ++
  "          (let* ((domain (.ref relation 'checked-domain))\n" ++
  "                 (domains\n" ++
  "                  (and domain\n" ++
  "                       (begin\n" ++
  "                         (unless (and (vector? domain) (= (vector-length domain) 2)\n" ++
  "                                      (eq? (vector-ref domain 0) 'finite-domain))\n" ++
  "                           (error \"untrusted finite domain descriptor\"))\n" ++
  "                         (vector-ref domain 1))))\n" ++
  "                 (name (.ref relation 'name)) (arity (.ref relation 'arity))\n" ++
  "                 (rows (.ref relation 'rows)))\n" ++
  "            (case (.ref relation 'storage-kind)\n" ++
  "              ((relation)\n" ++
  "               (if domain (relational-finite-source name arity rows domains)\n" ++
  "                   (relational-source name arity rows)))\n" ++
  "              ((lattice)\n" ++
  "               (let (descriptor (.ref relation 'checked-operator))\n" ++
  "                 (unless (and (vector? descriptor) (= (vector-length descriptor) 2)\n" ++
  "                              (eq? (vector-ref descriptor 0) 'lattice))\n" ++
  "                   (error \"untrusted relational lattice\"))\n" ++
  "                 (if domain\n" ++
  "                     (relational-finite-lattice name arity rows (vector-ref descriptor 1) domains)\n" ++
  "                     (relational-checked-lattice name arity rows (vector-ref descriptor 1)))))\n" ++
  "              (else (error \"unsupported relational storage kind\")))))\n" ++
  "        (.ref program 'relations)))\n" ++
  "         (rules (map relational-capture-rule (.ref program 'rules)))\n" ++
  "         (input-limit (.ref program 'max-input-facts))\n" ++
  "         (derived-limit (.ref program 'max-derived-facts))\n" ++
  "         (output-limit (.ref program 'max-output-facts))\n" ++
  "         (sources (.ref program 'source-handles)))\n" ++
  "    ;; The source has already passed the ordinary complete Program contract.\n" ++
  "    ;; This new, private tree passes that same complete contract after restoring\n" ++
  "    ;; ordinary constructor checks. No Term validation result is memoized.\n" ++
  "    (gerbil-ascent-construct-inert-program\n" ++
  "     (lambda ()\n" ++
  "       (gerbil-ascent-program relations (map (lambda (build) (build)) rules)\n" ++
  "         input-limit derived-limit output-limit sources)) #f)))\n"

def snapshotQuintSource : String :=
  "// SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n" ++
  "// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n" ++
  "// Whole-source choice precedes construction; failure never retries another route.\n" ++
  "module ClosedDslLowering {\n" ++
  "  const Mutation: str\n" ++
  "  var phase: str\n" ++
  "  var recognized: bool\n" ++
  "  var route: str\n" ++
  "  var attempts: int\n" ++
  "  var owner: bool\n" ++
  "  var rejected: bool\n" ++
  "  action init = all {\n" ++
  "    phase' = \"reader\", recognized' = false, route' = \"none\",\n" ++
  "    attempts' = 0, owner' = false, rejected' = false\n" ++
  "  }\n" ++
  "  action Read = { nondet complete = Set(false,true).oneOf(); all {\n" ++
  "    phase == \"reader\", phase' = \"chosen\", recognized' = complete,\n" ++
  "    route' = if (complete or Mutation == \"partial\") \"closed\" else \"macro\",\n" ++
  "    attempts' = attempts, owner' = owner, rejected' = rejected\n" ++
  "  }}\n" ++
  "  action Reject = all {\n" ++
  "    phase == \"reader\", phase' = \"terminal\", rejected' = true,\n" ++
  "    recognized' = recognized, route' = route, attempts' = attempts,\n" ++
  "    owner' = Mutation == \"rejectOwner\"\n" ++
  "  }\n" ++
  "  action Construct = all {\n" ++
  "    phase == \"chosen\", phase' = \"executing\", attempts' = attempts + 1,\n" ++
  "    recognized' = recognized, route' = route, owner' = owner, rejected' = rejected\n" ++
  "  }\n" ++
  "  action Finish = { nondet success = Set(false,true).oneOf(); all {\n" ++
  "    phase == \"executing\", phase' = \"terminal\", owner' = success,\n" ++
  "    attempts' = if (not(success) and Mutation == \"retry\") attempts + 1 else attempts,\n" ++
  "    recognized' = recognized, route' = route, rejected' = not(success)\n" ++
  "  }}\n" ++
  "  action Idle = all {\n" ++
  "    phase == \"terminal\", phase' = phase, recognized' = recognized,\n" ++
  "    route' = route, attempts' = attempts, owner' = owner, rejected' = rejected\n" ++
  "  }\n" ++
  "  action step = any {Read, Reject, Construct, Finish, Idle}\n" ++
  "  // Canonical positive snapshot occurrences: caller root + copied root.\n" ++
  "  // The old copier also performs Term, Atom and Rule intermediate checks.\n" ++
  "  pure def snapshot_checks(terms: int, captured: bool): int =\n" ++
  "    if (not(captured) or Mutation == \"retain-snapshot-intermediate\") 5 * terms\n" ++
  "    else if (Mutation == \"skip-snapshot-root\") terms else 2 * terms\n" ++
  "  val SnapshotRoots = snapshot_checks(14, true) == 2 * 14 and attempts >= 0\n" ++
  "  val SnapshotWorkExact = snapshot_checks(14, false) - snapshot_checks(14, true) == 3 * 14 and attempts >= 0\n" ++
  "  val WholeChoice = route != \"closed\" or recognized\n" ++
  "  val NoRetry = attempts <= 1\n" ++
  "  val FailurePrivate = not(rejected) or not(owner)\n" ++
  "}\n"

end Ascent.ClosedDslLowering

#print axioms Ascent.ClosedDslLowering.owned_checks_no_more
#print axioms Ascent.ClosedDslLowering.complete_exhaustive_matrix
#print axioms Ascent.ClosedDslLowering.failed_capture_prevents_construction
#print axioms Ascent.ClosedDslLowering.rejected_root_not_published

#print axioms Ascent.ClosedDslLowering.corpus_term_check_reduction

#print axioms Ascent.ClosedDslLowering.snapshot_both_roots_retained
#print axioms Ascent.ClosedDslLowering.snapshot_intermediate_checks_removed

#print axioms Ascent.ClosedDslLowering.snapshot_state_invariant_not_weakened
