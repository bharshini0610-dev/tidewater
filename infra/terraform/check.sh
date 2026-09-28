#!/usr/bin/env bash
# Terraform proof required by the brief: fmt -check, validate (every root), tflint, checkov.
# Nothing is applied. Usage: infra/terraform/check.sh   (TF=tofu to use OpenTofu locally)
set -euo pipefail
cd "$(dirname "$0")"
TF=${TF:-terraform}
echo "== $TF fmt -check -recursive"
$TF fmt -check -recursive -diff
for root in bootstrap envs/staging envs/prod; do
  echo "== $TF validate ($root)"
  (cd "$root" && $TF init -backend=false -input=false >/dev/null && $TF validate)
done
echo "== tflint (recursive, aws ruleset)"
tflint --init >/dev/null
tflint --recursive --config "$PWD/.tflint.hcl" --format compact
export BC_SKIP_MAPPING=TRUE
for root in bootstrap envs/staging envs/prod; do
  echo "== checkov ($root; suppressions and their justifications: $root/.checkov.yaml + inline #checkov:skip)"
  checkov -d "$root" --framework terraform --quiet --compact --config-file "$root/.checkov.yaml"
done
