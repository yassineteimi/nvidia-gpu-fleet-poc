"""Reading an XID out of a kernel log line, and deciding what it means.

The fault or application split is the NVIDIA device plugin's, from
internal/rm/health.go at v0.20.0: these six codes are "application errors: the
GPU should still be healthy", and any other XID marks the GPU unhealthy. The
Session B alert rules and the node-problem-detector rule use the same list, so
Prometheus, the scheduler and this controller can't disagree about a GPU.
"""

import re

APPLICATION_XIDS = frozenset({13, 31, 43, 45, 68, 109})

# Short names for the codes an operator actually meets, for the Event message.
# Anything else is reported by number only, not guessed at.
XID_NAMES = {
    13: "Graphics Engine Exception",
    31: "GPU memory page fault",
    43: "GPU stopped processing",
    45: "Preemptive cleanup, due to previous errors",
    48: "Double Bit ECC Error",
    63: "ECC page retirement or row remapping recording event",
    64: "ECC page retirement or row remapper recording failure",
    74: "NVLink Error",
    79: "GPU has fallen off the bus",
    92: "High single-bit ECC error rate",
    94: "Contained ECC error",
    95: "Uncontained ECC error",
    109: "Context Switch Timeout Error",
    119: "GSP RPC Timeout",
    120: "GSP Error",
}

# The driver prints, from src/nvidia/src/kernel/gpu/rc/kernel_rc.c at 595.91.07:
#   NVRM: Xid (PCI:%04x:%02x:%02x): %d, pid=%s, name=%s, <message>
#   NVRM: Xid (PCI:%04x:%02x:%02x): %d, <message>              (process unknown)
# and on a MIG GPU the parenthesis also carries " GPU-I:%02u" and " GPU-CI:%02u".
_XID_LINE = re.compile(
    r"NVRM: Xid \(PCI:(?P<pci>[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})[^)]*\): (?P<code>\d+),")


def parse(message):
    """Return (pci, code) for the last Xid line in message, or None."""
    matches = list(_XID_LINE.finditer(message or ""))
    if not matches:
        return None
    last = matches[-1]
    return last.group("pci"), int(last.group("code"))


def is_fault(code):
    return code not in APPLICATION_XIDS


def describe(code):
    name = XID_NAMES.get(code)
    return f"XID {code} ({name})" if name else f"XID {code}"
