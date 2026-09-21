# Session B: observability and XID alerting

!!! info "Status: not yet run"
    This chapter is written during the session, from output captured live, not
    reconstructed afterwards. Until the session has run, this page states the plan
    and the acceptance test only. Nothing is claimed here that has not happened.

## Scope

DCGM exporter scraped by Prometheus. A Grafana dashboard covering SM utilisation,
framebuffer, temperature, power, ECC counters, clock event reasons and XID. Prometheus
alert rules on critical XID codes and on utilisation collapse during a running job.

## Acceptance test

A dashboard screenshot with live data across all of those signals on one screen, and
at least one alert observed moving to firing. The alert that fires here is driven by a
real condition, a genuinely killed job, not an injected one.

## What happened

To be filled in during Session B with real captured output.
