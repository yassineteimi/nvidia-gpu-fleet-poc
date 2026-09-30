"""Checkpoints and step logs in an S3 bucket, laid out per run:

  <run>/ckpt/step-000200.bin   checkpoint bytes
  <run>/ckpt/latest            the step number of the newest complete checkpoint
  <run>/log/<attempt>.jsonl    each attempt's step log

`latest` is written after the checkpoint upload returns, so a pod killed
mid-upload leaves the previous checkpoint as the one to resume from. Older
checkpoints are deleted, keeping `keep` of them, so the volume doesn't fill.
"""

import io


class S3Store:
    def __init__(self, s3, bucket, run, keep=2):
        self.s3, self.bucket, self.run, self.keep = s3, bucket, run, keep

    def _key(self, *parts):
        return "/".join((self.run,) + parts)

    def latest(self):
        try:
            body = self.s3.get_object(Bucket=self.bucket, Key=self._key("ckpt", "latest"))["Body"].read()
        except self.s3.exceptions.NoSuchKey:
            return None
        return int(body.decode())

    def get_checkpoint(self, step):
        out = io.BytesIO()
        self.s3.download_fileobj(self.bucket, self._key("ckpt", f"step-{step:06d}.bin"), out)
        return out.getvalue()

    def put_checkpoint(self, step, data):
        self.s3.upload_fileobj(io.BytesIO(data), self.bucket, self._key("ckpt", f"step-{step:06d}.bin"))
        self.s3.put_object(Bucket=self.bucket, Key=self._key("ckpt", "latest"), Body=str(step).encode())
        self._prune()

    def _prune(self):
        listing = self.s3.list_objects_v2(Bucket=self.bucket, Prefix=self._key("ckpt", "step-"))
        keys = sorted(o["Key"] for o in listing.get("Contents", []))
        for key in keys[:-self.keep]:
            self.s3.delete_object(Bucket=self.bucket, Key=key)

    def put_log(self, attempt, text):
        self.s3.put_object(Bucket=self.bucket, Key=self._key("log", f"{attempt}.jsonl"), Body=text.encode())

    def logs(self):
        listing = self.s3.list_objects_v2(Bucket=self.bucket, Prefix=self._key("log", ""))
        out = {}
        for o in listing.get("Contents", []):
            attempt = o["Key"].rsplit("/", 1)[1][: -len(".jsonl")]
            out[attempt] = self.s3.get_object(Bucket=self.bucket, Key=o["Key"])["Body"].read().decode()
        return out
