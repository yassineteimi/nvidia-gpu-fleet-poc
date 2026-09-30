# The goodput trainer. Built by .github/workflows/trainer-image.yml for
# linux/amd64 and pinned by digest in workloads/goodput/job.yaml.
#
# The base is the PyTorch runtime image, pinned by digest: about 4.1 GB of
# CUDA and torch in one layer, which is why scripts/goodput.sh pulls it onto
# the GPU node before the timed run starts.
FROM pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime@sha256:eee11b3b3872a8c838e35ef48f08b2d5def2080902c7f666831310ca1a0ef2be

# torch lives in Ubuntu 24.04's system Python 3.12, which refuses pip installs
# unless told otherwise (PEP 668). The base image put torch there the same way,
# and nothing else in this single-purpose image uses that Python.
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt
COPY trainer/ trainer/

# Nothing here needs root. The uid has no /etc/passwd entry, and building
# torch's SGD optimizer imports torch._dynamo, which names its cache directory
# after getpass.getuser(); that reads USER first. Without it the first Job on
# the L4 died at start (docs/04-goodput-and-burn-in.md). HOME is somewhere
# writable for torch's caches.
ENV HOME=/tmp USER=trainer PYTHONUNBUFFERED=1
USER 65532:65532

# Smoke test at build time, on CPU and as the user the Job runs as: every module
# imports, and the PyTorch backend builds its optimizer, takes a step and
# round-trips a checkpoint. No image if it doesn't.
RUN python3 -c "import boto3; from trainer import dump, goodput, loop, s3, store; \
from trainer.torch_backend import TorchBackend; \
b = TorchBackend(width=64, depth=2, batch=32, device='cpu'); b.step(); b.load(b.save()); b.step(); \
print('trainer smoke test passed')"

ENTRYPOINT ["python3", "-m", "trainer"]
