# AWS Deployment FAQ

---

## Q: Terraform fails with "secret already scheduled for deletion" — how do I fix it?

**Answer:** AWS Secrets Manager doesn't delete secrets immediately. It schedules them for deletion with a 7–30 day recovery window. During that window the name is reserved and can't be reused, so `terraform apply` fails.

**Important:** The AWS Console hides secrets that are scheduled for deletion — it will show "No secrets" even though the secret still exists in a pending-deletion state. Always use the CLI to check.

**Run (list all secrets including ones pending deletion):**

```bash
aws secretsmanager list-secrets --region <your-region> \
  --include-planned-deletion \
  --query "SecretList[].{Name:Name,DeletedDate:DeletedDate}" \
  --output table
```

The `Name` column is the `--secret-id` value you need. `DeletedDate` will be set for secrets scheduled for deletion.

**Run (force delete the secret):**

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

---

## Q: ECS shows "CannotPullContainerError" and ECR has no images — do I stop the service first?

**Answer:** No. This happens when Terraform creates the infrastructure (ECR repo, ECS service, etc.) but no Docker image has been pushed yet. The ECS service tries to start a container from an image that doesn't exist, so it fails with `CannotPullContainerError: pull image manifest has been retried 7 time(s): failed to resolve ref`.

Just push your code to the `staging` branch or re-run the `deploy-staging.yml` workflow. It will build the image, push it to ECR, update the task definition, and deploy. ECS will automatically replace the failing tasks with healthy ones — no need to stop the service manually.

**Run (re-trigger the deploy workflow):**

```bash
# Option 1: Push a commit to staging
git push origin staging

# Option 2: Re-run the workflow from GitHub Actions UI
# Go to Actions > "Deploy Staging to AWS Fargate" > select the last run > "Re-run all jobs"
```

---

## Q: App shows "could not translate host name CHANGE_ME" — the database secrets are still placeholders?

**Answer:** Terraform seeds Secrets Manager with placeholder values (`CHANGE_ME`). After the initial `terraform apply`, you need to populate the real values once. ECS injects these secrets into the container at runtime, so every future deployment picks them up automatically.

**Do not** add database credentials to workflow files or GitHub Actions variables in plain text — they belong in Secrets Manager where they're encrypted and access-controlled.

**Run (populate the secret with real values):**

```bash
aws secretsmanager put-secret-value \
  --secret-id "adventus-staging/app" \
  --secret-string '{
    "APP_KEY": "base64:your-actual-app-key",
    "DB_HOST": "your-rds-endpoint.ap-southeast-1.rds.amazonaws.com",
    "DB_PORT": "5432",
    "DB_DATABASE": "your-database-name",
    "DB_USERNAME": "your-db-username",
    "DB_PASSWORD": "your-db-password",
    "PASSPORT_PRIVATE_KEY": "your-private-key",
    "PASSPORT_PUBLIC_KEY": "your-public-key"
  }' \
  --region ap-southeast-1
```

**Run (find your RDS endpoint):**

```bash
aws rds describe-db-instances --region ap-southeast-1 \
  --query "DBInstances[].Endpoint.Address" --output text
```

**Run (force ECS to pick up the new secret values):**

```bash
aws ecs update-service \
  --cluster <your-cluster-name> \
  --service <your-service-name> \
  --force-new-deployment \
  --region ap-southeast-1
```

> **Note:** You only need to do this once per environment. After the real values are set, the `lifecycle { ignore_changes = [secret_string] }` block in Terraform ensures they won't be overwritten on future applies.

---

## Q: Where are the secrets pulled from? Can I add them to the GitHub workflow instead?

**Answer:** Secrets are **not** managed by the GitHub workflow. ECS pulls them directly from AWS Secrets Manager every time it starts a container. The flow is:

1. **Terraform** creates the secret in Secrets Manager with `CHANGE_ME` placeholders (`modules/secrets/main.tf`)
2. **You** update the secret in Secrets Manager with real values once (via AWS CLI or Console)
3. **ECS** reads from Secrets Manager at container startup and injects them as environment variables

This is defined in `modules/ecs/main.tf` in the task definition's `secrets` block:

```hcl
secrets = [
  { name = "APP_KEY",              valueFrom = "${var.secrets_arn}:APP_KEY::" },
  { name = "DB_HOST",              valueFrom = "${var.secrets_arn}:DB_HOST::" },
  { name = "DB_PORT",              valueFrom = "${var.secrets_arn}:DB_PORT::" },
  { name = "DB_DATABASE",          valueFrom = "${var.secrets_arn}:DB_DATABASE::" },
  { name = "DB_USERNAME",          valueFrom = "${var.secrets_arn}:DB_USERNAME::" },
  { name = "DB_PASSWORD",          valueFrom = "${var.secrets_arn}:DB_PASSWORD::" },
  { name = "PASSPORT_PRIVATE_KEY", valueFrom = "${var.secrets_arn}:PASSPORT_PRIVATE_KEY::" },
  { name = "PASSPORT_PUBLIC_KEY",  valueFrom = "${var.secrets_arn}:PASSPORT_PUBLIC_KEY::" },
]
```

Non-sensitive config (like `APP_ENV`, `LOG_CHANNEL`, `DB_CONNECTION`) is set in the `environment` block of the same file and is safe to live in Terraform.

**Do not** put credentials in the workflow YAML or GitHub Actions variables. They would be stored in plain text in git. Secrets Manager keeps them encrypted and access-controlled within AWS.

---

## Q: Where do I find the actual values for each Secrets Manager placeholder?

**Answer:** Each value comes from a different source:

| Secret | Value | Source |
|--------|-------|--------|
| `DB_DATABASE` | `adventus` | Hardcoded in `environments/staging/main.tf` |
| `DB_USERNAME` | `adventus_admin` | Hardcoded in `environments/staging/main.tf` |
| `DB_PASSWORD` | *(your password)* | The `TF_VAR_DB_PASSWORD` GitHub Secret you set when configuring the repo |
| `DB_HOST` | *(RDS endpoint)* | Dynamically created by AWS — look it up with the CLI |
| `DB_PORT` | `5432` | Already correct in the placeholder |
| `APP_KEY` | *(generate)* | Generate locally with Artisan |
| `PASSPORT_PRIVATE_KEY` | *(generate)* | Generate locally with Artisan |
| `PASSPORT_PUBLIC_KEY` | *(generate)* | Generate locally with Artisan |

**Run (get the RDS endpoint for DB_HOST):**

```bash
aws rds describe-db-instances --region ap-southeast-1 \
  --query "DBInstances[?DBInstanceIdentifier=='adventus-staging-postgres'].Endpoint.Address" \
  --output text
```

**Run (find DB_PASSWORD — check GitHub repo settings):**

Go to your GitHub repo > Settings > Secrets and variables > Actions > look for `TF_VAR_DB_PASSWORD`. If you no longer know the value, you can reset it on the RDS instance and update both GitHub Secrets and Secrets Manager.

**Run (generate APP_KEY):**

```bash
php artisan key:generate --show
```

**Run (generate Passport keys):**

```bash
php artisan passport:keys
cat storage/oauth-private.key   # PASSPORT_PRIVATE_KEY
cat storage/oauth-public.key    # PASSPORT_PUBLIC_KEY
```

After collecting all values, update them in the Secrets Manager Console (or via CLI) and force a new ECS deployment.

---

## Q: Why is DB_HOST a "CHANGE_ME" placeholder? Where does the actual value come from?

**Answer:** When Terraform creates the RDS instance (`modules/rds/main.tf`), AWS dynamically assigns it a hostname. The RDS module exposes this as an output (`modules/rds/outputs.tf`):

```hcl
output "db_host" {
  description = "RDS hostname (address only)"
  value       = aws_db_instance.this.address
}
```

However, this output is **not wired into the Secrets Manager module** — the secret is seeded with `CHANGE_ME` placeholders independently. That's why you need to look up the RDS endpoint manually and paste it into Secrets Manager.

The RDS instance identifier follows the pattern `{project_name}-postgres` (e.g. `adventus-staging-postgres`), and the hostname AWS assigns will look something like `adventus-staging-postgres.xxxxxxx.ap-southeast-1.rds.amazonaws.com`.

**Run (look up the RDS endpoint):**

```bash
aws rds describe-db-instances --region ap-southeast-1 \
  --query "DBInstances[?DBInstanceIdentifier=='adventus-staging-postgres'].Endpoint.Address" \
  --output text
```

Use the returned value as `DB_HOST` in your Secrets Manager secret.

---

## Q: "password authentication failed" and "no pg_hba.conf entry... no encryption" — what's wrong?

**Answer:** This error has two parts:

**1. Password mismatch** — The `DB_PASSWORD` in Secrets Manager must match the password the RDS instance was originally created with. Updating the password in GitHub Secrets (`TF_VAR_DB_PASSWORD`) only affects future `terraform apply` runs — it does **not** update Secrets Manager or the running ECS containers. You must update the password directly in Secrets Manager.

**2. SSL not enabled** — AWS RDS rejects unencrypted PostgreSQL connections. Laravel's `sslmode` defaults to `prefer`, which can fall back to no encryption. You need `DB_SSLMODE=require` set as an environment variable in the ECS task definition (`modules/ecs/main.tf`):

```hcl
environment = [
  { name = "DB_CONNECTION", value = "pgsql" },
  { name = "DB_SSLMODE", value = "require" },
  # ...other env vars...
]
```

This is a Terraform change, so it requires a push to `staging` with the modified file under `adventus-infrastructure/terraform/**` to trigger the Terraform workflow.

**Also check:** The error may show `Database: postgres` instead of your actual database name. Make sure `DB_DATABASE` in Secrets Manager is set to `adventus`, not `CHANGE_ME` — otherwise Laravel connects to the default `postgres` database.

---

## Q: I updated the password in GitHub Secrets — do I need to rerun Terraform?

**Answer:** It depends on what you're trying to do:

- **If Secrets Manager already has the correct password** (matching what RDS was created with), you don't need to rerun Terraform. The app reads credentials from Secrets Manager, not from GitHub.
- **If you want to change the RDS password itself**, then yes — update `TF_VAR_DB_PASSWORD` in GitHub Secrets and rerun `terraform apply`. Terraform will modify the RDS instance password. Then also update `DB_PASSWORD` in Secrets Manager to match, and force a new ECS deployment.

The key distinction:

| Store | What it controls |
|-------|-----------------|
| **GitHub Secrets** (`TF_VAR_DB_PASSWORD`) | The password Terraform sets on the RDS instance |
| **Secrets Manager** (`DB_PASSWORD`) | The password the running app uses to connect |
| **RDS instance** | The actual password PostgreSQL validates against |

All three must match. Updating one does not automatically update the others.

---

## Q: Terraform is using stale state — can I destroy and recreate everything?

**Answer:** Yes. For staging this is safe since `skip_final_snapshot = true` and there's no production data at risk.

**Run (via GitHub Actions UI — recommended):**

1. Go to Actions > "Terraform: Staging" > "Run workflow" > choose **"destroy"**
2. Wait for it to complete
3. Run the workflow again with **"apply"**

**Run (via CLI, if you have Terraform and AWS credentials locally):**

```bash
cd adventus-infrastructure/terraform/environments/staging

terraform init \
  -backend-config="bucket=<your-tf-state-bucket>" \
  -backend-config="key=adventus/staging/terraform.tfstate" \
  -backend-config="region=ap-southeast-1"

terraform destroy -auto-approve
terraform apply -auto-approve
```

**After recreating, you must:**

1. Populate Secrets Manager with real values again — RDS will have a **new endpoint**, so `DB_HOST` will change
2. Push an image to ECR — push to `staging` or re-run `deploy-staging.yml`, since the ECR repo will be empty

> **Warning:** Destroying deletes the RDS instance and all its data. Staging has `skip_final_snapshot = true`, so there is no automatic backup. If you have data you need, take a manual snapshot first:
> ```bash
> aws rds create-db-snapshot \
>   --db-instance-identifier adventus-staging-postgres \
>   --db-snapshot-identifier adventus-staging-manual-backup \
>   --region ap-southeast-1
> ```
