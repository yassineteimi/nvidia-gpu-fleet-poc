"""Print one run's step logs from the store as JSON, {attempt: jsonl text}.
scripts/goodput.sh runs this in the cluster, where the store is reachable,
and saves the output next to the rest of the evidence.

  python3 -m trainer.dump <run id>
"""

import json
import os
import sys

from . import s3
from .store import S3Store


def main(argv):
    store = S3Store(s3.client(), os.environ["CHECKPOINT_BUCKET"], argv[0])
    json.dump(store.logs(), sys.stdout)


if __name__ == "__main__":
    main(sys.argv[1:])
