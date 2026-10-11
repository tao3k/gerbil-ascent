# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Lossless symbol transport within the native wire's identifier length bound."""
import copy
import hashlib


def encode(program):
    lowered, symbols = copy.deepcopy(program), {}

    def token(value):
        key = "s" + hashlib.sha256(value.encode("utf-8")).hexdigest()
        if key in symbols and symbols[key] != value:
            raise ValueError("Datalog symbol digest collision")
        symbols[key] = value
        return key

    for relation in lowered["relations"]:
        relation["rows"] = [[token(value) if isinstance(value, str) else value
                             for value in row] for row in relation["rows"]]
    for rule in lowered["rules"]:
        for clause in rule["head"] + rule["body"]:
            for term in clause["terms"]:
                if isinstance(term.get("const"), str):
                    term["const"] = token(term["const"])
    return lowered, symbols
