# The goodput trainer. Built by .github/workflows/trainer-image.yml for
# linux/amd64 and pinned by digest in workloads/goodput/job.yaml.
#
# The base is the PyTorch runtime image, pinned by digest: about 4.1 GB of
# CUDA and torch in one layer, which is why scripts/goodput.sh pulls it onto
# the GPU node before the timed run starts.
FROM pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime@sha256:eee11b3b3872a8c838e35ef48f08b2d5def2080902c7f666831310ca1a0ef2be

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY trainer/ trainer/

# Nothing here needs root. HOME is somewhere writable for torch's caches.
ENV HOME=/tmp PYTHONUNBUFFERED=1
USER 65532:65532
ENTRYPOINT ["python", "-m", "trainer"]
