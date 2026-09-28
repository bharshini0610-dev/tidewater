# AI usage

**Tool:** an AI coding assistant with shell access, used as a pair programmer.

**Where it was used.** Most of this repository was drafted by the AI from my instructions and the
brief. That includes the reconstruction of the inherited repo (no repository or evidence bundle was
supplied), the application operability changes and tests, Kubernetes manifests, scripts, the
GitHub Actions pipeline, the Terraform modules, and the first drafts of every document in `docs/`.

**How the output was checked (by running it, not by reading it):**
* unit tests against a real Postgres + Redis, and a local end-to-end run (`docs/evidence/local-e2e-idempotency.txt`);
* `terraform fmt/validate`, `tflint` and `checkov` until clean (`docs/evidence/terraform-checks-local.txt`);
* `kubeconform`, `shellcheck`, `ruff`; the full pipeline on GitHub Actions (evidence branch).

**Things that were wrong in the first attempt and had to be corrected** (found by those runs):
* JSON log handler bound `sys.stdout` at import time, so the request-id test captured nothing → handler now resolves stdout per record.
* Checkov: the WAF used dynamic blocks (the static check couldn't see the Log4j rule set), and the
  ALB/WAF association crossed a module boundary → rules written out and WAF moved into the ALB module.
  Adding `AnonymousIpList` naively would have blocked merchants calling from cloud hosting, so that sub-rule is set to *count*.
* Redis replication group used the default parameter group; for a job queue `noeviction` is required.
* ECS `deployment_maximum_percent 200` would double connections during deploys; lowered to 150 and added to the budget formula.
* Shell scripts: `set -e` aborted verification at the first failed curl, so later checks were never reported → verification disables `-e` and always reports every check.
* Helm `--set` with a JSON log format broke on commas → moved to a values file.
* *(pipeline iterations — see git history for `fix(ci)` commits)*

**What I reviewed / changed myself:** _<fill in honestly before submitting: what you read line by
line, what you changed, what you disagree with>_

**Limits I am aware of.** The RCA is built from the brief and a reconstruction, not from the real
evidence bundle; the claims marked **[to confirm]** are hypotheses. The cost figures are list-price
estimates that were not checked in the AWS Pricing Calculator.
