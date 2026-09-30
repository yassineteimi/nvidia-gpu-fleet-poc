"""Entry point in the pod. Everything comes from the environment: the S3
credentials from the checkpoint-s3 Secret, the rest from the Job spec."""

import os
import signal
import sys

from . import s3
from .loop import StepLog, env_int, run
from .store import S3Store


def main():
    # Eviction sends SIGTERM. Turn it into SystemExit so the loop flushes the
    # step log on its way out, then exit 143 like an unhandled SIGTERM would.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    store = S3Store(s3.client(), os.environ["CHECKPOINT_BUCKET"], os.environ["RUN_ID"])
    steplog = StepLog(store, attempt=os.environ.get("POD_NAME", "local"))

    from .torch_backend import TorchBackend  # imported late so the tests don't need torch
    backend = TorchBackend(width=env_int("WIDTH", 2048), depth=env_int("DEPTH", 8),
                           batch=env_int("BATCH", 65536))
    run(backend, store, steplog, total_steps=env_int("TOTAL_STEPS", 3000),
        ckpt_every=env_int("CKPT_EVERY", 200))


if __name__ == "__main__":
    main()
