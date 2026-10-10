# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Link the compiler-derived ASCENT library closure for C ABI consumers.

Run the normal Gerbil package build first. This links one engine library;
it neither builds a model scenario nor discovers or runs Scheme tests.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
from concurrent.futures import ThreadPoolExecutor

def run(arguments, root, capture=False):
    result = subprocess.run(list(map(str, arguments)), cwd=root,
                            text=True, capture_output=capture)
    if result.returncode:
        if capture and result.stderr: print(result.stderr, flush=True)
        result.check_returncode()
    return result.stdout if capture else ''

def define(path, key):
    match = re.search(r'^#define '+re.escape(key)+r' ([A-Za-z0-9_]+)$', path.read_text(), re.M)
    if not match: raise ValueError('generated linker omitted '+key)
    return match[1]

def build(root, output):
    root = root.resolve(); output = output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    if platform.system() == 'Darwin':
        os.environ['MACOSX_DEPLOYMENT_TARGET'] = platform.mac_ver()[0].split('.')[0]+'.0'
    home = Path(run(['gxi','-e','(displayln (gerbil-home))'],root,True).strip())
    gsc = home/'bin/gsc'
    # Compiler and runtime must come from this same release.
    os.environ['GAMBOPT'] = f'~~={home},~~bin={home / "bin"},~~lib={home / "lib"}'
    expression = '''(let* ((ctx (import-module (string->symbol ":gerbil-ascent/interface/c-api")))
                          (deps (gxc#find-runtime-module-deps ctx)))
     (for-each (lambda (dep) (displayln "CLOSURE\\t" (expander-context-id dep) "\\t" (gxc#find-static-module-file dep))) deps)
     (displayln "ROOT\\t" (gxc#find-static-module-file ctx)))'''
    raw = run(['gxi','-e','(import :gerbil/compiler/driver :gerbil/expander)','-e',expression],root,True)
    sdk=[]; user=[]; entry=None
    for line in raw.splitlines():
        if line.startswith('ROOT\t'): entry=Path(line.split('\t',1)[1])
        elif line.startswith('CLOSURE\t'):
            _, module, path = line.split('\t'); path=Path(path)
            if module.startswith(('gerbil/','std/')) and not module.startswith('gerbil/core'):
                sdk.append(path)
            elif not module.startswith('gerbil/') and path.is_file() and path.stat().st_size:
                user.append(path)
    if entry is None: raise ValueError('compiler did not report the scheme root')
    sdk=list(dict.fromkeys(sdk)); user=list(dict.fromkeys(user))
    directory=output.parent; link=directory/'ascent_.c'; link_object=link.with_suffix('.o')
    runtime=directory/'runtime.o'
    print(f'ASCENT-C-ABI-LINK modules={len(sdk)+len(user)+1}',flush=True)
    run([gsc,'-target','C','-link','-o',link,*[p.with_suffix('.c') for p in sdk],*user,entry],root)
    run([gsc,'-target','C','-cc-options','-D___LIBRARY','-obj','-o',link_object,link],root)
    run([gsc,'-target','C','-cc-options',
         f'-I{root / "bindings/c"} -D___VERSION={define(link,"___VERSION")} -DASCENT_LINKER={define(link,"___LINKER_ID")}',
         '-obj','-o',runtime,root/'bindings/c/runtime.c'],root)
    sources=list(dict.fromkeys([*user,entry,*sdk]))
    def object_for(source):
        obj=source.with_suffix('.o'); generated=source.with_suffix('.c')
        if not obj.is_file() or generated.stat().st_mtime_ns > obj.stat().st_mtime_ns:
            print('ASCENT-C-ABI-OBJECT '+source.name,flush=True)
            run([gsc,'-target','C','-cc-options','-fPIC','-obj','-o',obj,generated],root)
        return obj
    cores=int(os.environ.get('GERBIL_BUILD_CORES',str(os.cpu_count() or 1)))
    if cores < 1: raise ValueError('GERBIL_BUILD_CORES must be positive')
    with ThreadPoolExecutor(max_workers=min(cores,len(sources),64)) as workers:
        objects=list(workers.map(object_for,sources))
    flags=shlex.split((home/'lib/libgerbil.ldd').read_text().strip().strip('()'))
    shared=['-dynamiclib','-Wl,-undefined,dynamic_lookup','-Wl,-no_compact_unwind',
            '-mmacosx-version-min='+os.environ['MACOSX_DEPLOYMENT_TARGET']] if platform.system()=='Darwin' else ['-shared']
    candidate=output.with_name(output.name+'.pending')
    run(['cc',*shared,'-o',candidate,*objects,link_object,runtime,
         '-L',home/'lib','-lgambit',*flags,'-Wl,-rpath,'+str(home/'lib')],root)
    candidate.replace(output)
    manifest={'schema':'ascent.c-abi-build.v1','abi':1,'sdk':str(home),
              'librarySha256':hashlib.sha256(output.read_bytes()).hexdigest(),
              'runtimeSourceSha256':hashlib.sha256((root/'bindings/c/runtime.c').read_bytes()).hexdigest(),
              'headerSha256':hashlib.sha256((root/'bindings/c/ascent.h').read_bytes()).hexdigest(),
              'closureSources':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
              'closureObjects':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in objects}}
    output.with_suffix(output.suffix+'.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('ASCENT-C-ABI-BUILD-OK '+str(output),flush=True)

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--root',type=Path,default=Path.cwd())
    parser.add_argument('--output',type=Path,required=True); args=parser.parse_args()
    build(args.root,args.output)

if __name__=='__main__':main()
