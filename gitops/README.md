# GitOps layout

Everything the cluster runs is declared here. The only thing installed by a
person is ArgoCD itself, by `scripts/bootstrap-argocd.sh`, and the last thing
that script does is apply `bootstrap/root-app.yaml`, after which nothing else is
installed by a person again.

```text
gitops/
├── bootstrap/
│   ├── argocd-values.yaml   # values for the one Helm release a human installs
│   └── root-app.yaml        # app of apps, watches gitops/apps
├── apps/                    # one Application per platform component
└── values/                  # the values file for each of those Applications
```

## The two source pattern

Every Application has two sources. The first is the upstream chart, untouched
and pinned to a version. The second is this repository, present only as a `ref`
so that the values file can be referenced as `$values/gitops/values/<name>.yaml`.

The alternative is vendoring upstream charts into this repository, which makes
upgrades a merge exercise, or inlining values into the Application, which puts
YAML that wants reviewing inside YAML that wants leaving alone. This way the
chart stays upstream, the configuration stays reviewable, and a version bump is
a one line diff.

## Sync waves

| Wave | Component | Session |
|---|---|---|
| -1 | local-path-provisioner | B |
| 0 | node-feature-discovery, kube-prometheus-stack | A, B |
| 1 | gpu-operator | A |
| 2 | gpu-observability: GPU alert rules and the Grafana dashboard | B |
| 3 | node-problem-detector, gpu-remediator | C |
| 4 | Tenant namespaces and quotas | D |

Waves 3 and 4 do not exist yet. They are added by the session that builds them,
not before.

Three orderings matter. Storage before anything that asks for a volume.
Node Feature Discovery before the GPU Operator, which selects nodes on NFD's
labels. And kube-prometheus-stack before the GPU Operator, which is why it moved
from wave 1 to wave 0 in Session B: the operator enables a ServiceMonitor for the
DCGM exporter by default, and a ServiceMonitor only exists once the Prometheus
Operator's CRDs do.

> **Waves only order readiness because of a setting.** ArgoCD stopped assessing
> the health of `Application` resources in version 1.8. Without it, waves between
> child Applications in an app of apps only order their *creation*: wave 1 is
> created the moment wave 0 is, not once wave 0 is healthy.
> `bootstrap/argocd-values.yaml` restores the health check that ArgoCD's own
> documentation gives for this. Session A ran without it, which is written up in
> [Findings](../docs/findings.md).

## If you forked this

`bootstrap/root-app.yaml` and every file in `apps/` name this repository by URL
and reference branch `main`. Change both in every one of those files, or ArgoCD will
cheerfully sync someone else's repository into your cluster.
