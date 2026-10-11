# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Source-bound research review. Scheme derives answers; no execution authority.

The host must authenticate observations and choose complete input/requirement
sets. A passed receipt is evidence of its named claim, never universal truth.
"""
import copy

from .derivations import EvidenceChain


ARITIES = {
    "Candidate": 3,  # candidate, scope, tested-input identity
    "Failure": 4,  # failure, scope, tested-input identity, report reference
    "Passed": 2,  # receipt, qualified claim
    "ReceiptInput": 3,  # receipt, input key, expected identity
    "CurrentInput": 2,  # input key, current identity
    "ReceiptDepends": 2,
    "Requires": 2,  # candidate, qualified claim
    "ClaimDepends": 2,
    "Cause": 3,  # candidate, failure, reviewed causal-evidence receipt
}
OUTPUTS = {
    "KnownFailure": 3, "Established": 2, "Reusable": 2,
    "Missing": 2, "Unusable": 2, "Denial": 2,
    "Need": 2, "ReceiptPath": 2, "CausalEvidence": 3,
}


def sources(facts):
    if set(facts) - set(ARITIES):
        raise ValueError("unknown review relation")
    result = []
    for name, width in ARITIES.items():
        rows = facts.get(name, [])
        if not isinstance(rows, (list, tuple)):
            raise ValueError("review rows must be arrays")
        if any(not isinstance(row, (list, tuple)) or len(row) != width
               or any(not isinstance(v, str) or not v for v in row) for row in rows):
            raise ValueError("nonempty symbol columns required: " + name)
        rows = sorted({tuple(row) for row in rows})
        if name in ("Candidate", "Failure", "CurrentInput"):
            if len({row[0] for row in rows}) != len(rows):
                raise ValueError("conflicting identity: " + name)
        result.append({"name": name, "source": True,
                       "columns": [{"kind": "symbol"}] * width,
                       "rows": [list(row) for row in rows]})
    return result


def program(base):
    """Stratified rules; absence is meaningful only in this supplied snapshot."""
    declarations = dict(OUTPUTS, PassedId=1, Bound=1, Bad=1, Claim=1,
                        HasRequirement=1, Relevant=4, HasCause=2)
    rules = []

    def atom(name, *terms, absent=False):
        return {"relation": name, "not": absent, "terms": [
            {"const": t[1:]} if t.startswith("=") else {"var": t} for t in terms]}

    def rule(head, *body):
        rules.append({"head": [head], "body": list(body)})

    rule(atom("PassedId", "r"), atom("Passed", "r", "p"))
    rule(atom("Bound", "r"), atom("ReceiptInput", "r", "k", "v"))
    rule(atom("ReceiptPath", "r", "d"), atom("ReceiptDepends", "r", "d"))
    rule(atom("ReceiptPath", "r", "d"), atom("ReceiptPath", "r", "x"), atom("ReceiptDepends", "x", "d"))
    rule(atom("Unusable", "r", "=unbound-inputs"), atom("PassedId", "r"), atom("Bound", "r", absent=True))
    rule(atom("Unusable", "r", "=stale-or-missing-input"), atom("ReceiptInput", "r", "k", "v"), atom("CurrentInput", "k", "v", absent=True))
    rule(atom("Unusable", "r", "=missing-dependency"), atom("ReceiptPath", "r", "d"), atom("PassedId", "d", absent=True))
    rule(atom("Unusable", "r", "=circular-justification"), atom("ReceiptPath", "r", "r"))
    rule(atom("Unusable", "r", "=invalid-dependency"), atom("ReceiptPath", "r", "d"), atom("Unusable", "d", "reason"))
    rule(atom("Bad", "r"), atom("Unusable", "r", "reason"))
    rule(atom("Reusable", "r", "p"), atom("Passed", "r", "p"), atom("Bad", "r", absent=True))
    rule(atom("Established", "p", "r"), atom("Reusable", "r", "p"))
    rule(atom("Claim", "p"), atom("Established", "p", "r"))
    rule(atom("Need", "c", "p"), atom("Requires", "c", "p"))
    rule(atom("Need", "c", "q"), atom("Need", "c", "p"), atom("ClaimDepends", "p", "q"))
    rule(atom("HasRequirement", "c"), atom("Requires", "c", "p"))
    rule(atom("Missing", "c", "p"), atom("Need", "c", "p"), atom("Claim", "p", absent=True))
    rule(atom("Relevant", "c", "f", "i", "report"), atom("Candidate", "c", "s", "ci"), atom("Failure", "f", "s", "i", "report"))
    rule(atom("KnownFailure", "c", "f", "report"), atom("Relevant", "c", "f", "i", "report"))
    rule(atom("CausalEvidence", "c", "f", "r"), atom("Cause", "c", "f", "r"), atom("Reusable", "r", "p"))
    rule(atom("HasCause", "c", "f"), atom("CausalEvidence", "c", "f", "r"))
    rule(atom("Denial", "c", "=unchanged-failed-inputs"), atom("Candidate", "c", "s", "i"), atom("Failure", "f", "s", "i", "report"))
    rule(atom("Denial", "c", "=missing-causal-evidence"), atom("Relevant", "c", "f", "i", "report"), atom("HasCause", "c", "f", absent=True))
    rule(atom("Denial", "c", "=missing-premise"), atom("Missing", "c", "p"))
    rule(atom("Denial", "c", "=missing-requirement-set"), atom("Candidate", "c", "s", "i"), atom("HasRequirement", "c", absent=True))
    return {"relations": copy.deepcopy(base) + [
        {"name": name, "columns": [{"kind": "symbol"}] * width,
         "source": False, "rows": []} for name, width in declarations.items()],
        "rules": rules, "queries": list(OUTPUTS)}


class EvidenceReview:
    """Explain failed routes, reusable evidence and gaps; never allow execution.

    Receipt dependency cycles invalidate reuse. Input replacement invalidates
    all retained results through EvidenceChain. The host still owns provenance,
    causal-link review, requirement completeness and final execution admission.
    """
    def __init__(self, engine, facts):
        self.sources = sources(facts)
        self.chain = EvidenceChain(engine, self.sources)

    def replace(self, facts):
        replacement = sources(facts)
        self.chain.replace(replacement)
        self.sources = replacement

    def review(self):
        receipt = self.chain.query(program(self.sources))
        rows = receipt["result"]["relations"]
        receipt.update(
            schema="ascent-evidence-review.v1",
            decisions=[{"candidate": row[0],
                        "decision": "DENY" if any(d[0] == row[0] for d in rows["Denial"]) else "REVIEW_REQUIRED"}
                       for source in self.sources if source["name"] == "Candidate" for row in source["rows"]],
            executionAuthorized=False,
            scope="Finite supplied observations and declared dependencies; not native correctness or execution permission.",
        )
        return receipt

    def close(self):
        self.chain.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
