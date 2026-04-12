import unittest
from unittest import mock

import bridge


class BridgeEntrypointTests(unittest.TestCase):
    def test_replace_mode_truncates_table_in_place(self):
        spark = mock.Mock()

        bridge.clear_target_table_for_replace(
            spark, "s3tablesbp.customer_logs.logs_service_hour"
        )

        spark.sql.assert_called_once_with(
            "TRUNCATE TABLE s3tablesbp.customer_logs.logs_service_hour"
        )


if __name__ == "__main__":
    unittest.main()
