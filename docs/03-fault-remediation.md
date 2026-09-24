# Session C: fault detection and remediation

!!! info "Status: not yet run"
    This page holds the plan and the acceptance test. I'll write the results
    during the session, from captured output, as I did for Sessions A and B.

## Scope

node-problem-detector with a custom monitor that reads the kernel log for `NVRM: Xid`
and sets a `GPUUnhealthy` node condition. A Python controller on the Kubernetes client
reacts to it: cordon, emit an event, annotate, drain. Getting back into service is a
documented, gated step. The fault itself is injected and labelled as simulated.

## Acceptance test

One command injects the fault. Within 60 seconds the node has `GPUUnhealthy=True`, is
`SchedulingDisabled` and runs no workload pods, and the events show the controller's
own event with the decoded XID code. Returning the node to service is a separate
command, and it refuses to run if `dcgmi diag` fails.

## What happened

Not run yet.
