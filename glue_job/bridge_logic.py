import re
from datetime import datetime, timezone

NORMALIZED_COLUMNS = [
    "ts",
    "ts_raw",
    "service",
    "status",
    "message_text",
    "host",
    "source",
    "trace_id",
    "span_id",
    "schema_version",
    "body_json_text",
    "attributes_hot_text",
    "attributes_cold_text",
    "tags_hot_text",
    "tags_cold_text",
    "source_file",
]

_TS_MILLIS_RE = re.compile(r"(?<!\d)(\d{10,})(?!\d)")


def parse_epoch_millis(value):
    if value is None:
        return None

    if isinstance(value, datetime):
        return value.replace(tzinfo=None)

    match = _TS_MILLIS_RE.search(str(value).strip())
    if not match:
        return None

    millis = int(match.group(1))
    if millis < 0:
        return None

    return datetime.fromtimestamp(millis / 1000.0, tz=timezone.utc).replace(tzinfo=None)


def normalize_log_record(record):
    if record is None:
        return None

    ts_raw = record.get("ts")
    ts = parse_epoch_millis(ts_raw)
    if ts is None:
        return None

    service = record.get("service")
    if service is None or str(service).strip() == "":
        service = "_unknown"

    return {
        "ts": ts,
        "ts_raw": None if ts_raw is None else str(ts_raw),
        "service": service,
        "status": record.get("status"),
        "message_text": record.get("message_text"),
        "host": record.get("host"),
        "source": record.get("source"),
        "trace_id": record.get("trace_id"),
        "span_id": record.get("span_id"),
        "schema_version": record.get("schema_version"),
        "body_json_text": record.get("body_json_text"),
        "attributes_hot_text": record.get("attributes_hot_text"),
        "attributes_cold_text": record.get("attributes_cold_text"),
        "tags_hot_text": record.get("tags_hot_text"),
        "tags_cold_text": record.get("tags_cold_text"),
        "source_file": record.get("source_file"),
    }
