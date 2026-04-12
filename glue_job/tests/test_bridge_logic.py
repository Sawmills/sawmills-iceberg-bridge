import unittest
from datetime import datetime

from bridge_logic import normalize_log_record, parse_epoch_millis


class BridgeLogicTests(unittest.TestCase):
    def test_parse_epoch_millis(self):
        parsed = parse_epoch_millis("1712320496789")

        self.assertEqual(parsed, datetime(2024, 4, 5, 12, 34, 56, 789000))

    def test_preserves_snowflake_shaped_columns(self):
        normalized = normalize_log_record(
            {
                "ts": "1712320496789",
                "service": "billing-api",
                "status": "INFO",
                "message_text": "hello world",
                "host": "ip-10-0-0-1",
                "source": "collector",
                "trace_id": "trace-123",
                "span_id": "span-456",
                "schema_version": "1",
                "body_json_text": '{"hello":"world"}',
                "attributes_hot_text": "hot",
                "attributes_cold_text": "cold",
                "tags_hot_text": "tag-hot",
                "tags_cold_text": "tag-cold",
                "source_file": "s3://bucket/path/file.parquet",
            }
        )

        self.assertIsNotNone(normalized)
        self.assertEqual(normalized["ts"], datetime(2024, 4, 5, 12, 34, 56, 789000))
        self.assertEqual(normalized["ts_raw"], "1712320496789")
        self.assertEqual(normalized["service"], "billing-api")
        self.assertEqual(normalized["status"], "INFO")
        self.assertEqual(normalized["message_text"], "hello world")
        self.assertEqual(normalized["host"], "ip-10-0-0-1")
        self.assertEqual(normalized["source"], "collector")
        self.assertEqual(normalized["trace_id"], "trace-123")
        self.assertEqual(normalized["span_id"], "span-456")
        self.assertEqual(normalized["schema_version"], "1")
        self.assertEqual(normalized["body_json_text"], '{"hello":"world"}')
        self.assertEqual(normalized["attributes_hot_text"], "hot")
        self.assertEqual(normalized["attributes_cold_text"], "cold")
        self.assertEqual(normalized["tags_hot_text"], "tag-hot")
        self.assertEqual(normalized["tags_cold_text"], "tag-cold")
        self.assertEqual(normalized["source_file"], "s3://bucket/path/file.parquet")

    def test_defaults_missing_service_to_unknown(self):
        normalized = normalize_log_record({"ts": "1712320496789", "service": None})

        self.assertIsNotNone(normalized)
        self.assertEqual(normalized["service"], "_unknown")

    def test_rejects_rows_with_unusable_timestamps(self):
        self.assertIsNone(normalize_log_record({"ts": "not-a-timestamp"}))
        self.assertIsNone(normalize_log_record({"ts": None}))


if __name__ == "__main__":
    unittest.main()
