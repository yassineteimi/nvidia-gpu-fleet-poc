#!/usr/bin/env bash
#
# SIMULATED GPU fault: write one NVRM Xid line into a node's kernel log.
#
#   scripts/inject-xid.sh <node> <xid>
#
# The line has the exact shape the driver prints (src/nvidia/src/kernel/gpu/rc/
# kernel_rc.c at 595.91.07), so node-problem-detector sees what it would see on
# a real fault. Its message says SIMULATED, so the node's own kernel log is
# honest about where it came from. Nothing happens to the GPU: the driver, the
# device plugin and DCGM learn about XIDs through NVML and never see this line.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl ssh
require_kubeconfig
load_env
resolve_ssh_keypair

NODE="${1:?usage: scripts/inject-xid.sh <node> <xid>}"
XID="${2:?usage: scripts/inject-xid.sh <node> <xid>}"
[[ "$XID" =~ ^[0-9]+$ ]] || die "XID must be a number, got $XID"
TIMELINE="$REPO_ROOT/docs/artifacts/session-c-timeline.txt"

# The SSH address of a node, from Terraform, which is the only thing that knows it.
if [ "$NODE" = "$(tf_output gpu_node_name)" ]; then
  HOST="$(tf_output gpu_node_public_ip)"
elif kubectl_cp get node "$NODE" -o jsonpath='{.metadata.labels}' | grep -q 'node-role.kubernetes.io/control-plane'; then
  HOST="$(tf_output control_plane_public_ip)"
else
  die "don't know how to reach $NODE"
fi
[ -n "$HOST" ] || die "no address for $NODE in Terraform outputs"

# The GPU's real PCI address if there is one, so the line names the right device.
PCI="$(node_ssh "$HOST" "lspci -D -d 10de: 2>/dev/null | awk 'NR==1{print substr(\$1,1,10)}'" || true)"
PCI="${PCI:-0000:01:00}"

LINE="NVRM: Xid (PCI:$PCI): $XID, pid=0, name=inject-xid.sh, SIMULATED by scripts/inject-xid.sh, not a real fault"

log "SIMULATED: writing XID $XID for PCI $PCI into the kernel log of $NODE"
# The injection time comes from the node's own clock, in the same command as the
# write, so it can be compared with the controller's annotations (another
# NTP-synced node) and not with this laptop. Not from the condition either: its
# lastTransitionTime is derived from the kernel's uptime counter, and on the
# control plane, six days after boot, it read 4 seconds early.
at="$(node_ssh "$HOST" "echo '<3>$LINE' > /dev/kmsg && date -u +%Y-%m-%dT%H:%M:%S.%3NZ")"
mkdir -p "$(dirname "$TIMELINE")"
echo "xid_injected=$at node=$NODE xid=$XID simulated=true" | tee -a "$TIMELINE"
node_ssh "$HOST" "dmesg | grep 'NVRM: Xid' | tail -1"
