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
| 0 | node-feature-discovery | A |
| 1 | gpu-operator | A |
| 1 | kube-prometheus-stack | B |
| 2 | Grafana dashboards, Prometheus alert rules | B |
| 3 | node-problem-detector, gpu-remediator | C |
| 4 | Tenant namespaces and quotas | D |

Waves 2 to 4 do not exist yet. They are added by the session that builds them,
not before.

The ordering that matters today is 0 before 1: the GPU Operator selects nodes on
labels that Node Feature Discovery produces, so an operator that syncs first
finds nothing to do and stays that way.

## If you forked this

`bootstrap/root-app.yaml` and every file in `apps/` name this repository by URL
and reference branch `main`. Change both in all three places, or ArgoCD will
cheerfully sync someone else's repository into your cluster.
