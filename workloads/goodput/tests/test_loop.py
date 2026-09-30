"""The loop against an in-memory store and a stand-in model: resume from the
latest checkpoint, never from a half-written one, and a step log the goodput
analysis can read."""

import json

from trainer.goodput import analyse
from trainer.loop import StepLog, run


class MemStore:
    def __init__(self):
        self.ckpts, self.latest_step, self.logs_by_attempt = {}, None, {}

    def latest(self):
        return self.latest_step

    def get_checkpoint(self, step):
        return self.ckpts[step]

    def put_checkpoint(self, step, data):
        self.ckpts[step] = data
        self.latest_step = step

    def put_log(self, attempt, text):
        self.logs_by_attempt[attempt] = text


class Counter:
    """Stand-in model whose whole state is the number of steps it has taken."""
    def __init__(self, die_after=None):
        self.n, self.die_after = 0, die_after

    def step(self):
        if self.die_after is not None and self.n >= self.die_after:
            raise SystemExit("evicted")
        self.n += 1

    def save(self):
        return str(self.n).encode()

    def load(self, data):
        self.n = int(data)


class Clock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        self.t += 0.5
        return self.t


def quiet(*a, **k):
    pass


def test_resume_continues_from_the_latest_checkpoint_and_the_model_state_matches():
    store, clock = MemStore(), Clock()
    first = Counter(die_after=130)
    try:
        run(first, store, StepLog(store, "a", clock=clock, echo=quiet), 300, 50, clock=clock)
    except SystemExit:
        pass
    assert store.latest() == 100

    second = Counter()
    run(second, store, StepLog(store, "b", clock=clock, echo=quiet), 300, 50, clock=clock)
    assert second.n == 300                 # 100 restored + 200 taken, not 130 + 200
    b = [json.loads(l) for l in store.logs_by_attempt["b"].splitlines()]
    assert b[0]["ev"] == "start" and b[0]["resumed_from"] == 100
    assert [e["step"] for e in b if e["ev"] == "step"][0] == 101
    assert b[-1]["ev"] == "done"


def test_an_evicted_attempt_flushes_every_step_it_took():
    # Found by the end-to-end test against real Garage: without a flush on the
    # way out, steps since the last periodic flush vanish from the log and the
    # analysis counts them as outage instead of redone work.
    store, clock = MemStore(), Clock()
    try:
        run(Counter(die_after=130), store, StepLog(store, "a", flush_s=1e9, clock=clock, echo=quiet),
            300, 50, clock=clock)
    except SystemExit:
        pass
    events = [json.loads(l) for l in store.logs_by_attempt["a"].splitlines()]
    assert events[-1]["ev"] == "step" and events[-1]["step"] == 130


def test_the_logs_feed_the_goodput_analysis():
    store, clock = MemStore(), Clock()
    try:
        run(Counter(die_after=130), store, StepLog(store, "a", clock=clock, echo=quiet), 300, 50, clock=clock)
    except SystemExit:
        pass
    clock.t += 300
    run(Counter(), store, StepLog(store, "b", clock=clock, echo=quiet), 300, 50, clock=clock)
    r = analyse(store.logs_by_attempt)
    assert r["final_step"] == 300 and r["steps_kept"] == 300
    assert r["attempts"] == ["a", "b"]
    assert r["outage_s"] > 300
