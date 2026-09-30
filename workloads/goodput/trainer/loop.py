"""The training loop, without the model: steps, checkpoints, resume and the
step log that the goodput analysis reads.

The model is a backend with three methods (step, save, load), so this file is
tested end to end against a real Garage server with a stand-in backend, and
the PyTorch backend in torch_backend.py only has to do the maths.

Step log, one JSON object per line, all times from time.time() on the node:
  start  attempt began work; resumed_from is the checkpoint step, restore_s its load time
  step   one optimiser step, with its own start (t0) and end (t)
  ckpt   a checkpoint for `step` is durable in the store; write_s is the upload time
  done   the final step is checkpointed and the job is complete

No checkpoint on SIGTERM, on purpose: the fault being simulated is XID 79, the
GPU falling off the bus, and a process whose GPU is gone can't save anything.
The step log is flushed on the way out, though; that's a small write to the
store, and without it the last few seconds of steps would be misread as
outage. A node that dies outright would still lose up to `flush_s` of log.
"""

import json
import os
import time


class StepLog:
    """Keeps this attempt's events and rewrites them to the store every
    `flush_s` seconds, so an evicted pod loses at most that much of its log."""

    def __init__(self, store, attempt, flush_s=5.0, clock=time.time, echo=print):
        self.store, self.attempt, self.flush_s = store, attempt, flush_s
        self.clock, self.echo = clock, echo
        self.lines, self.last_flush = [], 0.0

    def event(self, ev, **fields):
        record = {"ev": ev, "t": round(self.clock(), 6), "attempt": self.attempt, **fields}
        line = json.dumps(record, sort_keys=True)
        self.lines.append(line)
        self.echo(line, flush=True)
        if ev != "step" or self.clock() - self.last_flush >= self.flush_s:
            self.flush()
        return record

    def flush(self):
        self.store.put_log(self.attempt, "\n".join(self.lines) + "\n")
        self.last_flush = self.clock()


def run(backend, store, steplog, total_steps, ckpt_every, clock=time.time):
    t = clock()
    latest = store.latest()
    if latest is None:
        start_step, restore_s = 0, 0.0
    else:
        backend.load(store.get_checkpoint(latest))
        start_step, restore_s = latest, clock() - t
    steplog.event("start", resumed_from=latest, restore_s=round(restore_s, 6))

    try:
        for step in range(start_step + 1, total_steps + 1):
            t0 = clock()
            backend.step()
            steplog.event("step", step=step, t0=round(t0, 6))
            if step % ckpt_every == 0 or step == total_steps:
                w0 = clock()
                store.put_checkpoint(step, backend.save())
                steplog.event("ckpt", step=step, write_s=round(clock() - w0, 6))
    except BaseException:
        # Evicted (SIGTERM, turned into SystemExit by __main__) or crashed:
        # write out the steps taken since the last flush, so the analysis sees
        # them as redone work rather than outage. Only the log, never a
        # checkpoint: the simulated fault is a GPU that has gone.
        steplog.flush()
        raise

    steplog.event("done", step=total_steps)
    steplog.flush()


def env_int(name, default):
    return int(os.environ.get(name, default))
