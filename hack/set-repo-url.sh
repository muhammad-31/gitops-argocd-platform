#!/usr/bin/env bash
# Point every Argo CD manifest at your fork.
# Usage: hack/set-repo-url.sh https://github.com/<you>/gitops-argocd-platform.git
set -euo pipefail

new="${1:?usage: $0 <git-repo-url>}"
old="https://github.com/muhammad-31/gitops-argocd-platform.git"

grep -rl --include='*.yaml' "$old" bootstrap clusters | while read -r file; do
  sed -i.bak "s#${old}#${new}#g" "$file" && rm -f "$file.bak"
  echo "updated $file"
done
