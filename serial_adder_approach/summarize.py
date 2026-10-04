"""Validate saved build identities and summarize Gowin's actual report rows."""
from pathlib import Path
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
summary = {}
for variant in ['serial_lfsr', 'serial_engine_only']:
    evidence = HERE / 'evidence' / variant
    manifest = json.loads((evidence / 'manifest.json').read_text())
    for key, path in [('rtl', HERE / manifest['rtl_file']),
                      ('bitstream', evidence / 'gqh_serial.fs'),
                      ('cst', HERE / '19_tang_nano_20k.cst'),
                      ('sdc', HERE / 'tang_nano_20k.sdc'),
                      ('options', HERE / 'options.tcl')]:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest[key], path
    report = (evidence / 'place-route.rpt.txt').read_text()
    timing = (evidence / 'gqh_serial_tr_content.html').read_text()
    row = re.search(r'(\d+)\((\d+) LUT, (\d+) ALU, (\d+) ROM16\)', report)
    logic, lut, alu, rom16 = map(int, row.groups())
    assert logic == lut + alu + rom16
    metrics = {'logic': logic, 'lut': lut, 'alu': alu, 'rom16': rom16}
    for label, key in [('Register', 'registers'), ('BSRAM', 'bsram')]:
        metrics[key] = int(re.search(r'^\s*' + label + r'\s*\|\s*(\d+)/', report, re.M)[1])
    for kind in ['Setup', 'Hold']:
        row = re.search(r'<td>' + kind + r'</td>\s*<td>([-.\d]+)</td>\s*<td>(\d+)</td>', timing)
        metrics[kind.lower() + '_violated_endpoints'] = int(row[2])
        assert float(row[1]) == 0 and int(row[2]) == 0, (variant, kind)
    metrics['rtl_file'] = manifest['rtl_file']
    metrics['rtl_sha256'] = manifest['rtl']
    metrics['bitstream_sha256'] = manifest['bitstream']
    metrics['board_validated'] = False
    summary[variant] = metrics
summary['selected'] = min(['serial_lfsr', 'serial_engine_only'],
                          key=lambda v: (summary[v]['logic'], summary[v]['registers']))
(HERE / 'evidence' / 'resources.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
