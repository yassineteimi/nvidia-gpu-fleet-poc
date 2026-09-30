"""Goodput from the step logs, with the definitions fixed before the run.

  useful      time inside optimiser steps that are part of the final model:
              for each step number, only its last computation counts
  redone      time inside step computations that a later attempt threw away,
              because they came after the checkpoint it resumed from
  checkpoint  time spent writing checkpoints, in every attempt
  restore     time spent loading a checkpoint when an attempt resumed
  outage      from the last logged event of an interrupted attempt to the
              moment the next attempt starts loading its checkpoint: fault
              detection, drain, the wait for return to service, rescheduling
              and container start all land here
  other       whatever is left of the total: the first attempt's startup and
              the loop's own bookkeeping

  goodput = useful / total

`total` is the Job's startTime to completionTime when given (the API server's
clock), otherwise first start to done (the GPU node's clock). The step log is
flushed every few seconds, so up to one flush interval of work lost to an
interruption is counted as outage rather than redone; the write-up says which
it was from the pod's own log if that survived.
"""

import json
import sys


def parse(logs):
    """logs: {attempt: jsonl text} -> attempts ordered by their start event."""
    attempts = []
    for name, text in logs.items():
        events = [json.loads(line) for line in text.splitlines() if line.strip()]
        start = next((e for e in events if e["ev"] == "start"), None)
        if start is None:
            continue
        attempts.append({"name": name, "start": start, "events": events})
    return sorted(attempts, key=lambda a: a["start"]["t"])


def analyse(logs, job_start=None, job_end=None):
    attempts = parse(logs)
    if not attempts:
        raise ValueError("no attempt has a start event")

    kept, discarded = {}, []
    ckpt_s = restore_s = outage_s = 0.0
    outages = []
    done = None
    for i, a in enumerate(attempts):
        resumed = a["start"].get("resumed_from") or 0
        for step in sorted(s for s in kept if s > resumed):
            discarded.append(kept.pop(step))
        for e in a["events"]:
            if e["ev"] == "step":
                kept[e["step"]] = e["t"] - e["t0"]
            elif e["ev"] == "ckpt":
                ckpt_s += e["write_s"]
            elif e["ev"] == "done":
                done = e
        restore_s += a["start"].get("restore_s", 0.0)
        if i > 0:
            previous_last = attempts[i - 1]["events"][-1]["t"]
            began_restoring = a["start"]["t"] - a["start"].get("restore_s", 0.0)
            gap = began_restoring - previous_last
            outage_s += gap
            outages.append({"after": attempts[i - 1]["name"], "before": a["name"],
                            "last_event_t": previous_last, "resume_t": began_restoring,
                            "seconds": round(gap, 3)})

    if done is None:
        raise ValueError("no attempt reached done")
    total = (job_end - job_start) if job_start is not None and job_end is not None \
        else done["t"] - attempts[0]["start"]["t"]
    useful = sum(kept.values())
    redone = sum(discarded)
    other = total - useful - redone - ckpt_s - restore_s - outage_s
    return {
        "attempts": [a["name"] for a in attempts],
        "final_step": done["step"],
        "steps_kept": len(kept),
        "steps_redone": len(discarded),
        "total_s": round(total, 3),
        "useful_s": round(useful, 3),
        "redone_s": round(redone, 3),
        "checkpoint_s": round(ckpt_s, 3),
        "restore_s": round(restore_s, 3),
        "outage_s": round(outage_s, 3),
        "other_s": round(other, 3),
        "goodput": round(useful / total, 4) if total > 0 else None,
        "outages": outages,
    }


def main(argv):
    """goodput.py <attempt.jsonl>... [--job-start EPOCH --job-end EPOCH]"""
    files, job_start, job_end = [], None, None
    args = iter(argv)
    for arg in args:
        if arg == "--job-start":
            job_start = float(next(args))
        elif arg == "--job-end":
            job_end = float(next(args))
        else:
            files.append(arg)
    logs = {f.rsplit("/", 1)[-1].rsplit(".", 1)[0]: open(f).read() for f in files}
    print(json.dumps(analyse(logs, job_start, job_end), indent=2))


if __name__ == "__main__":
    main(sys.argv[1:])
