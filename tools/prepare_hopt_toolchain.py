#!/usr/bin/env python3
"""Recreate the isolated H2-H5 HDL verification toolchain without system installs.

Use --from-downloads for an offline reconstruction from preserved packages.
--download explicitly enables network retrieval. Requires an existing Linux
GCC/G++, make, dpkg-deb, Python 3.12+, and a compatible x86_64 Ubuntu runtime.
This does not modify the OCaml switch or install packages globally.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
from urllib.request import urlopen


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(args):
    root = args.root.resolve()
    if any(character.isspace() for character in str(root)):
        raise ValueError('Toolchain root must contain no whitespace (Yosys Makefile paths)')
    metadata = json.loads(args.manifest.read_text())
    root.mkdir(parents=True, exist_ok=False)
    downloads = root / 'downloads'
    downloads.mkdir()
    packages = root / 'usr-root'
    packages.mkdir()
    binaries = root / 'bin'
    binaries.mkdir()
    for name, item in metadata['artifacts'].items():
        target = downloads / name
        if args.from_downloads:
            shutil.copyfile(args.from_downloads / name, target)
        else:
            with urlopen(item['url'], timeout=60) as response, target.open('wb') as output:
                shutil.copyfileobj(response, output)
        if sha256(target) != item['sha256']:
            raise ValueError(f'Download SHA-256 mismatch: {name}')
        if name.endswith('.deb'):
            subprocess.run(['dpkg-deb', '-x', str(target), str(packages)], check=True)
    with tarfile.open(downloads / 'yosys-0.33.tar.gz') as archive:
        archive.extractall(root, filter='data')
    yosys = root / 'yosys-yosys-0.33'
    if (yosys / '.gitcommit').read_text().strip() != '2584903a060':
        raise ValueError('Yosys archive identity differs from the pinned 0.33 tag')
    for name in ['bison', 'flex', 'vvp']:
        (binaries / name).symlink_to(packages / 'usr/bin' / name)
    (binaries / 'iverilog').write_text(
        '#!/bin/sh\nexec ' + shlex.quote(str(packages / 'usr/bin/iverilog')) +
        ' -B ' + shlex.quote(str(packages / 'usr/lib/x86_64-linux-gnu/ivl')) + ' "$@"\n')
    (binaries / 'iverilog').chmod(0o755)
    config = '\n'.join([
        'CONFIG := gcc', 'ENABLE_TCL := 0', 'ENABLE_READLINE := 0',
        'ENABLE_ZLIB := 0', 'ENABLE_ABC := 0', f'PREFIX := {root}/install',
        'CXXFLAGS += -include cstdint',
        f'CXXFLAGS += -I{packages}/usr/include/x86_64-linux-gnu',
        f'LDFLAGS += -L{packages}/usr/lib/x86_64-linux-gnu']) + '\n'
    (yosys / 'Makefile.conf').write_text(config)
    environment = os.environ.copy()
    environment['PATH'] = str(binaries) + ':' + environment['PATH']
    environment['BISON_PKGDATADIR'] = str(packages / 'usr/share/bison')
    with (root / 'yosys-build.log').open('w') as log:
        subprocess.run(['make', '-C', str(yosys), '-j', str(args.jobs)],
                       check=True, env=environment, stdout=log, stderr=subprocess.STDOUT)
    (root / 'env.sh').write_text(
        f'export PATH={shlex.quote(str(binaries))}:{shlex.quote(str(yosys))}:$PATH\n'
        f'export BISON_PKGDATADIR={shlex.quote(str(packages / "usr/share/bison"))}\n'
        f'export PYTHONPATH={shlex.quote(str(packages / "usr/lib/python3/dist-packages"))}'
        '${PYTHONPATH:+:$PYTHONPATH}\n')
    evidence = {'artifacts': metadata['artifacts'], 'yosys_build_config': config,
                'yosys_version': subprocess.check_output([str(yosys / 'yosys'), '-V'], text=True).strip(),
                'root': str(root)}
    (root / 'manifest.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'Prepared {root}; activate with: source {root}/env.sh')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True, help='Fresh isolated directory')
    parser.add_argument('--manifest', type=Path,
                        default=Path(__file__).with_name('hopt-toolchain.json'))
    parser.add_argument('--jobs', type=int, default=4)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--from-downloads', type=Path)
    source.add_argument('--download', action='store_true')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    prepare(args)


if __name__ == '__main__':
    main()
