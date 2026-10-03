"""Independent GQH packet codec and direct-window reference model.

Prices and indices are unsigned 16-bit integers. Each item keeps its own last
16 prices; averages are recomputed with sum() rather than a rolling sum.
"""

import struct

NONE = 0
SELL = 1
BUY = 2
ITEM_A = 0x11
ITEM_B = 0x22
WINDOW_SIZE = 16

_REQUEST = struct.Struct(">HBHBH")
_RESPONSE = struct.Struct(">HBBBBH")


def _unsigned16(name: str, value: int) -> None:
    if type(value) is not int or not 0 <= value <= 65535:
        raise ValueError(f"{name} must be an integer in 0..65535")


def _items(item1: int, item2: int) -> None:
    if (type(item1) is not int or type(item2) is not int
            or (item1, item2) not in ((ITEM_A, ITEM_B), (ITEM_B, ITEM_A))):
        raise ValueError("item IDs must contain 0x11 and 0x22 exactly once")


def encode_request(index: int, item1: int, price1: int,
                   item2: int, price2: int) -> bytes:
    """Encode the eight-byte request, preserving the supplied slot order."""
    _unsigned16("index", index)
    _items(item1, item2)
    _unsigned16("price1", price1)
    _unsigned16("price2", price2)
    return _REQUEST.pack(index, item1, price1, item2, price2)


def decode_request(request: bytes) -> tuple[int, int, int, int, int]:
    """Decode an exact eight-byte request and reject unknown or duplicate IDs."""
    if not isinstance(request, (bytes, bytearray)) or len(request) != 8:
        raise ValueError("request must contain exactly eight bytes")
    fields = _REQUEST.unpack(request)
    _items(fields[1], fields[3])
    return fields


class ReferenceModel:
    """Calculate responses independently, with index 0 starting a fresh session.

    Sessions must start at index 0 and continue sequentially. Each item's
    history and held action follow its ID even when packet slots are swapped.
    """

    def __init__(self) -> None:
        self._windows: dict[int, list[int]] = {ITEM_A: [], ITEM_B: []}
        self._actions: dict[int, int] = {ITEM_A: NONE, ITEM_B: NONE}
        self._next_index = 0

    def _reset(self) -> None:
        self._windows = {ITEM_A: [], ITEM_B: []}
        self._actions = {ITEM_A: NONE, ITEM_B: NONE}
        self._next_index = 0

    def _update(self, item: int, price: int) -> int:
        window = self._windows[item]
        if len(window) < WINDOW_SIZE:
            window.append(price)
            return NONE

        old_average = sum(window) // WINDOW_SIZE
        previous_price = window[-1]
        new_window = window[1:] + [price]
        new_average = sum(new_window) // WINDOW_SIZE
        if previous_price <= old_average and price > new_average:
            action = BUY
        elif previous_price >= old_average and price < new_average:
            action = SELL
        else:
            action = self._actions[item]
        self._windows[item] = new_window
        self._actions[item] = action
        return action

    def respond(self, request: bytes) -> bytes:
        """Update both items once and return the exact eight expected bytes."""
        index, item1, price1, item2, price2 = decode_request(request)
        if index == 0:
            self._reset()
        if index != self._next_index:
            raise ValueError(
                f"expected request index {self._next_index}, received {index}"
            )
        action1 = self._update(item1, price1)
        action2 = self._update(item2, price2)
        self._next_index = index + 1
        return _RESPONSE.pack(index, item1, action1, item2, action2, 0)
