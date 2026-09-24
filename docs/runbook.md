# Cluster acceptance runbook

!!! info "Status: skeleton"
    The structure and the order of checks are settled. In Session D each check gets
    its command, expected output and failure path, taken from a cluster that ran
    them.

Covers the path from hardware handover to the first production workload. Each check
will have a command, an expected result and what to do when it fails. Work top to
bottom without skipping: a failure high on the list makes everything below it
meaningless.

## Exit criteria

The cluster is accepted when all of the following are true.

| # | Criterion | Check |
|---|---|---|
| 1 | Every GPU the order says exists is present and enumerated | 3 |
| 2 | Driver and container toolkit versions match the fleet standard on every node | 5 |
| 3 | No uncorrectable ECC errors and no pending row remappings | 7 |
| 4 | Every GPU passes DCGM diagnostics at level 3 | 6 |
| 5 | Sustained load holds target clocks without thermal or power throttling | 8 |
| 6 | The scheduler admits and runs a real GPU workload | 10 |
| 7 | Telemetry reaches Prometheus and the dashboard is populated for every GPU | 11 |
| 8 | An alert fires end to end, on purpose, and reaches the on-call path | 12 |
| 9 | A node can be drained and returned to service without operator improvisation | 13 |

## Checks in order

1. Physical and inventory reconciliation
2. Node reachable, OS and kernel at the fleet standard
3. GPU enumeration and PCIe topology
4. Node Feature Discovery labels present
5. Driver and container toolkit version match
6. DCGM diagnostics, levels 1 through 3
7. ECC state and row remapping
8. Thermal and power headroom under sustained load
9. Multi-GPU interconnect bandwidth, where applicable
10. Scheduler admission of a real workload
11. Telemetry pipeline live
12. Deliberate alert firing
13. Drain and return-to-service drill

## XID decode table

Planned for Session D: the codes an operator actually meets, what each one means, and
whether the right response is to retry, drain, or send the hardware back. The split
between application errors and GPU faults will follow the device plugin's list in
[Findings](findings.md#the-device-plugin-already-decides-which-xids-mean-a-broken-gpu).
