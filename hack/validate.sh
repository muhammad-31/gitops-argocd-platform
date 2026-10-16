#!/usr/bin/env bash
# Render everything Argo CD would deploy and validate it offline:
#   1. kustomize overlays and the web-app chart for every app x environment
#   2. Kubernetes + CRD schemas (kubeconform)
#   3. Kyverno policy unit tests
#   4. rendered apps against the prod (Deny) policies, so a change that would
#      be rejected by the cluster fails in the pull request instead.
set -euo pipefail

K8S_VERSION="${K8S_VERSION:-1.35.0}"
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
ENVIRONMENTS=(dev prod)

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "==> kustomize build"
for dir in clusters/* platform/*/overlays/* policies/overlays/*; do
  kustomize build "$dir" > "$out/kustomize_${dir//\//_}.yaml"
  echo "    $dir"
done

echo "==> helm template (charts/web-app x apps x environments)"
helm lint charts/web-app --strict --quiet
for app_dir in apps/*/; do
  app="$(basename "$app_dir")"
  for env in "${ENVIRONMENTS[@]}"; do
    args=(-f "$app_dir/values.yaml")
    [[ -f "$app_dir/values-$env.yaml" ]] && args+=(-f "$app_dir/values-$env.yaml")
    helm template "$app" charts/web-app --namespace "$app" "${args[@]}" > "$out/app_${app}_${env}.yaml"
    echo "    $app ($env)"
  done
done

echo "==> kubeconform (Kubernetes $K8S_VERSION + CRD catalog)"
kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
  -schema-location default -schema-location "$CRD_SCHEMAS" \
  "$out"/*.yaml

echo "==> kyverno test (policy unit tests)"
kyverno test policies/tests --warnings-as-errors

echo "==> kyverno apply (rendered apps vs prod policies)"
values="$out/kyverno-values.yaml"
{
  echo "apiVersion: cli.kyverno.io/v1alpha1"
  echo "kind: Values"
  echo "namespaceSelector:"
  for app_dir in apps/*/; do
    printf '  - name: %s\n    labels:\n      workload-tier: apps\n' "$(basename "$app_dir")"
  done
} > "$values"

for rendered in "$out"/app_*.yaml; do
  result="$(kyverno apply "$out/kustomize_policies_overlays_prod.yaml" \
    --resource "$rendered" --values-file "$values" 2>&1)" || true
  summary="$(grep -E '^pass:' <<<"$result")"
  echo "    $(basename "$rendered" .yaml): $summary"
  if ! grep -qE 'fail: 0, warn: 0, error: 0' <<<"$summary" || grep -qE '^pass: 0,' <<<"$summary"; then
    echo "$result"
    exit 1
  fi
done

echo "All checks passed."
