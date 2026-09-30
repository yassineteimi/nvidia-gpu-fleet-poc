"""The S3 client, configured from the checkpoint-s3 Secret's variables.
Path-style addressing, because Garage serves buckets on its root domain only
when DNS for it is set up, and here it isn't."""

import os


def client():
    import boto3
    from botocore.config import Config
    return boto3.client(
        "s3",
        endpoint_url=os.environ["AWS_ENDPOINT_URL"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "garage"),
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 5}),
    )
