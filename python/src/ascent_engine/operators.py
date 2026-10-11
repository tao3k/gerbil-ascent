# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Inert builders for Scheme's checked operators; no host callback execution."""
import copy


def where(operator, *terms):
    return {"mode": "where", "operator": operator, "terms": copy.deepcopy(list(terms))}


def compute(output, operator, *terms):
    return {"mode": "compute", "operator": operator, "output": output,
            "terms": copy.deepcopy(list(terms))}


def reduce(output, operator, relation, terms, inputs=()):
    return {"mode": "reduce", "operator": operator, "output": output,
            "relation": relation, "terms": copy.deepcopy(list(terms)), "inputs": list(inputs)}


def dependencies(clauses):
    """Only relation-bearing clauses create component/source dependencies."""
    return {clause["relation"] for clause in clauses if "relation" in clause}
