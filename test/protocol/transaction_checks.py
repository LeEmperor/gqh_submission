"""G1 production-controller verification; expected actions use F's local oracle."""
from pathlib import Path
import collections
import hashlib
import json
import random
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ORACLE = HERE.parent / 'engine' / 'oracle'
sys.path.insert(0, str(ORACLE))
from model import ReferenceModel, decode_request, encode_request, ITEM_A, ITEM_B


def run(args):
    subprocess.run([str(a) for a in args], check=True)


def packets(path):
    model = ReferenceModel()
    rows = []
    supplied = 0
    coverage = collections.Counter()
    def add(request, expected=None):
        index, id1, p1, id2, p2 = decode_request(request)
        coverage['sessions'] += index == 0
        coverage['warmup_packets' if index < 16 else 'steady_packets'] += 1
        coverage['swapped_packets'] += id1 == ITEM_B
        coverage['warmup_swaps'] += index < 16 and id1 == ITEM_B
        coverage['wraps'] += index % 16 == 15
        for item, price in [(id1,p1),(id2,p2)]:
            coverage['zero_prices'] += price == 0
            coverage['maximum_prices'] += price == 65535
            if index >= 16:
                window = model._windows[item]  # Coverage only; never expected arithmetic.
                old_sum = sum(window)
                new_sum = sum(window[1:] + [price])
                coverage['previous_equals_old_average'] += window[-1] == old_sum // 16
                coverage['price_equals_new_average'] += price == new_sum // 16
                coverage['truncation'] += old_sum % 16 != 0 or new_sum % 16 != 0
        previous_actions = dict(model._actions)
        response = model.respond(request)
        for item, action in [(id1,response[3]),(id2,response[5])]:
            coverage[f'action_{action}'] += 1
            coverage[f'held_{action}'] += index >= 16 and action == previous_actions[item]
        if expected is not None:
            assert response == expected
        fields = decode_request(request)
        rows.append(' '.join(map(str, (*fields, response[3], response[5]))))
    for folder in sorted((ORACLE / 'fixtures').iterdir()):
        for line in (folder / 'fixture.jsonl').read_text().splitlines():
            r = json.loads(line)
            add(bytes.fromhex(r['request_hex']), bytes.fromhex(r['expected_response_hex']))
            supplied += 1
    assert supplied == 800
    # Same seeds, lengths, ranges, swapping and directed prices as F's extra
    # deterministic/random vectors. Only packet stimulus is reused; no test
    # adapter dispatches updates, clears state or advances a hardware pointer.
    for seed in [0, 1, 42, 0x57214720, 0xFFFF, 20261003]:
        rng = random.Random(seed)
        for index in range(513):
            bound = 65536 if seed % 2 else 128
            a, b = rng.randrange(bound), rng.randrange(bound)
            add(encode_request(index, ITEM_B, b, ITEM_A, a) if rng.randrange(2)
                else encode_request(index, ITEM_A, a, ITEM_B, b))
    directed = [
        [(100, 200)]*16 + [(102,198),(103,197),(99,201),(98,202)]*24,
        [(65535, 0)]*16 + [(65535,0),(0,65535),(1,65534),(65534,1)]*24,
        [(100,100)]*15 + [(115,85)] + [(101,99),(100,100),(100,100)]*32,
    ]
    for prices in directed:
        for index, (a, b) in enumerate(prices):
            add(encode_request(index, ITEM_B, b, ITEM_A, a) if index % 2 == 0
                else encode_request(index, ITEM_A, a, ITEM_B, b))
    for required in ['warmup_swaps','wraps','maximum_prices','zero_prices',
                     'held_1','held_2','previous_equals_old_average',
                     'price_equals_new_average','truncation']:
        assert coverage[required] > 0, required
    path.write_text('\n'.join(rows)+'\n')
    return dict(records=len(rows), supplied=800, additional=len(rows)-800,
                trace_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                packet_coverage=dict(sorted(coverage.items())),
                real_reset_offsets=30, post_reset_replay_records=1050,
                rolling_reset_prepopulate_records=525,
                total_real_completed_records=len(rows)+1575)


def main():
    exe = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]) if len(sys.argv) == 3 else None
    if output:
        output.mkdir(parents=True, exist_ok=True)
    provenance = json.loads((ORACLE / 'SOURCE.json').read_text())
    for entry in provenance['files']:
        if entry['unchanged']:
            assert hashlib.sha256((ORACLE / entry['local_path']).read_bytes()).hexdigest() == entry['upstream_sha256']
    with tempfile.TemporaryDirectory(prefix='phase-g1-') as directory:
        tmp = Path(directory)
        trace = tmp / 'packets.txt'
        summary = packets(trace)
        run([exe, 'mocks'])
        run([exe, 'replay', trace])
        run([exe, 'bytes', trace])
        for kind, top in [('controller','gqh_transaction_controller'),
                          ('payload','gqh_transaction_test'),('byte','gqh_byte_test')]:
            rtl = tmp / f'{top}.v'
            run([exe, 'emit', kind, rtl])
            data = rtl.read_bytes()
            run([exe, 'emit', kind, rtl])
            assert rtl.read_bytes() == data, 'nondeterministic RTL'
            assert b'initial' not in data
            net = tmp / f'{top}.json'
            run(['yosys', '-Q', '-q', '-p',
                 f'read_verilog {rtl}; hierarchy -check -top {top}; proc; opt_clean; check -assert; write_json {net}'])
            run(['iverilog','-g2012','-s',top,'-o',tmp / kind,rtl])
            if kind == 'controller':
                ports = json.loads(net.read_text())['modules'][top]['ports']
                inputs = {'clock':1,'reset':1,'request_valid':1,'update_ready':1,
                          'result_valid':1,'action':2,'response_ready':1,'response_done':1,
                          'request$index':16,'request$slot1_id':8,'request$slot1_price':16,
                          'request$slot2_id':8,'request$slot2_price':16}
                outputs = {'request_ready':1,'receive_enable':1,'update_valid':1,
                           'result_ready':1,'session_clear':1,'response_valid':1,
                           'update$item_select':1,'update$price':16,
                           'update$window_position':4,'update$warmup':1,
                           'response$index':16,'response$slot1_id':8,'response$slot2_id':8,
                           'response$slot1_action':2,'response$slot2_action':2}
                assert {k:len(v['bits']) for k,v in ports.items()} == inputs | outputs
                assert {k for k,v in ports.items() if v['direction']=='output'} == set(outputs)
            summary[top+'_sha256'] = hashlib.sha256(data).hexdigest()
            if output:
                (output / rtl.name).write_bytes(data)
        print(json.dumps(summary,indent=2),flush=True)
        if output:
            (output / 'coverage.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('PASS G1: mocks, independent oracle/real engine, byte composition, deterministic RTL, Yosys and Icarus elaboration')

if __name__ == '__main__':
    main()
