#!/usr/bin/env python3
"""Build droid-scx.ko for a GKI family with its pinned DDK image."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = json.loads((ROOT / 'build/gki-targets.json').read_text())

def source_hashes(target, source_key='scx_source'):
    paths = [ROOT/'Makefile', ROOT/'src/gki-target.h']
    paths += [p for directory in (ROOT/target[source_key], ROOT/'vendor/kallrecon')
              for p in directory.rglob('*') if p.is_file()
              and not {'.git', '.DS_Store', '__pycache__'}.intersection(p.parts)]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=TARGETS)
    parser.add_argument('make_args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    target = TARGETS[args.target]
    key = 'scx_source'
    if not (ROOT / target[key] / 'main.c').is_file():
        parser.error(f'missing source set: {target[key]}')
    outname, ko, make = target['kmi']+'-scx', 'droid-scx.ko', ['TARGET=scx', f'SCX_DIR={target[key]}']
    cmd = ['docker', 'run', '--rm', '--platform', 'linux/amd64',
           '-v', f'{ROOT}:/module', '-w', '/module', target['image'],
           'make', *make,
           f'GKI_ANDROID={target["kmi"].split("-")[0]}', f'GKI_VERSION={args.target}',
           f'OUT=/module/out/gki/{outname}', *args.make_args]
    out = ROOT/'out/gki'/outname
    record = out/'build.json'
    record.unlink(missing_ok=True)
    before = source_hashes(target, key)
    subprocess.run(cmd, check=True)
    if before != source_hashes(target, key):
        raise RuntimeError('build sources changed during compilation')
    record.write_text(json.dumps(dict(target=target, sources=before,
        module_sha256=hashlib.sha256((out/ko).read_bytes()).hexdigest()),
        indent=2)+'\n')
