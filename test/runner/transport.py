"""Byte transports the runner can talk through: the real board, or a scripted fake.

Contract shared by both:
  write(data)            send bytes
  read(size, timeout_s)  return 1..size bytes as soon as some arrive, or b"" if
                         nothing arrives within timeout_s
  drain()                return (and discard) whatever is already buffered, without waiting
  close()
"""

from __future__ import annotations

import time
from collections import deque
from collections.abc import Mapping, Sequence
from typing import Optional, Protocol

from fixture import FixtureRecord

# A scripted reply is a list of chunks. None means "silence until the deadline":
# chunks after it are only seen by drain(), i.e. they arrive late.
Reply = Sequence[Optional[bytes]]

FAULTS = ("wrong_action", "short", "timeout", "split", "extra")
_ACTION1 = 3  # response byte holding slot 1's action


class Transport(Protocol):
    def write(self, data: bytes) -> None: ...
    def read(self, size: int, timeout_s: float) -> bytes: ...
    def drain(self) -> bytes: ...
    def close(self) -> None: ...


class SerialTransport:
    """The Tang Nano 20K's BL616 USB-serial port, opened the way the official scripts open it."""

    _TIMEOUT_SLACK_S = 0.001  # skip re-configuring the port for sub-ms timeout differences
    _MIN_TIMEOUT_S = 0.001    # Windows pyserial rounds a sub-ms timeout to 0 = block forever

    def __init__(self, port: str, baud: int, timeout_s: float, settle_s: float = 0.2) -> None:
        import serial  # imported here so fake runs and tests work without pyserial

        # serial_for_url opens plain ports (COM6, /dev/cu.usbserial-*) and pyserial URLs
        # such as loop://, which the tests use as a board-free echo port.
        self._serial = serial.serial_for_url(port, baud, timeout=timeout_s)
        self._full_timeout_s = timeout_s
        time.sleep(settle_s)
        self._serial.reset_input_buffer()

    def write(self, data: bytes) -> None:
        self._serial.write(data)

    def read(self, size: int, timeout_s: float) -> bytes:
        # pyserial re-programs the port on every timeout assignment, so only do it
        # when the budget really changed (normally it is the full timeout, already set).
        timeout_s = max(timeout_s, self._MIN_TIMEOUT_S)
        if abs(self._serial.timeout - timeout_s) > self._TIMEOUT_SLACK_S:
            self._serial.timeout = timeout_s
        return self._serial.read(size)

    def drain(self) -> bytes:
        # Runs before each send, outside the timed window: undo any shortened read budget
        # here so the next timed read does not pay for re-programming the port.
        if self._serial.timeout != self._full_timeout_s:
            self._serial.timeout = self._full_timeout_s
        waiting = self._serial.in_waiting
        return self._serial.read(waiting) if waiting else b""

    def close(self) -> None:
        self._serial.close()


class FakeTransport:
    """Answers the Nth write with the Nth scripted reply. Records what was sent."""

    def __init__(self, replies: Sequence[Reply]) -> None:
        self._replies = list(replies)
        self._pending: deque[bytes | None] = deque()
        self.sent: list[bytes] = []

    def write(self, data: bytes) -> None:
        reply = self._replies[len(self.sent)] if len(self.sent) < len(self._replies) else []
        self.sent.append(bytes(data))
        self._pending.extend(reply)

    def read(self, size: int, timeout_s: float) -> bytes:
        if not self._pending:
            return b""
        chunk = self._pending.popleft()
        if chunk is None:
            return b""
        if len(chunk) > size:
            self._pending.appendleft(chunk[size:])
        return chunk[:size]

    def drain(self) -> bytes:
        data = b"".join(c for c in self._pending if c is not None)
        self._pending.clear()
        return data

    def close(self) -> None:
        pass


def fake_replies(records: Sequence[FixtureRecord], faults: Mapping[int, str]) -> list[Reply]:
    """Replies that echo each record's expected response, except at fault rows.

    wrong_action  slot 1's action is changed to a different valid code
    short         the last byte never arrives
    timeout       nothing arrives
    split         the response arrives in two pieces (3 + 5 bytes); should still pass
    extra         one unsolicited byte follows the response
    """
    unknown = sorted(set(faults.values()) - set(FAULTS))
    if unknown:
        raise ValueError(f"unknown fault(s) {unknown}; choose from {', '.join(FAULTS)}")
    return [_reply(r.expected, faults.get(row)) for row, r in enumerate(records)]


def _reply(expected: bytes, fault: str | None) -> Reply:
    if fault == "wrong_action":
        action = expected[_ACTION1]
        wrong = 0x02 if action != 0x02 else 0x01
        return [expected[:_ACTION1] + bytes([wrong]) + expected[_ACTION1 + 1:]]
    if fault == "short":
        return [expected[:-1]]
    if fault == "timeout":
        return []
    if fault == "split":
        return [expected[:3], expected[3:]]
    if fault == "extra":
        return [expected + b"\xff"]
    return [expected]
