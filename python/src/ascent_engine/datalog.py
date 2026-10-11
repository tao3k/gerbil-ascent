# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Translate relational Datalog text; ASCENT owns all inference.

No eval, Python fixed point, or fallback. Demand slicing selects complete rule
dependencies, not favorable facts. Unsupported syntax on that slice is an error.
"""
import ast
import json
from .operators import where, compute, reduce


def symbol(value):
    if type(value) not in (str, int):
        raise ValueError("audit cells must be strings or integers")
    return json.dumps(value, ensure_ascii=True)


def term(value, typed=False):
    if isinstance(value, ast.Name) and value.id[0].isupper():
        return {"var": value.id}
    if isinstance(value, ast.Constant) and type(value.value) in (str, int, bool):
        return {"const": value.value if typed else symbol(value.value)}
    if (isinstance(value, ast.UnaryOp) and isinstance(value.op, ast.USub)
            and isinstance(value.operand, ast.Constant) and type(value.operand.value) is int):
        number = -value.operand.value
        return {"const": number if typed else symbol(number)}
    raise ValueError("unsupported audit term")


def atom(node, typed=False):
    absent = isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Invert)
    if absent:
        node = node.operand
    if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name) or node.keywords:
        raise ValueError("only relational atoms are supported")
    terms = [term(value, typed) for value in node.args]
    if not terms:
        raise ValueError("zero-column relations are unsupported")
    return {"relation": node.func.id, "not": absent, "terms": terms}


def conjunction(node, typed=False):
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitAnd):
        return conjunction(node.left, typed) + conjunction(node.right, typed)
    if typed:
        if isinstance(node, ast.Compare) and len(node.ops) == 1 and isinstance(node.ops[0], ast.Lt):
            return [where("<", term(node.left, True), term(node.comparators[0], True))]
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and not node.keywords:
            if node.func.id == "where" and node.args and isinstance(node.args[0], ast.Constant):
                return [where(node.args[0].value, *[term(v, True) for v in node.args[1:]])]
            if node.func.id == "bind" and len(node.args) == 2:
                output = term(node.args[0], True)
                if "var" not in output:
                    raise ValueError("binding output must be a variable")
                value = node.args[1]
                if isinstance(value, ast.BinOp) and isinstance(value.op, ast.Add):
                    return [compute(output["var"], "+", term(value.left, True), term(value.right, True))]
                return [compute(output["var"], "identity", term(value, True))]
            if node.func.id == "reduce" and len(node.args) >= 3:
                output, operator = term(node.args[0], True), node.args[1]
                relation = atom(node.args[2], True)
                inputs = [term(v, True) for v in node.args[3:]]
                if ("var" not in output or not isinstance(operator, ast.Constant)
                        or relation["not"] or any("var" not in v for v in inputs)):
                    raise ValueError("invalid reduction")
                return [reduce(output["var"], operator.value, relation["relation"], relation["terms"],
                               [v["var"] for v in inputs])]
    return [atom(node, typed)]


def check_bindings(head, body):
    bound = set()
    for clause in body:
        used = {t["var"] for t in clause["terms"] if "var" in t}
        mode = clause.get("mode")
        if mode == "reduce":
            if not set(clause["inputs"]) <= used:
                raise ValueError("reducer inputs absent from relation")
        elif clause.get("not") or mode in ("where", "compute"):
            if not used <= bound:
                raise ValueError("unsafe rule variables")
        else:
            bound.update(used)
        if mode in ("compute", "reduce"):
            if clause["output"] in bound:
                raise ValueError("operator output already bound")
            bound.add(clause["output"])
    if not {t["var"] for t in head["terms"] if "var" in t} <= bound:
        raise ValueError("unsafe rule variables")


def compile_program(facts, rule_text, queries, *, schema=None):
    """Compile equality joins, recursion and stratified relational negation.

    JSON-tagged scalar symbols preserve the distinction between integer 1 and
    string "1". An explicit typed schema enables native checked operators.
    """
    if schema == "infer":
        from .datalog_types import infer_schema
        schema = infer_schema(facts, rule_text, queries)
    definitions = {}
    for statement in ast.parse(rule_text).body:
        node = statement.value if isinstance(statement, ast.Expr) else None
        if not isinstance(node, ast.Compare) or len(node.ops) != 1 or not isinstance(node.ops[0], ast.LtE):
            raise ValueError("expected one relational rule")
        head = atom(node.left, schema is not None)
        if head["not"]:
            raise ValueError("negative rule head")
        definitions.setdefault(head["relation"], []).append((head, node.comparators[0]))
    wanted = {}
    for label, expression in queries.items():
        query = atom(ast.parse(expression, mode="eval").body)
        variables = [term.get("var") for term in query["terms"]]
        if query["not"] or None in variables or len(set(variables)) != len(variables):
            raise ValueError("queries must request all distinct relation columns")
        wanted[label] = query
    arities, rules, pending, visited = {}, [], list(wanted.values()), set()
    while pending:
        current = pending.pop()
        name, width = current["relation"], len(current["terms"])
        if name in arities and arities[name] != width:
            raise ValueError("inconsistent relation arity: " + name)
        arities[name] = width
        if name in visited:
            continue
        visited.add(name)
        if name in definitions:
            if facts.get(name):
                raise ValueError("derived relation cannot contain source facts: " + name)
            for head, body_node in definitions[name]:
                body = conjunction(body_node, schema is not None)
                check_bindings(head, body)
                rules.append({"head": [head], "body": body})
                pending.extend(a for a in [head, *body] if "relation" in a)
        elif name not in facts:
            raise ValueError("undeclared source relation: " + name)
    relations = []
    for name, width in sorted(arities.items()):
        rows = facts.get(name, []) if name not in definitions else []
        if any(len(row) != width for row in rows):
            raise ValueError("source row arity mismatch: " + name)
        columns = ["symbol"] * width if schema is None else schema.get(name, [])
        if len(columns) != width or any(c not in ("symbol", "integer", "boolean") for c in columns):
            raise ValueError("complete typed relation schema required: " + name)
        relations.append({"name": name, "source": name not in definitions,
                          "columns": [{"kind": kind} for kind in columns],
                          "rows": ([list(row) for row in rows] if schema is not None else
                                   sorted({tuple(symbol(v) for v in row) for row in rows}))})
    return {"relations": relations, "rules": rules,
            "queries": list(dict.fromkeys(a["relation"] for a in wanted.values()))}, wanted


def evaluate(engine, facts, rules, queries, *, schema=None):
    from ascent_engine.derivations import EvidenceChain
    from .datalog_symbols import encode

    program, wanted = compile_program(facts, rules, queries, schema=schema)
    program, symbols = encode(program)
    with EvidenceChain(engine, [r for r in program["relations"] if r["source"]]) as chain:
        result = chain.query(program)
        reused = chain.query(program)
    if result["result"] != reused["result"] or not result["result"].get("complete"):
        raise ValueError("ASCENT audit did not return a stable complete result")
    rows = result["result"]["relations"]
    def decode(value):
        if isinstance(value, str):
            if value not in symbols:
                raise ValueError("unknown native Datalog symbol")
            value = symbols[value]
        return json.loads(value) if schema is None else value
    answers = {label: sorted((tuple(decode(v) for v in row) for row in rows[a["relation"]]),
                            key=lambda row: tuple((type(v).__name__, v) for v in row))
               for label, a in wanted.items()}
    return answers, {"sourceIdentity": result["sourceIdentity"],
                     "pathIdentity": result["pathIdentity"],
                     "freshComponents": len(result["freshComponents"]),
                     "repeatReusedComponents": len(reused["reusedComponents"])}
