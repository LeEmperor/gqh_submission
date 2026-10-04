"""Optional local Gowin measurement; manual IDE import needs only RTL/CST/SDC."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
env = dict(os.environ, QT_QPA_PLATFORM='minimal')
env.setdefault('GOWIN_HOME', '/home/wayne/tools/gowin/1.9.11.03-edu')
subprocess.run(['python3', str(HERE / 'prepare.py')], check=True)
for variant, rtl in [('serial_lfsr', 'gqh_serial_top.v'),
                     ('serial_engine_only', 'gqh_serial_engine_only_top.v')]:
    folder = HERE / 'builds' / variant
    evidence = HERE / 'evidence' / variant
    evidence.mkdir(parents=True, exist_ok=True)
    with (evidence / 'build.log').open('w') as log:
        result = subprocess.run(['gw_sh', 'build.tcl'], cwd=folder, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
    result.check_returncode()
    assert 'SERIAL_BUILD_COMPLETED' in (evidence / 'build.log').read_text()
    report = folder / 'impl/pnr/gqh_serial.rpt.txt'
    assert report.exists(), report
    shutil.copy2(report, evidence / 'place-route.rpt.txt')
    for name in ['gqh_serial.tr.html', 'gqh_serial_tr_content.html', 'gqh_serial_tr_cata.html']:
        source = folder / 'impl/pnr' / name
        if source.exists(): shutil.copy2(source, evidence / name)
    for source in (folder / 'impl/gwsynthesis').glob('*'):
        if source.suffix in ['.html', '.xml']:
            shutil.copy2(source, evidence / source.name)
    shutil.copy2(folder / 'resolved-settings.tcl', evidence / 'resolved-settings.tcl')
    image = folder / 'impl/pnr/gqh_serial.fs'
    assert image.exists(), image
    shutil.copy2(image, evidence / 'gqh_serial.fs')
    manifest = {name: hashlib.sha256(path.read_bytes()).hexdigest()
                for name, path in [('rtl', HERE / rtl), ('bitstream', image),
                                   ('cst', HERE / '19_tang_nano_20k.cst'),
                                   ('sdc', HERE / 'tang_nano_20k.sdc'),
                                   ('options', HERE / 'options.tcl')]}
    manifest['rtl_file'] = rtl
    (evidence / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(variant + ':', flush=True)
    for line in report.read_text().splitlines():
        if any(key in line for key in ['Logic ', '--LUT,ALU', 'Register ', 'BSRAM ', 'SSRAM ']):
            print(line, flush=True)
