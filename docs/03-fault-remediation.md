# Session C: fault detection and remediation

!!! info "Status: not yet run"
    This chapter is written during the session, from output captured live, not
    reconstructed afterwards. Until the session has run, this page states the plan
    and the acceptance test only. Nothing is claimed here that has not happened.

## Scope

node-problem-detector with a custom monitor that reads the kernel log for `NVRM: Xid`
and surfaces a `GPUUnhealthy` node condition. A Python controller on the Kubernetes
client that reacts: cordon, emit an event, annotate, drain. A documented and gated path
back to service. Fault injection, clearly labelled as simulated.

## Acceptance test

One command injects the fault. Within 60 seconds the node carries `GPUUnhealthy=True`,
is `SchedulingDisabled`, has no running workload pods, and the event trail shows the
controller's own event with the decoded XID code. Return to service is a separate
deliberate command that refuses to run if `dcgmi diag` fails.

## What happened

To be filled in during Session C with real captured output.
