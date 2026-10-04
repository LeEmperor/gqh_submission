"""Self-contained Phase F oracle, Cyclesim and emitted-RTL verification."""
from pathlib import Path
import collections
import hashlib
import json
import random
import struct
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'oracle'))
from model import ReferenceModel, decode_request, encode_request, ITEM_A, ITEM_B


def relation(window):
    """Last price versus floor(sum(direct window)/16), including warm-up."""
    price = window[-1] if window else 0
    average = sum(window) // 16
    return int(price < average), int(price > average)


def relation_name(window):
    below, above = relation(window)
    return "below" if below else "above" if above else "equal"


def run(args):
    subprocess.run([str(a) for a in args], check=True)


class Trace:
    """Test-only packet adapter and edge scoreboard. Arithmetic uses direct windows.

    Public command acceptance drives the scoreboard, while published actions are
    supplied by the unchanged independent packet oracle. No rolling-sum oracle.
    """
    def __init__(self, path):
        self.file = path.open('w')
        self.rng = random.Random(0xF20261003)
        self.ram = [65535 - a for a in range(32)]
        self.state = 0
        self.pending = None
        self.clear_scalars()
        self.edges = 0
        self.counts = collections.Counter()
        self.pointer = 0

    def clear_scalars(self):
        self.windows = [[], []]
        self.held = [0, 0]
        self.output_action = 0

    def noise(self):
        return dict(item=self.rng.randrange(2), price=self.rng.randrange(65536),
                    pos=self.rng.randrange(16), warm=self.rng.randrange(2))

    def outputs(self, reset, clear):
        return [int(self.state == 0 and not reset and not clear),
                int(self.state == 5 and not reset), self.output_action]

    def step(self, reset=0, clear=0, valid=0, ready=0, item=0, price=0,
             pos=0, warm=0, answer=0):
        inputs = [reset, clear, valid, ready, item, price, pos, warm]
        before = self.outputs(reset, clear)
        commit = int(self.state == 4 and not reset)
        if reset:
            self.counts[f'reset_state_{self.state}'] += 1
            self.clear_scalars()
            self.state = 0
            self.pending = None
        elif self.state == 0:
            if clear:
                self.counts['session_clear'] += 1
                self.counts['clear_valid_collision'] += bool(valid)
                self.clear_scalars()
            elif valid:
                self.pending = (item, price, pos, warm, answer)
                self.state = 1
                self.counts['accepted'] += 1
        elif self.state == 1:
            self.state = 3 if self.pending[3] else 2
        elif self.state == 2:
            self.state = 3
        elif self.state == 3:
            self.state = 4
        elif self.state == 4:
            item, price, pos, warm, answer = self.pending
            old = self.windows[item]
            if warm:
                assert len(old) < 16
                window = old + [price]
            else:
                assert len(old) == 16
                old_average = sum(old) // 16
                new_average = sum(old[1:] + [price]) // 16
                self.counts['previous_equals_old_average'] += old[-1] == old_average
                self.counts['price_equals_new_average'] += price == new_average
                self.counts['truncated_average'] += bool(sum(old) % 16 or sum(old[1:] + [price]) % 16)
                self.counts[f'held_{answer}'] += answer == self.held[item]
                window = old[1:] + [price]
            before_relation, after_relation = relation_name(old), relation_name(window)
            self.counts[f'relation_{after_relation}'] += 1
            self.counts[f'transition_{before_relation}_{after_relation}'] += 1
            if warm and len(window) == 16:
                self.counts[f'warmup_final_{after_relation}'] += 1
            if not warm and pos == 0:
                self.counts[f'scored_wrap_previous_{before_relation}'] += 1
            self.windows[item] = window
            self.held[item] = answer
            self.output_action = answer
            self.ram[item * 16 + pos] = price
            self.state = 5
            self.counts['warmup' if warm else 'steady'] += 1
            self.counts[f'action_{answer}'] += 1
            self.counts['maximum_sum'] += sum(window) == 1048560
            self.counts['zero_sum'] += sum(window) == 0
        elif ready:
            self.state = 0
            self.counts['results_consumed'] += 1
        else:
            self.counts['result_stall_edges'] += 1
        scalar = [sum(w) for w in self.windows]
        scalar += [flag for w in self.windows for flag in relation(w)] + self.held
        after = self.outputs(reset, clear)
        self.file.write(' '.join(map(str, inputs + before + after + scalar + self.ram + [commit])) + '\n')
        self.edges += 1

    def command(self, item, price, pos, warm, answer, stall=None):
        assert self.state == 0
        for _ in range(self.rng.randrange(3)):
            self.step(**self.noise(), ready=self.rng.randrange(2))
        self.step(valid=1, ready=self.rng.randrange(2), item=item, price=price,
                  pos=pos, warm=warm, answer=answer)
        assert self.state == 1
        # Change *every* captured field, and offer busy commands. Early ready
        # must not cause a result to be consumed at its publication edge.
        noise = dict(item=1-item, price=price ^ 65535, pos=pos ^ 15, warm=1-warm)
        latency = 0
        # Explicit expected stages: synchronous read, optional subtract, add,
        # commit. Busy clear is illegal and must not disturb the accepted work.
        stages = [3, 4, 5] if warm else [2, 3, 4, 5]
        for expected_stage in stages:
            self.step(valid=1, ready=1, clear=1, **noise)
            latency += 1
            assert self.state == expected_stage
        assert latency == (3 if warm else 4)
        self.counts[f'latency_{"warm" if warm else "steady"}_{latency}'] += 1
        for _ in range(self.rng.randrange(12) if stall is None else stall):
            self.step(valid=1, ready=0, **self.noise())
        self.step(valid=1, ready=1, **noise)
        assert self.state == 0

    def packet(self, request, response, oracle_windows):
        index, id1, price1, id2, price2 = decode_request(request)
        if index == 0:
            self.pointer = 0
            # Clear wins when valid is simultaneously asserted: no acceptance.
            self.step(clear=1, valid=1, ready=1, **self.noise())
            self.step()
        assert self.pointer == index % 16
        for item_id, price, answer in [(id1, price1, response[3]), (id2, price2, response[5])]:
            item = int(item_id == ITEM_B)
            previous_relation = relation_name(self.windows[item])
            self.command(item, price, self.pointer, int(index < 16), answer)
            if index == 16:
                self.counts[f'first_scored_{previous_relation}_{relation_name(self.windows[item])}'] += 1
            # Tie direct-window scalar/flag expectations to the unchanged oracle,
            # independently of DUT arithmetic and physical circular RAM order.
            assert self.windows[item] == oracle_windows[item_id]
        self.pointer = (self.pointer + 1) % 16
        self.counts['packets'] += 1
        self.counts['warmup_swaps'] += index < 16 and id1 == ITEM_B
        self.counts['wraps'] += self.pointer == 0


def build_trace(path):
    t = Trace(path)
    t.step(reset=1, clear=1, valid=1, ready=1)
    t.step(reset=1, valid=1)
    t.step()
    model = ReferenceModel()
    supplied = 0
    for folder in sorted((HERE / 'oracle/fixtures').iterdir()):
        for line in (folder / 'fixture.jsonl').read_text().splitlines():
            record = json.loads(line)
            request = bytes.fromhex(record['request_hex'])
            response = bytes.fromhex(record['expected_response_hex'])
            assert model.respond(request) == response
            t.packet(request, response, model._windows)
            supplied += 1
    assert supplied == 800
    # Six seeded streams with arbitrary warm-up swaps, 32 circular wraps each.
    for seed in [0, 1, 42, 0x57214720, 0xFFFF, 20261003]:
        rng = random.Random(seed)
        for index in range(513):
            bound = 65536 if seed % 2 else 128
            a, b = rng.randrange(bound), rng.randrange(bound)
            request = (encode_request(index, ITEM_B, b, ITEM_A, a) if rng.randrange(2)
                       else encode_request(index, ITEM_A, a, ITEM_B, b))
            t.packet(request, model.respond(request), model._windows)
    # Explicit equality/held crossings, maximum/zero sums, truncation changes.
    directed = [
        [(100, 200)]*16 + [(102,198),(103,197),(99,201),(98,202)]*24,
        [(65535, 0)]*16 + [(65535,0),(0,65535),(1,65534),(65534,1)]*24,
        [(100,100)]*15 + [(115,85)] + [(101,99),(100,100),(100,100)]*32,
    ]
    # Force every relation at the last warm-up commit and every destination
    # relation at index 16. Last=99 is equal with sum remainder 15.
    for last in [98, 100, 102, 99]:
        for incoming in [98, 100, 102]:
            directed.append([(100, 200)]*15 + [(last, 2*last)]
                            + [(incoming, 2*incoming)])
    for prices in directed:
        for index, (a, b) in enumerate(prices):
            request = (encode_request(index, ITEM_B, b, ITEM_A, a) if index % 2 == 0
                       else encode_request(index, ITEM_A, a, ITEM_B, b))
            t.packet(request, model.respond(request), model._windows)
    # Reset at every state, including subtraction, addition and final commit,
    # with both warm-up and rolling commands and a pending committed result. Check all RAM words on every edge:
    # a reset on the commit edge MUST suppress the write, even with valid high.
    for warm in [0, 1]:
      for target_state in ([0, 1, 3, 4, 5] if warm else range(6)):
        for item in range(2):
            # Populate both histories and nonzero BUY/SELL before reset tests.
            for index in range(35):
                a, b = ((100, 200) if index < 16 else
                        [(102,198),(103,197),(99,201),(98,202)][(index-16)%4])
                request = encode_request(index, ITEM_A, a, ITEM_B, b)
                t.packet(request, model.respond(request), model._windows)
            assert all(t.held) and all(sum(w) for w in t.windows)
            if warm:
                # A new session leaves physical history populated/stale.
                t.step(clear=1)
                model.respond(encode_request(0, ITEM_A, 0, ITEM_B, 65535))
            if target_state:
                response = (bytes([0,0,17,0,34,0,0,0]) if warm else
                            model.respond(encode_request(35, ITEM_A, 0, ITEM_B, 65535)))
                t.step(valid=1, item=item, price=0 if item == 0 else 65535,
                       pos=0 if warm else t.pointer, warm=warm,
                       answer=response[3 if item == 0 else 5])
                for _ in range(4):
                    if t.state == target_state:
                        break
                    t.step(**t.noise())
                if target_state == 5:
                    for _ in range(64):
                        t.step(ready=0, valid=1, **t.noise())
            assert t.state == target_state
            t.counts[f'reset_{"warm" if warm else "steady"}_state_{target_state}'] += 1
            t.step(reset=1, valid=1, ready=1, **t.noise())
            t.step(reset=1, clear=1, valid=1, **t.noise())
            t.step()
            # Restart on the SAME engine, refill all words before first scored
            # update. Deliberately retain stale physical RAM through reset.
            for index in range(35):
                request = encode_request(index, ITEM_B, 65000-index, ITEM_A, index*17)
                t.packet(request, model.respond(request), model._windows)
    t.file.close()
    for name in ['held_1', 'held_2', 'previous_equals_old_average',
                 'price_equals_new_average', 'truncated_average', 'maximum_sum',
                 'zero_sum', 'warmup_swaps', 'wraps', 'result_stall_edges']:
        assert t.counts[name] > 0, name
    for old in ["below", "equal", "above"]:
        assert t.counts[f"warmup_final_{old}"] > 0
        assert t.counts[f"scored_wrap_previous_{old}"] > 0
        for new in ["below", "equal", "above"]:
            assert t.counts[f"transition_{old}_{new}"] > 0
            assert t.counts[f"first_scored_{old}_{new}"] > 0
    for state in range(6):
        assert t.counts[f'reset_state_{state}'] >= 2
    summary = dict(sorted(t.counts.items()))
    summary.update(supplied_fixture_records=supplied, edges=t.edges,
                   extra_packet_records=t.counts['packets']-supplied,
                   trace_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    print(json.dumps(summary, indent=2), flush=True)
    return summary


def main():
    generator = Path(sys.argv[1]).resolve()
    provenance = json.loads((HERE / 'oracle/SOURCE.json').read_text())
    for entry in provenance['files']:
        if entry['unchanged']:
            copied = HERE / 'oracle' / entry['local_path']
            assert hashlib.sha256(copied.read_bytes()).hexdigest() == entry['upstream_sha256'], copied
    print('PASS: pinned unchanged oracle/factory/fixture source hashes', flush=True)
    run([sys.executable, HERE / 'oracle/run_checks.py'])
    with tempfile.TemporaryDirectory(prefix='phase-f-') as directory:
        tmp = Path(directory)
        trace = tmp / 'trace.txt'
        summary = build_trace(trace)
        run([generator, 'replay', trace])
        rtl = tmp / 'engine.v'
        run([generator, 'emit', rtl])
        data = rtl.read_bytes()
        run([generator, 'emit', rtl])
        assert data == rtl.read_bytes(), 'nondeterministic engine RTL'
        assert b'initial' not in data, 'unexpected hardware initialization'
        assert b'reg [15:0] engine_history[0:31]' in data
        assert data.count(b'(* syn_ramstyle="block_ram" *)') == 1
        assert b'(* syn_ramstyle="block_ram" *)\n    reg [15:0] engine_history[0:31]' in data
        net = tmp / 'net.json'
        run(['yosys', '-Q', '-q', '-p', f'read_verilog {rtl}; hierarchy -check -top gqh_update_engine; proc; opt_clean; check -assert; write_json {net}'])
        module = json.loads(net.read_text())['modules']['gqh_update_engine']
        arithmetic_cells = [c for c in module['cells'].values()
                            if c['type'] in ('$add', '$sub')]
        assert len(arithmetic_cells) == 1, arithmetic_cells
        cell = arithmetic_cells[0]
        assert cell['type'] == '$add'
        assert len(cell['connections']['A']) == len(cell['connections']['B']) == 21
        assert len(cell['connections']['Y']) == 21
        assert cell['connections']['A'][0] == cell['connections']['B'][0]
        assert cell['connections']['A'][1:] == module['netnames']['arithmetic_lhs']['bits']
        assert cell['connections']['B'][1:] == module['netnames']['arithmetic_rhs']['bits']
        assert cell['connections']['Y'] == module['netnames']['arithmetic_with_carry']['bits']
        summary['arithmetic_structure'] = dict(add_cells=1, sub_cells=0,
            encoded_width=21, retained_width=20, shared_guard_carry=True)
        print('PASS arithmetic structure: one addition, 20 retained bits, shared guard carry; no subtract/increment chain')
        ports = module['ports']
        for suffix in ['a', 'b']:
            assert 'previous_' + suffix not in module['netnames']
            for flag in ['below', 'above']:
                assert len(module['netnames'][f'previous_{flag}_{suffix}']['bits']) == 1
        expected = {'clock':1, 'reset':1, 'session_clear':1, 'update_valid':1,
                    'result_ready':1, 'update$item_select':1, 'update$price':16,
                    'update$window_position':4, 'update$warmup':1,
                    'update_ready':1, 'result_valid':1, 'action':2}
        assert {k:len(v['bits']) for k,v in ports.items()} == expected
        assert {k for k,v in ports.items() if v['direction']=='output'} == {'update_ready','result_valid','action'}
        exe = tmp / 'engine_tb'
        run(['iverilog', '-g2012', '-s', 'engine_tb', '-o', exe, rtl, HERE / 'engine_tb.v'])
        run(['vvp', exe, f'+TRACE={trace}'])
        print('RTL SHA256:', hashlib.sha256(data).hexdigest(), flush=True)
        if len(sys.argv) == 3:
            output = Path(sys.argv[2])
            output.mkdir(parents=True, exist_ok=True)
            (output / 'gqh_update_engine.v').write_bytes(data)
            (output / 'coverage.json').write_text(json.dumps(summary, indent=2)+'\n')
            (output / 'trace.sha256').write_text(summary['trace_sha256']+'\n')
    print('PASS: Phase F independent oracle, Cyclesim, deterministic RTL, Yosys and Icarus')


if __name__ == '__main__':
    main()
