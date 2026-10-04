"""Create a small, self-contained manual-import ZIP after verification/build."""
from pathlib import Path
import hashlib
import json
import zipfile

HERE = Path(__file__).resolve().parent
verification = json.loads((HERE / 'evidence/verification.json').read_text())
resources = json.loads((HERE / 'evidence/resources.json').read_text())
assert verification['status'] == 'PASS'
for variant in ['serial_lfsr', 'serial_engine_only']:
    path = HERE / resources[variant]['rtl_file']
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == verification['variants'][variant]['rtl_sha256']
    assert digest == resources[variant]['rtl_sha256']

files = [HERE / name for name in ['README.md', 'gqh_serial_top.v',
    'gqh_serial_engine_only_top.v', '19_tang_nano_20k.cst', 'tang_nano_20k.sdc',
    'options.tcl', 'evidence/verification.json', 'evidence/verification.log',
    'evidence/resources.json']]
for variant in ['serial_lfsr', 'serial_engine_only']:
    files.extend((HERE / 'evidence' / variant).iterdir())
out = HERE / 'gowin_import.zip'
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        if path.is_file():
            archive.write(path, 'serial_adder_approach/' + str(path.relative_to(HERE)))
print(out)
