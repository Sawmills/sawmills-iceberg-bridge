import json
from pathlib import Path
from typing import Iterable, List, Optional, Set, Tuple


def parse_s3_uri(uri: str) -> Tuple[str, str]:
    if not uri.startswith("s3://"):
        raise ValueError(f"unsupported s3 uri: {uri}")

    bucket_and_key = uri[5:]
    bucket, _, key = bucket_and_key.partition("/")
    if not bucket:
        raise ValueError(f"missing s3 bucket in uri: {uri}")
    return bucket, key


def derive_checkpoint_uri(source_path: str, namespace: str, table_name: str) -> str:
    if source_path.startswith("s3://"):
        bucket, key_prefix = parse_s3_uri(source_path.rstrip("/"))
        checkpoint_key = (
            f"{key_prefix}/_checkpoint/{namespace}/{table_name}/processed-files.json"
        )
        return f"s3://{bucket}/{checkpoint_key}"

    source_dir = Path(source_path)
    return str(
        source_dir / "_checkpoint" / namespace / table_name / "processed-files.json"
    )


def select_new_source_files(
    discovered_files: Iterable[str], processed_files: Iterable[str]
) -> List[str]:
    processed = set(processed_files)
    return sorted({path for path in discovered_files if path not in processed})


def finalize_successful_run(
    store: "JsonCheckpointStore",
    processed_before: Iterable[str],
    processed_now: Iterable[str],
) -> Set[str]:
    merged = set(processed_before)
    merged.update(processed_now)
    store.save(merged)
    return merged


class JsonCheckpointStore:
    def __init__(self, checkpoint_uri: str, s3_client=None):
        self.checkpoint_uri = checkpoint_uri
        self.s3_client = s3_client

    def load(self) -> Set[str]:
        payload = self._read_text()
        if payload is None:
            return set()

        document = json.loads(payload)
        return set(document.get("processed_files", []))

    def save(self, processed_files: Iterable[str]) -> None:
        document = {
            "processed_files": sorted(set(processed_files)),
        }
        self._write_text(json.dumps(document, indent=2, sort_keys=True))

    def _read_text(self) -> Optional[str]:
        if self.checkpoint_uri.startswith("s3://"):
            bucket, key = parse_s3_uri(self.checkpoint_uri)
            client = self._get_s3_client()
            try:
                response = client.get_object(Bucket=bucket, Key=key)
            except client.exceptions.NoSuchKey:
                return None
            return response["Body"].read().decode("utf-8")

        path = Path(self.checkpoint_uri)
        if not path.exists():
            return None
        return path.read_text()

    def _write_text(self, payload: str) -> None:
        if self.checkpoint_uri.startswith("s3://"):
            bucket, key = parse_s3_uri(self.checkpoint_uri)
            self._get_s3_client().put_object(
                Bucket=bucket,
                Key=key,
                Body=payload.encode("utf-8"),
                ContentType="application/json",
            )
            return

        path = Path(self.checkpoint_uri)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload)

    def _get_s3_client(self):
        if self.s3_client is None:
            import boto3

            self.s3_client = boto3.client("s3")
        return self.s3_client


def list_source_files(source_path: str, s3_client=None) -> List[str]:
    if source_path.startswith("s3://"):
        bucket, key_prefix = parse_s3_uri(source_path.rstrip("/"))
        import boto3

        client = s3_client or boto3.client("s3")
        paginator = client.get_paginator("list_objects_v2")
        source_files = []
        for page in paginator.paginate(Bucket=bucket, Prefix=key_prefix):
            for entry in page.get("Contents", []):
                key = entry["Key"]
                if key.endswith(".parquet"):
                    source_files.append(f"s3://{bucket}/{key}")
        return sorted(source_files)

    source = Path(source_path)
    if source.is_file() and source.suffix == ".parquet":
        return [str(source)]
    return sorted(str(path) for path in source.rglob("*.parquet"))
