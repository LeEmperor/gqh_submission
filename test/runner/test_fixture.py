import json

import pytest

from fixture import FixtureError, load_fixture

# Index 0, A=100, B=200 -> warm-up, both NONE (the record format agreed with Beginner 1).
REQ0 = "00001100642200c8"
RSP0 = "0000110022000000"
# Index 1, B in slot 1 -> response mirrors the slot order.
REQ1 = "0001220065110063"
RSP1 = "0001220011000000"


def write_json(path, doc):
    path.write_text(json.dumps(doc))
    return path


def record(index, req, rsp, session=0):
    return {"session": session, "index": index, "request_hex": req, "expected_response_hex": rsp}


def test_jsonl_fixture_loads_records_in_file_order(tmp_path):
    path = tmp_path / "f.jsonl"
    path.write_text(json.dumps(record(0, REQ0, RSP0)) + "\n\n" + json.dumps(record(1, REQ1, RSP1)) + "\n")

    fx = load_fixture(path)

    assert [r.index for r in fx.records] == [0, 1]
    assert fx.records[0].request == bytes([0x00, 0x00, 0x11, 0x00, 0x64, 0x22, 0x00, 0xC8])
    assert fx.records[1].expected == bytes([0x00, 0x01, 0x22, 0x00, 0x11, 0x00, 0x00, 0x00])
    assert fx.metadata == {}


def test_json_fixture_keeps_seed_and_settings_as_metadata(tmp_path):
    path = write_json(tmp_path / "f.json", {
        "seed": 1234,
        "settings": {"price_max": 100},
        "records": [record(0, REQ0, RSP0)],
    })

    fx = load_fixture(path)

    assert fx.metadata == {"seed": 1234, "settings": {"price_max": 100}}
    assert len(fx.records) == 1


def test_session_defaults_to_zero_and_is_kept_when_given(tmp_path):
    no_session = {"index": 0, "request_hex": REQ0, "expected_response_hex": RSP0}
    path = write_json(tmp_path / "f.json", [no_session, record(0, REQ0, RSP0, session=3)])

    fx = load_fixture(path)

    assert [r.session for r in fx.records] == [0, 3]


@pytest.mark.parametrize("bad_record, reason", [
    (record(0, "00001100642200", RSP0), "request is 7 bytes"),
    (record(0, REQ0, "000011002200000000"), "expected response is 9 bytes"),
    (record(0, "zz001100642200c8", RSP0), "request is not hex"),
    (record(5, REQ0, RSP0), "index 5 disagrees with request bytes (index 0)"),
    (record(0, REQ0, "0000110022000001"), "reserved is not 0x0000"),
    (record(0, REQ0, "0000220011000000"), "response swaps the request's slot order"),
    (record(0, REQ0, "0000110322000000"), "action 0x03 is not NONE/SELL/BUY"),
    ({"index": 0, "request_hex": REQ0}, "expected_response_hex missing"),
])
def test_malformed_record_is_rejected_with_its_row(tmp_path, bad_record, reason):
    path = write_json(tmp_path / "f.json", [record(0, REQ0, RSP0), bad_record])

    with pytest.raises(FixtureError, match=r"row 1"):
        load_fixture(path)


def test_empty_fixture_is_rejected(tmp_path):
    with pytest.raises(FixtureError):
        load_fixture(write_json(tmp_path / "f.json", {"seed": 1, "records": []}))


def test_fixture_saved_with_a_windows_bom_loads(tmp_path):
    path = tmp_path / "f.json"
    path.write_bytes(b"\xef\xbb\xbf" + json.dumps([record(0, REQ0, RSP0)]).encode())

    assert len(load_fixture(path).records) == 1


def test_fixture_in_a_non_utf8_encoding_is_a_fixture_error(tmp_path):
    path = tmp_path / "f.json"
    path.write_bytes(json.dumps([record(0, REQ0, RSP0)]).encode("utf-16"))

    with pytest.raises(FixtureError):
        load_fixture(path)
