"""End to end against a real Garage server, when one is running:

  GARAGE_E2E=http://127.0.0.1:3900 AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... pytest

Skipped otherwise. In D1 it ran against the Garage v2.4.1 binary with the
same garage.toml the cluster uses."""

import os
import uuid

import pytest

from tests.test_loop import Clock, Counter, quiet
from trainer.goodput import analyse
from trainer.loop import StepLog, run
from trainer.store import S3Store

endpoint = os.environ.get("GARAGE_E2E")
pytestmark = pytest.mark.skipif(not endpoint, reason="no Garage endpoint in GARAGE_E2E")


def test_interrupt_resume_and_goodput_through_real_s3():
    import boto3
    from botocore.config import Config
    s3 = boto3.client("s3", endpoint_url=endpoint, region_name="garage",
                      config=Config(s3={"addressing_style": "path"}))
    store = S3Store(s3, "checkpoints", f"e2e-{uuid.uuid4().hex[:8]}", keep=2)
    clock = Clock()
    with pytest.raises(SystemExit):
        run(Counter(die_after=130), store, StepLog(store, "a", clock=clock, echo=quiet), 300, 50, clock=clock)
    assert store.latest() == 100
    resumed = Counter()
    run(resumed, store, StepLog(store, "b", clock=clock, echo=quiet), 300, 50, clock=clock)
    assert resumed.n == 300
    kept = s3.list_objects_v2(Bucket="checkpoints", Prefix=f"{store.run}/ckpt/step-")["Contents"]
    assert [o["Key"].rsplit("/", 1)[1] for o in kept] == ["step-000250.bin", "step-000300.bin"]
    r = analyse(store.logs())
    assert r["attempts"] == ["a", "b"] and r["steps_redone"] == 30 and r["final_step"] == 300
