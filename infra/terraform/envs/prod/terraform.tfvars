# Non-secret inputs only. The pipeline overrides `image` with the verified digest.
app_version     = "1.9.0"
image           = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/settle-api-prod@sha256:0000000000000000000000000000000000000000000000000000000000000000"
certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
bank_url        = "https://bank.example.com"
