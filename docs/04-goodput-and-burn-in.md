# Session D: goodput, burn-in and tenancy

!!! info "Status: not yet run"
    This chapter is written during the session, from output captured live, not
    reconstructed afterwards. Until the session has run, this page states the plan
    and the acceptance test only. Nothing is claimed here that has not happened.

## Scope

GPU time slicing configured through the GPU Operator, with two tenant namespaces under
ResourceQuota. A PyTorch training loop with checkpointing, interrupted mid-run by an
injected fault. Total time, useful compute time and time lost to restart, measured. A
short burn-in with a stability record.

## Acceptance test

A goodput figure with the method stated and every input published. A burn-in record
with temperature, clocks, throttle reasons, ECC deltas and XID count over several hours,
labelled explicitly as a scaled-down instance of a multi-day, multi-rack campaign.

## What happened

To be filled in during Session D with real captured output.
