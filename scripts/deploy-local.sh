#!/usr/bin/env bash
# Local equivalent of the pipeline's deploy/verify/rollback stages (used by `make release`).
# deploy-local.sh <image-ref> <version> <image-id>
# Images imported with `k3d image import` have no registry digest, so locally the image is
# pinned by tag and the pipeline pins by registry digest. Everything else is identical.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=$1; VERSION=$2; ID=$3
log "local release $VERSION (image id $ID)"
ALLOW_TAG=1 "$ROOT/scripts/deploy.sh" "$IMAGE" "$VERSION"
"$ROOT/scripts/seed.sh"
if ! "$ROOT/scripts/verify.sh" "$VERSION"; then
  "$ROOT/scripts/rollback.sh"
  log "release $VERSION was rolled back automatically"
  exit 1
fi
