# GitOps layout

Everything the cluster runs is declared here. The one thing a person installs is
ArgoCD, through `scripts/bootstrap-argocd.sh`. That script's last step applies
`bootstrap/root-app.yaml`, and from then on ArgoCD installs everything else.

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

I didn't want to vendor upstream charts, which turns every upgrade into a merge,
or to inline values in the Application, which buries the YAML you review inside
YAML you shouldn't touch. This way the chart stays upstream, the configuration is
easy to review, and a version bump is a one-line diff.

## Sync waves

| Wave | Component | Session |
|---|---|---|
| -1 | local-path-provisioner | B |
| 0 | node-feature-discovery, kube-prometheus-stack | A, B |
| 1 | gpu-operator | A |
| 2 | gpu-observability: GPU alert rules and the Grafana dashboard | B |
| 3 | node-problem-detector, gpu-remediator | C |
| 4 | Tenant namespaces and quotas | D |

Waves 3 and 4 don't exist yet; each gets added by the session that builds it.

Three orderings matter:

- storage before anything that asks for a volume;
- Node Feature Discovery before the GPU Operator, which selects nodes on NFD's labels;
- kube-prometheus-stack before the GPU Operator. That's why it moved from wave 1 to
  wave 0 in Session B: the operator creates a ServiceMonitor for the DCGM exporter by
  default, and that can't exist until the Prometheus Operator's CRDs do.

> **The waves only wait for readiness because of one setting.** ArgoCD stopped
> assessing the health of `Application` resources in version 1.8. Without that
> check, waves between child Applications in an app of apps only order their
> *creation*: wave 1 gets created as soon as wave 0 does, healthy or not.
> `bootstrap/argocd-values.yaml` restores the health check from ArgoCD's own
> documentation. Session A ran without it; see [Findings](../docs/findings.md).

## If you forked this

`bootstrap/root-app.yaml` and every file in `apps/` point at this repository's URL
and branch `main`. Change both in every one of those files, or ArgoCD will happily
sync my repository into your cluster.
