# web-app Helm chart

Generic chart for a stateless HTTP service. The defaults are the secure ones,
so a team only overrides what is specific to its service.

| Concern | Default |
|---|---|
| Security | non-root UID 10001, read-only root filesystem, all capabilities dropped, RuntimeDefault seccomp, no service-account token. Passes the Kubernetes *restricted* Pod Security Standard. |
| Availability | 2 replicas, `maxUnavailable: 0` rollouts, PodDisruptionBudget, spread across zones and nodes, `preStop` sleep so in-flight requests finish. |
| Health | separate liveness and readiness probes; optional startup probe. |
| Resources | CPU and memory requests, memory limit, no CPU limit (avoids throttling). |
| Network | NetworkPolicy allowing only the gateway namespace in, DNS out. |
| Exposure | Gateway API `HTTPRoute` (or classic `Ingress`). |
| Scaling | optional HPA on CPU and memory with a slow scale-down. |
| Guard rails | `values.schema.json` rejects unknown keys, `:latest`, missing requests and malformed image names at `helm install` time. |

## Usage

```bash
helm install shop charts/web-app \
  --namespace shop --create-namespace \
  --set image.repository=ghcr.io/acme/shop \
  --set image.tag=1.4.2 \
  --set containerPort=8080
helm test shop -n shop
```

## Key values

| Value | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/stefanprodan/podinfo` | Fully qualified image repository |
| `image.tag` | chart `appVersion` | Image tag (`latest` is rejected) |
| `image.digest` | `""` | `sha256:...`; wins over the tag |
| `containerPort` | `9898` | Port the app listens on |
| `replicaCount` | `2` | Used when autoscaling is off |
| `env` / `envFrom` | `{}` / `[]` | Environment variables / ConfigMap and Secret refs |
| `probes.liveness.path` | `/healthz` | Liveness endpoint |
| `probes.readiness.path` | `/readyz` | Readiness endpoint |
| `probes.startup.enabled` | `false` | Startup probe for slow starters |
| `resources` | 50m / 64Mi, limit 128Mi | Requests and memory limit |
| `autoscaling.enabled` | `false` | HorizontalPodAutoscaler |
| `podDisruptionBudget.maxUnavailable` | `1` | Rendered when more than one replica |
| `serviceAccount.annotations` | `{}` | e.g. IRSA / Workload Identity role |
| `writableDirs` | `[/tmp]` | emptyDir mounts for a read-only root filesystem |
| `networkPolicy.ingressFrom` | gateway namespace | Who may call the service |
| `networkPolicy.egress` | `[]` | Extra egress rules (databases, APIs) |
| `httpRoute.enabled` | `false` | Expose through a Gateway API Gateway |
| `httpRoute.hostnames` | `[]` | Hostnames for the route |
| `ingress.enabled` | `false` | Classic Ingress instead of HTTPRoute |

See [`values.yaml`](values.yaml) for everything else.
