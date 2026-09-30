import json

import pytest

from trainer.goodput import analyse


def jsonl(events):
    return "\n".join(json.dumps(e) for e in events) + "\n"


def attempt(name, start_t, resumed_from, steps, step_s=1.0, ckpt_every=50, write_s=2.0,
            restore_s=0.0, done_at=None):
    """Events for one attempt: steps of step_s each, checkpoints every ckpt_every."""
    events = [{"ev": "start", "t": start_t, "attempt": name,
               "resumed_from": resumed_from, "restore_s": restore_s}]
    t = start_t
    for s in steps:
        events.append({"ev": "step", "t": t + step_s, "t0": t, "step": s, "attempt": name})
        t += step_s
        if s % ckpt_every == 0 or s == done_at:
            t += write_s
            events.append({"ev": "ckpt", "t": t, "step": s, "write_s": write_s, "attempt": name})
    if done_at is not None:
        events.append({"ev": "done", "t": t, "step": done_at, "attempt": name})
    return events


def test_an_uninterrupted_run_is_all_useful_but_checkpoints():
    a = attempt("a", 1000.0, None, range(1, 101), done_at=100)
    r = analyse({"a": jsonl(a)})
    assert r["useful_s"] == 100.0
    assert r["checkpoint_s"] == 4.0          # steps 50 and 100
    assert r["redone_s"] == 0 and r["outage_s"] == 0
    assert r["total_s"] == 104.0
    assert r["goodput"] == round(100 / 104, 4)


def test_an_interruption_is_split_into_redone_work_and_outage():
    # Attempt a checkpoints at 50 and 100, reaches step 130, and dies at t=1134.
    a = attempt("a", 1000.0, None, range(1, 131))
    # 400 s later attempt b starts, spends 3 s restoring step 100, and finishes at 200.
    b_start = a[-1]["t"] + 400.0 + 3.0
    b = attempt("b", b_start, 100, range(101, 201), restore_s=3.0, done_at=200)
    r = analyse({"b": jsonl(b), "a": jsonl(a)})          # order of the dict must not matter
    assert r["attempts"] == ["a", "b"]
    assert r["steps_kept"] == 200 and r["steps_redone"] == 30   # 101..130 ran twice
    assert r["useful_s"] == 200.0
    assert r["redone_s"] == 30.0
    assert r["outage_s"] == pytest.approx(400.0)
    assert r["restore_s"] == 3.0
    assert r["checkpoint_s"] == 2.0 * 4        # 50, 100 in a; 150, 200 in b
    assert r["other_s"] == pytest.approx(0.0, abs=1e-6)
    assert r["outages"][0]["seconds"] == pytest.approx(400.0)


def test_job_timestamps_set_the_total_and_the_rest_lands_in_other():
    a = attempt("a", 1000.0, None, range(1, 51), done_at=50)
    r = analyse({"a": jsonl(a)}, job_start=990.0, job_end=1060.0)   # 10 s startup, 8 s teardown
    assert r["total_s"] == 70.0
    assert r["other_s"] == pytest.approx(70.0 - 50.0 - 2.0)


def test_a_run_that_never_finished_is_an_error_not_a_number():
    a = attempt("a", 1000.0, None, range(1, 20))
    with pytest.raises(ValueError, match="done"):
        analyse({"a": jsonl(a)})


def test_two_interruptions_before_the_same_checkpoint():
    a = attempt("a", 0.0, None, range(1, 61))                     # dies at 60, ckpt at 50
    b = attempt("b", a[-1]["t"] + 100, 50, range(51, 71))         # dies at 70, no new ckpt
    c = attempt("c", b[-1]["t"] + 100, 50, range(51, 101), done_at=100)
    r = analyse({"a": jsonl(a), "b": jsonl(b), "c": jsonl(c)})
    assert r["steps_redone"] == 10 + 20        # 51..60 from a, 51..70 from b
    assert r["useful_s"] == 100.0
    assert r["outage_s"] == pytest.approx(200.0)
