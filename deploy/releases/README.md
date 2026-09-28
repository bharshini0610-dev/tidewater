`production.json` is the production pointer: the exact image digest that last passed
post-deploy verification on `main`. The pipeline writes it (commit `release: promote ...`)
and uses it to seed each ephemeral cluster with "what is running in production" before
deploying a candidate, so a failed candidate has something real to roll back to.
Rolling back production manually = revert the commit that changed this file (see RUNBOOK).
