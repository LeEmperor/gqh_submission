"""Load replay fixtures: one request and its expected response per record.

A record looks like (field names agreed with the fixture author):

    {"session": 0, "index": 0,
     "request_hex": "00001100642200c8",
     "expected_response_hex": "0000110022000000"}

Accepted containers:
  *.jsonl  one record per line
  *.json   a list of records, or {"records": [...], <anything else>} where every
           other key (seed, generation settings, ...) is kept as metadata.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

PACKET_LEN = 8
VALID_ACTIONS = (0x00, 0x01, 0x02)  # NONE, SELL, BUY


class FixtureError(ValueError):
    """The fixture file is unusable; the message names the offending row."""


@dataclass(frozen=True)
class FixtureRecord:
    session: int
    index: int
    request: bytes
    expected: bytes


@dataclass(frozen=True)
class Fixture:
    path: Path
    records: tuple[FixtureRecord, ...]
    metadata: dict[str, Any] = field(default_factory=dict)


def load_fixture(path: str | Path) -> Fixture:
    path = Path(path)
    try:
        raw_records, metadata = _read_container(path)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise FixtureError(f"{path}: {exc}") from exc
    if not raw_records:
        raise FixtureError(f"{path}: no records")
    records = tuple(_parse_record(row, raw) for row, raw in enumerate(raw_records))
    return Fixture(path=path, records=records, metadata=metadata)


def _read_container(path: Path) -> tuple[list[Any], dict[str, Any]]:
    text = path.read_text(encoding="utf-8-sig")  # tolerate the BOM Windows editors add
    if path.suffix == ".jsonl":
        return [json.loads(line) for line in text.splitlines() if line.strip()], {}
    doc = json.loads(text)
    if isinstance(doc, list):
        return doc, {}
    if isinstance(doc, dict) and isinstance(doc.get("records"), list):
        return doc["records"], {k: v for k, v in doc.items() if k != "records"}
    raise FixtureError(f"{path}: expected a list of records or an object with a 'records' list")


def _parse_record(row: int, raw: Any) -> FixtureRecord:
    def fail(reason: str) -> FixtureError:
        return FixtureError(f"row {row}: {reason}")

    if not isinstance(raw, dict):
        raise fail("record is not an object")
    for key in ("index", "request_hex", "expected_response_hex"):
        if key not in raw:
            raise fail(f"missing '{key}'")
    session, index = raw.get("session", 0), raw["index"]
    if not isinstance(index, int) or not isinstance(session, int):
        raise fail("index and session must be integers")

    request = _packet(raw["request_hex"], "request_hex", fail)
    expected = _packet(raw["expected_response_hex"], "expected_response_hex", fail)

    if int.from_bytes(request[0:2], "big") != index:
        raise fail(f"index {index} disagrees with request bytes {request[0:2].hex()}")
    _check_expected_follows_protocol(request, expected, fail)
    return FixtureRecord(session=session, index=index, request=request, expected=expected)


def _packet(value: Any, name: str, fail) -> bytes:
    try:
        data = bytes.fromhex(value)
    except (TypeError, ValueError):
        raise fail(f"{name} is not hex: {value!r}") from None
    if len(data) != PACKET_LEN:
        raise fail(f"{name} is {len(data)} bytes, need {PACKET_LEN}")
    return data


def _check_expected_follows_protocol(request: bytes, expected: bytes, fail) -> None:
    """A correct board's answer must echo index and item IDs in slot order, with reserved = 0."""
    if expected[0:3] != request[0:3] or expected[4] != request[5]:
        raise fail("expected response does not echo the request's index and item IDs in slot order")
    if expected[6:8] != b"\x00\x00":
        raise fail("expected response has a nonzero reserved field")
    if expected[3] not in VALID_ACTIONS or expected[5] not in VALID_ACTIONS:
        raise fail("expected response has an action that is not NONE/SELL/BUY")
