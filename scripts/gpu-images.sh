#!/usr/bin/env bash
#
# List the image labels Scaleway will actually boot on the GPU node type, in the
# zone the cluster runs in.
#
# Exists because the first make up failed with "couldn't find a local image for
# the given zone (fr-par-2) and commercial type (L4-1-24G)" for ubuntu_jammy.
# GPU instance types only accept images flagged as compatible with them, and that
# list is not the same as the list for ordinary instances. The marketplace API is
# the only authority on it, so ask it rather than guess.
#
# Usage: make gpu-images                   zone and type from Terraform
#        scripts/gpu-images.sh ZONE TYPE    anything else, e.g. pl-waw-2 L4-1-24G
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools curl jq terraform
load_env

ZONE="${1:-$(tf_output zone)}"
ZONE="${ZONE:-fr-par-2}"
TYPE="${2:-$(tf_output gpu_node_type)}"
TYPE="${TYPE:-L4-1-24G}"

API="https://api.scaleway.com/marketplace/v2"

scw_get() {
  curl -fsS -H "X-Auth-Token: $SCW_SECRET_KEY" "$API/$1"
}

# The local-images endpoint requires exactly one of image_id, version_id or
# image_label, so it cannot be asked "everything in this zone". Take the label
# list from the images endpoint first, then ask about each label in turn.
log "listing marketplace image labels"
all_labels="$(
  for page in 1 2 3; do
    scw_get "images?arch=x86_64&page_size=100&page=$page"
  done | jq -r '.images[]?.label' | sort -u
)"
[ -n "$all_labels" ] || die "the marketplace returned no image labels"

log "asking which of $(printf '%s\n' "$all_labels" | wc -l | tr -d ' ') labels will boot on $TYPE in $ZONE"
labels="$(
  printf '%s\n' "$all_labels" | while read -r label; do
    scw_get "local-images?image_label=$label&zone=$ZONE&page_size=100" \
      | jq -r --arg t "$TYPE" '
          .local_images[]?
          | select(.compatible_commercial_types | index($t))
          | [.label, .arch, .type] | @tsv'
  done | sort -u
)"

if [ -z "$labels" ]; then
  die "no images are listed as compatible with $TYPE in $ZONE"
fi

echo
printf '  %-40s %-8s %s\n' "label" "arch" "volume"
printf '%s\n' "$labels" | while IFS=$'\t' read -r label arch type; do
  if [[ "$label" == *gpu_os* ]]; then
    printf '  %-40s %-8s %-16s preinstalled NVIDIA driver, refused by variables.tf\n' "$label" "$arch" "$type"
  else
    printf '  %-40s %-8s %s\n' "$label" "$arch" "$type"
  fi
done
echo
