# Session D: goodput, burn-in and tenancy

!!! info "Status: not yet run"
    This page holds the plan and the acceptance test. I'll write the results
    during the session, from captured output, as I did for Sessions A and B.

## Scope

GPU time slicing through the GPU Operator, with two tenant namespaces under
ResourceQuota. A PyTorch training loop with checkpointing, interrupted mid-run by an
injected fault, with total time, useful compute time and time lost to the restart
measured. And a short burn-in with a stability record.

## Acceptance test

A goodput figure, with the method written down and every input published. A burn-in
record of temperature, clocks, throttle reasons, ECC deltas and XID count over several
hours, labelled as a scaled-down version of a multi-day, multi-rack campaign.

## What happened

Not run yet.
