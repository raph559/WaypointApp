from __future__ import annotations

from dataclasses import dataclass


WLOC_RESPONSE_PREFIX = b"\x00\x01\x00\x00\x00\x01\x00\x00"
COORD_SCALE = 100_000_000


@dataclass(frozen=True)
class ProtoField:
    number: int
    wire_type: int
    raw_start: int
    raw_end: int
    value_start: int
    value_end: int
    varint_value: int | None = None

    @property
    def value_slice(self) -> slice:
        return slice(self.value_start, self.value_end)


def rewrite_wloc_response_body(response_body: bytes, latitude: float, longitude: float) -> tuple[bytes, int]:
    if len(response_body) < len(WLOC_RESPONSE_PREFIX) + 2:
        return response_body, 0
    if not response_body.startswith(WLOC_RESPONSE_PREFIX):
        return response_body, 0

    payload_len_offset = len(WLOC_RESPONSE_PREFIX)
    payload_len = int.from_bytes(response_body[payload_len_offset : payload_len_offset + 2], "big")
    payload_start = payload_len_offset + 2
    payload_end = payload_start + payload_len
    if payload_end > len(response_body):
        return response_body, 0

    new_payload, rewrite_count = rewrite_wloc_payload(response_body[payload_start:payload_end], latitude, longitude)
    if rewrite_count == 0:
        return response_body, 0
    if len(new_payload) > 0xFFFF:
        raise ValueError("rewritten WLoc payload is too large for response frame")

    trailing = response_body[payload_end:]
    rewritten = (
        response_body[:payload_len_offset]
        + len(new_payload).to_bytes(2, "big")
        + new_payload
        + trailing
    )
    return rewritten, rewrite_count


def rewrite_wloc_payload(payload: bytes, latitude: float, longitude: float) -> tuple[bytes, int]:
    location = encode_location(latitude, longitude)
    output = bytearray()
    rewrite_count = 0

    for field in iter_proto_fields(payload):
        if field.number == 2 and field.wire_type == 2:
            wifi_device = payload[field.value_slice]
            rewritten_device = rewrite_wifi_device(wifi_device, location)
            output += encode_length_delimited_field(2, rewritten_device)
            rewrite_count += 1
            continue
        output += payload[field.raw_start : field.raw_end]

    return bytes(output), rewrite_count


def rewrite_wifi_device(wifi_device: bytes, location: bytes) -> bytes:
    output = bytearray()
    for field in iter_proto_fields(wifi_device):
        if field.number == 2 and field.wire_type == 2:
            continue
        output += wifi_device[field.raw_start : field.raw_end]
    output += encode_length_delimited_field(2, location)
    return bytes(output)


def extract_wifi_locations_from_response_body(response_body: bytes) -> list[dict[str, float | str | None]]:
    if len(response_body) < len(WLOC_RESPONSE_PREFIX) + 2:
        return []
    if not response_body.startswith(WLOC_RESPONSE_PREFIX):
        return []

    payload_start = len(WLOC_RESPONSE_PREFIX) + 2
    payload_len = int.from_bytes(response_body[len(WLOC_RESPONSE_PREFIX) : payload_start], "big")
    payload = response_body[payload_start : payload_start + payload_len]
    locations = []

    for field in iter_proto_fields(payload):
        if field.number != 2 or field.wire_type != 2:
            continue
        bssid = None
        location = None
        wifi_device = payload[field.value_slice]
        for nested in iter_proto_fields(wifi_device):
            value = wifi_device[nested.value_slice]
            if nested.number == 1 and nested.wire_type == 2:
                bssid = value.decode("ascii", "replace")
            elif nested.number == 2 and nested.wire_type == 2:
                location = decode_location(value)
        locations.append(
            {
                "bssid": bssid,
                "latitude": location.get("latitude") if location else None,
                "longitude": location.get("longitude") if location else None,
            }
        )
    return locations


def encode_location(
    latitude: float,
    longitude: float,
    horizontal_accuracy: int = 39,
    vertical_accuracy: int = 1000,
    altitude: int = 530,
    unknown_value4: int = 3,
    motion_activity_type: int = 63,
    motion_activity_confidence: int = 467,
) -> bytes:
    output = bytearray()
    output += encode_varint_field(1, coord_to_wire_int(latitude))
    output += encode_varint_field(2, coord_to_wire_int(longitude))
    output += encode_varint_field(3, horizontal_accuracy)
    output += encode_varint_field(4, unknown_value4)
    output += encode_varint_field(5, altitude)
    output += encode_varint_field(6, vertical_accuracy)
    output += encode_varint_field(11, motion_activity_type)
    output += encode_varint_field(12, motion_activity_confidence)
    return bytes(output)


def decode_location(location: bytes) -> dict[str, float | int]:
    decoded: dict[str, float | int] = {}
    for field in iter_proto_fields(location):
        if field.wire_type != 0 or field.varint_value is None:
            continue
        value = decode_signed_int64(field.varint_value)
        if field.number == 1:
            decoded["latitude"] = value / COORD_SCALE
        elif field.number == 2:
            decoded["longitude"] = value / COORD_SCALE
        elif field.number == 3:
            decoded["horizontal_accuracy"] = value
        elif field.number == 5:
            decoded["altitude"] = value
        elif field.number == 6:
            decoded["vertical_accuracy"] = value
    return decoded


def coord_to_wire_int(coord: float) -> int:
    return int(coord * COORD_SCALE)


def encode_varint_field(number: int, value: int) -> bytes:
    return encode_varint((number << 3) | 0) + encode_varint(encode_signed_int64(value))


def encode_length_delimited_field(number: int, value: bytes) -> bytes:
    return encode_varint((number << 3) | 2) + encode_varint(len(value)) + value


def iter_proto_fields(data: bytes):
    offset = 0
    while offset < len(data):
        raw_start = offset
        tag, offset = read_varint(data, offset)
        number = tag >> 3
        wire_type = tag & 0x07

        if wire_type == 0:
            value_start = offset
            value, offset = read_varint(data, offset)
            yield ProtoField(number, wire_type, raw_start, offset, value_start, offset, value)
        elif wire_type == 1:
            value_start = offset
            offset += 8
            if offset > len(data):
                raise ValueError("fixed64 field exceeds payload length")
            yield ProtoField(number, wire_type, raw_start, offset, value_start, offset)
        elif wire_type == 2:
            length, offset = read_varint(data, offset)
            value_start = offset
            offset += length
            if offset > len(data):
                raise ValueError("length-delimited field exceeds payload length")
            yield ProtoField(number, wire_type, raw_start, offset, value_start, offset)
        elif wire_type == 5:
            value_start = offset
            offset += 4
            if offset > len(data):
                raise ValueError("fixed32 field exceeds payload length")
            yield ProtoField(number, wire_type, raw_start, offset, value_start, offset)
        else:
            raise ValueError(f"unsupported protobuf wire type {wire_type}")


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
        if shift >= 70:
            raise ValueError("varint is too long")
    raise ValueError("truncated varint")


def encode_varint(value: int) -> bytes:
    output = bytearray()
    while value >= 0x80:
        output.append((value & 0x7F) | 0x80)
        value >>= 7
    output.append(value)
    return bytes(output)


def encode_signed_int64(value: int) -> int:
    return value & ((1 << 64) - 1)


def decode_signed_int64(value: int) -> int:
    if value >= 1 << 63:
        return value - (1 << 64)
    return value
