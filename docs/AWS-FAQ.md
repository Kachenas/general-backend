# AWS Deployment FAQ

---

## Q: Terraform fails with "secret already scheduled for deletion" — how do I fix it?

**Answer:** AWS Secrets Manager doesn't delete secrets immediately. It schedules them for deletion with a 7–30 day recovery window. During that window the name is reserved and can't be reused, so `terraform apply` fails.

**Run:**

```bash
aws secretsmanager delete-secret \
  --secret-id "<your-secret-name>" \
  --force-delete-without-recovery \
  --region <your-region>
```

Then re-run `terraform apply`. No need to destroy and recreate other infrastructure.

**Prevention:** Add `recovery_window_in_days = 0` to the secret resource so Terraform deletes it immediately:

```hcl
resource "aws_secretsmanager_secret" "this" {
  name                    = var.secret_name
  description             = "Application secrets for ${var.secret_name}"
  recovery_window_in_days = 0

  tags = var.tags
}
```

> **Note:** This means deleted secrets are unrecoverable. Suitable for staging/dev — consider keeping the default recovery window for production.

---

## Q: Does the Terraform workflow run every time I push code? What if I only changed application code and not infrastructure?

**Answer:** No. The Terraform and application deploy workflows are separate and trigger independently.

- **Application code changes** — Pushing to `staging` triggers `deploy-staging.yml`, which lints, tests, builds a Docker image, pushes to ECR, and deploys to ECS. Terraform is not touched.
- **Infrastructure changes** — Pushing to `staging` with changes under `adventus-infrastructure/terraform/**` triggers `terraform-staging.yml`, which runs `terraform plan` then `terraform apply`. This only fires when Terraform files are modified.
- **Both at once** — If a push changes both app code and Terraform files, both workflows run independently.

**Run (manual Terraform apply):**

```bash
# Via GitHub Actions UI:
# Go to Actions > "Terraform: Staging" > "Run workflow" > choose "apply" or "destroy"
```

**Run (check which workflows would trigger for your changes):**

```bash
# See what files changed vs the staging branch
git diff --name-only staging
```

If the output only shows files outside `adventus-infrastructure/terraform/`, only the app deploy workflow will run.
