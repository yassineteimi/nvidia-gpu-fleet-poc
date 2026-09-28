# gpu-remediator. Built by .github/workflows/remediator-image.yml for
# linux/amd64 and pinned by digest in gitops/manifests/gpu-remediator/.
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY remediator/ remediator/

# The kubernetes client needs nothing from root.
USER 65532:65532
ENTRYPOINT ["python", "-m", "remediator"]
