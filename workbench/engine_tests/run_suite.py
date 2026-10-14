"""Retain a bounded, file-by-file receipt for the complete semantic corpus."""
import argparse
import ast
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import time

def cases(path):
    tree=ast.parse(path.read_text())
    return [f"{path.stem}.{cls.name}.{fn.name}" for cls in tree.body if isinstance(cls,ast.ClassDef)
            for fn in cls.body if isinstance(fn,(ast.FunctionDef,ast.AsyncFunctionDef)) and fn.name.startswith("test_")]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--python",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--validation-tools",type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True,exist_ok=False)
    environment=dict(os.environ,PYTHONDONTWRITEBYTECODE="1",PATH="/usr/bin:/bin",
                     PYTHONPATH=os.pathsep.join(map(str,[root/"workbench/src",root/"workbench/engine_tests"])))
    if args.validation_tools:
        environment["PATH"] = str(args.validation_tools.absolute()) + os.pathsep + environment["PATH"]
    receipts=[]
    for path in sorted((root/"workbench/engine_tests").glob("test_*.py")):
        started=time.monotonic()
        # Resolve the containing directory, not the venv executable symlink:
        # resolving python itself silently selects the base interpreter.
        command=[str(args.python.absolute()),"-m","unittest",path.stem,"-v"]
        try:
            run=subprocess.run(command,env=environment,cwd=root,text=True,capture_output=True,timeout=150)
            stdout,stderr,status=run.stdout,run.stderr,run.returncode
        except subprocess.TimeoutExpired as error:
            stdout,stderr,status=error.stdout or b"",error.stderr or b"","timeout"
            if isinstance(stdout,bytes):stdout=stdout.decode(errors="replace")
            if isinstance(stderr,bytes):stderr=stderr.decode(errors="replace")
        (args.output/f"{path.stem}.stdout").write_text(stdout)
        (args.output/f"{path.stem}.stderr").write_text(stderr)
        observed={name:outcome for name,outcome in re.findall(r"^test_\w+ \(([^)]+)\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)",stderr,re.MULTILINE)}
        declared=cases(path)
        outcomes={name:observed.get(name,"unresolved-import-or-setup" if status!=0 else "unresolved-not-executed") for name in declared}
        receipt=dict(file=str(path.relative_to(root)),source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                     declared_cases=declared,case_outcomes=outcomes,status=status,wall_seconds=time.monotonic()-started,command=command)
        receipts.append(receipt)
        (args.output/"files.json").write_text(json.dumps(receipts,indent=2)+"\n")
        print(path.stem,status,round(receipt["wall_seconds"],2),flush=True)
    if any(receipt["status"]!=0 or any(v!="ok" for v in receipt["case_outcomes"].values()) for receipt in receipts):
        raise SystemExit("Full semantic qualification failed; every file receipt retained")

if __name__=="__main__":main()
