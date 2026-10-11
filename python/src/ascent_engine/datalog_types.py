# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Static column constraints for typed Datalog, not relational evaluation."""
import ast


def infer_schema(facts, rules, queries):
    from .datalog import atom, conjunction

    parents, kinds, widths = {}, {}, {}

    def root(key):
        parents.setdefault(key, key)
        if parents[key] != key:
            parents[key] = root(parents[key])
        return parents[key]

    def constrain(key, kind):
        key = root(key)
        if key in kinds and kinds[key] != kind:
            raise ValueError("incompatible Datalog column types")
        kinds[key] = kind

    def unify(left, right):
        left, right = root(left), root(right)
        if left == right:
            return
        if right in kinds:
            constrain(left, kinds[right])
        parents[right] = left

    def scalar(value):
        try:
            return {str: "symbol", int: "integer", bool: "boolean"}[type(value)]
        except KeyError:
            raise ValueError("unsupported typed Datalog scalar") from None

    def declare(name, width):
        if name in widths and widths[name] != width:
            raise ValueError("inconsistent relation arity: " + name)
        widths[name] = width
        for column in range(width):
            root(("column", name, column))

    def operand(term, scope, key):
        if "var" in term:
            unify(key, ("variable", scope, term["var"]))
        else:
            constrain(key, scalar(term["const"]))

    def relation(clause, scope):
        declare(clause["relation"], len(clause["terms"]))
        for column, term in enumerate(clause["terms"]):
            operand(term, scope, ("column", clause["relation"], column))

    for name, rows in facts.items():
        for row in rows:
            declare(name, len(row))
            for column, value in enumerate(row):
                constrain(("column", name, column), scalar(value))
    for scope, statement in enumerate(ast.parse(rules).body):
        node = statement.value if isinstance(statement, ast.Expr) else None
        if not isinstance(node, ast.Compare) or len(node.ops) != 1 or not isinstance(node.ops[0], ast.LtE):
            raise ValueError("expected one relational rule")
        relation(atom(node.left, True), scope)
        for number, clause in enumerate(conjunction(node.comparators[0], True)):
            if "relation" in clause:
                relation(clause, scope)
            mode = clause.get("mode")
            if mode is None:
                continue
            operator = clause["operator"]
            slots = []
            for index, term in enumerate(clause["terms"]):
                key = ("operand", scope, number, index)
                operand(term, scope, key)
                slots.append(key)
            if mode == "where" or (mode == "compute" and operator == "+"):
                for key in slots:
                    constrain(key, "integer")
            if mode in ("compute", "reduce"):
                output = ("variable", scope, clause["output"])
                if mode == "compute" and operator == "identity" and len(slots) == 1:
                    unify(output, slots[0])
                else:
                    constrain(output, "integer")
                if mode == "reduce" and operator != "count":
                    for variable in clause["inputs"]:
                        constrain(("variable", scope, variable), "integer")
    for expression in queries.values():
        clause = atom(ast.parse(expression, mode="eval").body)
        declare(clause["relation"], len(clause["terms"]))
    return {name: [kinds.get(root(("column", name, column)), "symbol")
                   for column in range(width)] for name, width in widths.items()}
