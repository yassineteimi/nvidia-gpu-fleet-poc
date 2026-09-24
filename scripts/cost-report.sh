#!/usr/bin/env bash
#
# Report what the GPU node has cost so far, from the session log that gpu-up.sh
# and gpu-down.sh maintain.
#
# The log is a local record of when the node was actually up, not an invoice.
# Scaleway is the authority on what was billed. This exists so that a session
# never ends with a vague sense that it was probably fine.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_env_optional

if [ ! -f "$SESSION_LOG" ]; then
  log "no session log yet at $SESSION_LOG. No GPU has been started."
  exit 0
fi

printf '\n  %-22s %-22s %8s  %10s\n' "started" "ended" "duration" "cost"
printf '  %s\n' "--------------------------------------------------------------------"

# LC_ALL=C keeps the decimal point a point. awk follows the locale, so on a
# machine set to French it printed 0,39 h beside EUR 0.79/h on the same line.
LC_ALL=C awk -F, \
  -v gpu_rate="$GPU_HOURLY_EUR" \
  -v now="$(date -u +%s)" '
  function to_epoch(ts,   cmd, out) {
    cmd = "date -u -d \"" ts "\" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ \"" ts "\" +%s"
    cmd | getline out
    close(cmd)
    return out + 0
  }

  NR == 1 { next }
  $1 == "" { next }

  {
    started = to_epoch($1)
    if ($2 == "") {
      ended = now
      open_session = 1
      open_label = " (still up)"
    } else {
      ended = to_epoch($2)
      open_label = ""
    }

    hours = (ended - started) / 3600.0
    cost = hours * gpu_rate
    total_hours += hours
    total_cost += cost
    sessions += 1

    printf "  %-22s %-22s %6.2f h  EUR %6.2f%s\n", $1, ($2 == "" ? "open" : $2), hours, cost, open_label
  }

  END {
    printf "\n  %d session(s), %.2f GPU hours, EUR %.2f at EUR %s/h\n", \
      sessions, total_hours, total_cost, gpu_rate
    if (open_session) {
      printf "\n  A GPU node is still up. Run make down when the session is over.\n"
    }
  }
' "$SESSION_LOG"

cat <<EOF

  The control plane bills separately and continuously at about
  EUR $CONTROL_PLANE_HOURLY_EUR/h for as long as it exists.
  Scaleway's console is the authority on what was actually charged.

EOF
