import json
import tempfile
import unittest
from pathlib import Path

from checkpoint import (
    JsonCheckpointStore,
    finalize_successful_run,
    select_new_source_files,
)


class CheckpointTests(unittest.TestCase):
    def test_select_new_source_files_returns_only_unprocessed_paths(self):
        discovered = [
            "s3://bucket/path/file-b.parquet",
            "s3://bucket/path/file-a.parquet",
            "s3://bucket/path/file-b.parquet",
            "s3://bucket/path/file-c.parquet",
        ]
        processed = {
            "s3://bucket/path/file-a.parquet",
            "s3://bucket/path/file-c.parquet",
        }

        self.assertEqual(
            select_new_source_files(discovered, processed),
            ["s3://bucket/path/file-b.parquet"],
        )

    def test_json_checkpoint_store_round_trips_sorted_processed_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checkpoint_path = Path(temp_dir) / "processed-files.json"
            store = JsonCheckpointStore(str(checkpoint_path))

            store.save(
                {
                    "s3://bucket/path/file-b.parquet",
                    "s3://bucket/path/file-a.parquet",
                }
            )

            self.assertEqual(
                store.load(),
                {
                    "s3://bucket/path/file-a.parquet",
                    "s3://bucket/path/file-b.parquet",
                },
            )
            self.assertEqual(
                json.loads(checkpoint_path.read_text()),
                {
                    "processed_files": [
                        "s3://bucket/path/file-a.parquet",
                        "s3://bucket/path/file-b.parquet",
                    ]
                },
            )

    def test_finalize_successful_run_merges_new_files_before_persisting(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checkpoint_path = Path(temp_dir) / "processed-files.json"
            store = JsonCheckpointStore(str(checkpoint_path))
            store.save({"s3://bucket/path/file-a.parquet"})

            merged = finalize_successful_run(
                store,
                {"s3://bucket/path/file-a.parquet"},
                [
                    "s3://bucket/path/file-b.parquet",
                    "s3://bucket/path/file-c.parquet",
                ],
            )

            self.assertEqual(
                merged,
                {
                    "s3://bucket/path/file-a.parquet",
                    "s3://bucket/path/file-b.parquet",
                    "s3://bucket/path/file-c.parquet",
                },
            )
            self.assertEqual(store.load(), merged)


if __name__ == "__main__":
    unittest.main()
