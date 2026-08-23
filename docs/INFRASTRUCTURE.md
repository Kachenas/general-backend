# Infrastructure Documentation

## Overview

Adventus runs on AWS using a containerized architecture deployed via Terraform and GitHub Actions.

```
                         Internet
                            |
                      [ ALB (public) ]
                       /          \
              [ ECS Fargate ]  [ ECS Fargate ]
              (private subnet)  (private subnet)
                       \          /
                      [ RDS PostgreSQL ]
                       (private subnet)

  Supporting services:
  - ECR (container registry)
  - Secrets Manager (app secrets)
  - CloudWatch (logs)
  - S3 (Terraform state)
```

**Two environments:**

| | Staging | Production |
|---|---|---|
| Branch | `staging` | `main` |
| Region | `ap-southeast-1` | `ap-southeast-1` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Project name | `adventus-staging` | `adventus-production` |

**Tech stack:** Terraform ~> 1.5, GitHub Actions, OIDC authentication (no long-lived AWS keys), ECS Fargate, PostgreSQL 16, Nginx + PHP-FPM (Alpine).

---

## Prerequisites (Manual Setup - One Time)

These steps must be completed manually before any automation will work.

### 1. AWS Account

Ensure you have an AWS account with permissions to create IAM roles, VPCs, ECS clusters, RDS instances, ECR repositories, and Secrets Manager secrets.

### 2. Create S3 Bucket for Terraform State

Create an S3 bucket in your target region to store Terraform state files. Enable versioning.

```bash
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled
```

> **Note:** If your bucket is in a region other than `us-east-1`, add `--create-bucket-configuration LocationConstraint=<region>`.

State file paths used:
- Staging: `adventus/staging/terraform.tfstate`
- Production: `adventus/production/terraform.tfstate`

### 3. Create IAM OIDC Identity Provider for GitHub Actions

This allows GitHub Actions to assume an IAM role without storing AWS access keys.

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 4. Create IAM Role for GitHub Actions

Create an IAM role with a trust policy that allows your GitHub repository to assume it via OIDC.

**Attach the following AWS managed policies to the role:**

| Policy | Purpose |
|---|---|
| `AmazonCloudDirectoryFullAccess` | Cloud directory resources |
| `AmazonEC2ContainerRegistryFullAccess` | Push/pull Docker images to ECR |
| `AmazonRDSFullAccess` | Create and manage RDS instances, subnet groups, and backups |
| `AmazonECS_FullAccess` | Manage ECS clusters, services, and task definitions |
| `AmazonECSTaskExecutionRolePolicy` | Allow ECS tasks to pull images and write logs |
| `AmazonS3FullAccess` | Terraform state storage in S3 |
| `AmazonVPCFullAccess` | Create and manage VPC, subnets, NAT gateways, security groups |
| `CloudWatchLogsFullAccess` | Create and manage CloudWatch log groups |
| `ElasticLoadBalancingFullAccess` | Create and manage ALB, target groups, listeners |
| `IAMFullAccess` | Create ECS task execution and task roles |
| `SecretsManagerReadWrite` | Create and manage Secrets Manager secrets |

> **Note:** These are broad managed policies suitable for a deployment role. For production, consider scoping down to least-privilege custom policies.

**Trust policy example** (replace `YOUR_GITHUB_ORG/YOUR_REPO`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

> **Tip:** You may need separate roles per environment if you want to restrict which branches can assume which role. The `sub` claim includes the branch (e.g., `repo:org/repo:ref:refs/heads/staging`).

### 5. Create GitHub Environments

In your GitHub repository settings, create two environments:
- `staging`
- `production`

These are referenced by the workflow files and scope variables/secrets per environment.

---

## GitHub Configuration

Each environment (`staging` and `production`) needs the following variables and secrets configured in GitHub repository settings under **Settings > Environments**.

### Variables (non-sensitive, per environment)

| Variable | Description | Example (staging) |
|---|---|---|
| `AWS_ROLE_ARN` | ARN of the IAM role for OIDC authentication | `arn:aws:iam::123456789:role/github-actions-staging` |
| `AWS_REGION` | AWS region for this environment | `ap-southeast-1` |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state | `your-terraform-state-bucket` |
| `ECR_REPOSITORY` | ECR repository name | `adventus-staging` |
| `ECS_CLUSTER` | ECS cluster name | `adventus-staging` |
| `ECS_SERVICE` | ECS service name | `adventus-staging` |
| `ECS_TASK_DEFINITION` | ECS task definition family name | `adventus-staging` |
| `ECS_CONTAINER_NAME` | Container name in the task definition | `adventus-staging` |

> **Note:** The `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION`, and `ECS_CONTAINER_NAME` values are outputs from the Terraform apply step. Run Terraform first, then populate these variables from the outputs.

### Secrets (sensitive, per environment)

| Secret | Description |
|---|---|
| `TF_VAR_DB_PASSWORD` | Master password for the RDS PostgreSQL database. Must be at least 8 characters and cannot contain `/`, `"`, `@`, or spaces |

---

## Deployment Order (Step-by-Step)

Follow these steps in order when setting up a new environment from scratch.

### Step 1: Complete Prerequisites

Complete all manual prerequisites above (AWS account, S3 bucket, OIDC provider, IAM role, GitHub environments).

### Step 2: Configure GitHub Environment - Initial Variables

Set the following variables that are known before Terraform runs:

- `AWS_ROLE_ARN` - the IAM role ARN you created
- `AWS_REGION` - the target region
- `TF_STATE_BUCKET` - your S3 bucket name

Set the following secret:

- `TF_VAR_DB_PASSWORD` - choose a strong password for the database

### Step 3: Run Terraform Workflow

Trigger the Terraform workflow to create all infrastructure:

- **Staging:** Push Terraform changes to the `staging` branch, or use the `workflow_dispatch` trigger in GitHub Actions
- **Production:** Push Terraform changes to the `main` branch, or use the `workflow_dispatch` trigger

Terraform creates: VPC, subnets, NAT gateway, ALB, security groups, ECR repository, Secrets Manager secret, IAM roles, RDS instance, ECS cluster, task definition, and ECS service.

### Step 4: Populate Remaining GitHub Variables

After Terraform completes, retrieve the outputs and set the remaining GitHub variables:

```bash
# From the Terraform output:
# ecr_repository_url  -> extract repository name for ECR_REPOSITORY
# ecs_cluster_name    -> ECS_CLUSTER
# ecs_service_name    -> ECS_SERVICE
# ecs_task_definition_family -> ECS_TASK_DEFINITION
# ecs_container_name  -> ECS_CONTAINER_NAME
```

### Step 5: Populate Secrets Manager

After Terraform creates the Secrets Manager secret (with placeholder values), update it with real values. The secret is named `{project_name}/app` (e.g., `adventus-staging/app`).

See the [Secrets Manager Values](#post-deployment-secrets-manager-values) section for the full list of keys and how to generate each value.

### Step 6: Push Application Code to Deploy

- **Staging:** Push to the `staging` branch
- **Production:** Push to the `main` branch

The deploy workflow will: lint, test, build the Docker image, push to ECR, update the ECS task definition, and deploy.

### Step 7: Verify

Check the ALB DNS name (from Terraform output `alb_dns_name`) and confirm the `/up` health check endpoint returns `200`.

```bash
curl http://<alb_dns_name>/up
```

---

## Infrastructure Components Reference

All Terraform modules are located in `adventus-infrastructure/terraform/modules/`.

| Module | Resources Created |
|---|---|
| **networking** | VPC, internet gateway, 2 public subnets, 2 private subnets, NAT gateway (single), route tables, ALB security group (HTTP inbound), ECS security group (HTTP from ALB only) |
| **ecr** | ECR repository with image scanning enabled. Lifecycle policy: untagged images expire after 7 days, keep last 10 tagged images |
| **secrets** | Secrets Manager secret with placeholder JSON containing: `APP_KEY`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `PASSPORT_PRIVATE_KEY`, `PASSPORT_PUBLIC_KEY`. Lifecycle ignores manual secret updates |
| **iam** | ECS task execution role (ECR pull + Secrets Manager read), ECS task role (application runtime, minimal permissions) |
| **alb** | Public-facing Application Load Balancer, target group (IP-based for Fargate, health check on `/up`), HTTP listener on port 80 |
| **rds** | PostgreSQL 16 instance in private subnets, encrypted storage (gp3), security group allowing port 5432 from ECS only |
| **ecs** | ECS cluster, Fargate task definition (Nginx + PHP-FPM container), ECS service with deployment circuit breaker and rollback, CloudWatch log group |

---

## CI/CD Workflows

All workflows are in `.github/workflows/`.

### `terraform-staging.yml` - Terraform: Staging

| | |
|---|---|
| **Trigger** | Push to `staging` (paths: `adventus-infrastructure/terraform/**`), PR to `staging` (same paths), `workflow_dispatch` (apply or destroy) |
| **What it does** | Runs `terraform plan` on every trigger. On push to `staging` or `workflow_dispatch`, also runs `terraform apply` (or `terraform destroy` if selected). Comments the plan output on PRs |
| **Concurrency** | `terraform-staging` group, no cancel-in-progress (state locking via concurrency group) |
| **Destroy support** | Yes, via `workflow_dispatch` with `action: destroy` |

### `terraform-production.yml` - Terraform: Production

| | |
|---|---|
| **Trigger** | Push to `main` (paths: `adventus-infrastructure/terraform/**`), PR to `main` (same paths), `workflow_dispatch` |
| **What it does** | Runs `terraform plan` on every trigger. On push to `main` or `workflow_dispatch`, also runs `terraform apply`. Comments the plan output on PRs |
| **Concurrency** | `terraform-production` group, no cancel-in-progress |
| **Destroy support** | No (apply only) |

### `deploy-staging.yml` - Deploy Staging to AWS Fargate

| | |
|---|---|
| **Trigger** | Push to `staging` |
| **What it does** | 1. Lint (Pint) 2. Test (PHPUnit) 3. Build Docker image and push to ECR (tagged with commit SHA + `latest`) 4. Update ECS task definition with new image 5. Deploy to ECS and wait for service stability |
| **Concurrency** | `deploy-${{ github.ref }}`, cancels in-progress runs |

### `deploy-production.yml` - Deploy Production

| | |
|---|---|
| **Trigger** | Push to `main` |
| **What it does** | Same pipeline as staging: Lint, Test, Build & Push to ECR, Deploy to ECS |
| **Concurrency** | None configured (runs independently) |

---

## Post-Deployment: Secrets Manager Values

After Terraform creates the Secrets Manager secret (named `{project_name}/app`, e.g. `adventus-staging/app`), it contains placeholder values (`CHANGE_ME`). You must update it with real values before the application will work.

### Generating Each Value

**APP_KEY:**

```bash
php artisan key:generate --show
# Output: base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**DB_HOST:**

Find the RDS endpoint using one of these methods:

1. **GitHub Actions logs (easiest):** Go to the **Actions** tab in your GitHub repo, open the latest `Terraform: Staging` (or Production) workflow run, click the **Terraform Apply** step, and scroll to the bottom. The outputs are printed at the end, including `rds_host`.

2. **AWS CLI:**
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier adventus-staging-postgres \
     --region ap-southeast-1 \
     --query 'DBInstances[0].Endpoint.Address' \
     --output text
   ```

3. **AWS Console:** Go to **RDS > Databases > adventus-staging-postgres** and copy the **Endpoint** value under **Connectivity & security**.

**DB_PORT / DB_DATABASE / DB_USERNAME:**

These are fixed values set in the Terraform RDS module:
- `DB_PORT`: `5432`
- `DB_DATABASE`: `adventus`
- `DB_USERNAME`: `adventus_admin`

**DB_PASSWORD:**

The same password you set as the `TF_VAR_DB_PASSWORD` GitHub secret.

**PASSPORT_PRIVATE_KEY / PASSPORT_PUBLIC_KEY:**

```bash
php artisan passport:keys
# This generates two files:
#   storage/oauth-private.key
#   storage/oauth-public.key
# Copy the full contents of each file (including the BEGIN/END lines)
```

### Updating the Secret

```bash
aws secretsmanager put-secret-value \
  --secret-id "adventus-staging/app" \
  --region ap-southeast-1 \
  --secret-string '{
    "APP_KEY": "base64:...",
    "DB_HOST": "your-rds-endpoint.rds.amazonaws.com",
    "DB_PORT": "5432",
    "DB_DATABASE": "adventus",
    "DB_USERNAME": "adventus_admin",
    "DB_PASSWORD": "your-db-password",
    "PASSPORT_PRIVATE_KEY": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
    "PASSPORT_PUBLIC_KEY": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
  }'
```

> **Note:** For production, use `--secret-id "adventus-production/app"`.

### Restarting ECS After Updating Secrets

ECS tasks read secrets at launch time. After updating Secrets Manager, force a new deployment to pick up the changes:

```bash
aws ecs update-service \
  --cluster adventus-staging \
  --service adventus-staging \
  --force-new-deployment \
  --region ap-southeast-1
```

> **Important:** The ECS task definition references these secrets individually via `secretsmanager:{secret_arn}:KEY::`. Terraform sets up these references automatically - you only need to populate the values.

### Common Mistakes

- **`DB_USERNAME` must be `adventus_admin`** — not `adventus_admin_staging` or any other variation. This is the master username Terraform used when creating the RDS instance (defined in the RDS module).
- **`DB_DATABASE` must be `adventus`** — not `postgres` or the project name. This is the database name Terraform created on the RDS instance.
- **`DB_PASSWORD` must match `TF_VAR_DB_PASSWORD` exactly** — this is the master password Terraform set on the RDS instance. If they don't match, you'll get `password authentication failed`.

---

## Environment Differences

| Setting | Staging | Production |
|---|---|---|
| Region | `ap-southeast-1` | `ap-southeast-1` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| ECS CPU / Memory | 256 / 512 MB | 512 / 1024 MB |
| ECS Desired Tasks | 1 | 2 |
| RDS Instance Class | `db.t3.micro` | `db.t3.small` |
| RDS Storage | 20 GB (gp3, encrypted) | 20 GB (gp3, encrypted) |
| RDS Backups | Disabled (0 days) | 7 days retention |
| RDS Final Snapshot | Skipped | Kept |
| Migrations | Auto (`RUN_MIGRATIONS=true`) | Manual (`RUN_MIGRATIONS=false`) |
| CloudWatch Log Retention | 14 days | 90 days |
| Container Insights | Disabled | Enabled |
| Terraform Destroy | Supported via workflow_dispatch | Not supported |

---

## Troubleshooting

### ECS Service Not Starting / Tasks Keep Restarting

1. **Check CloudWatch logs:** Look at `/ecs/adventus-{env}` log group for container startup errors
2. **Secrets Manager:** Ensure all secret values are populated (not placeholders). Missing `APP_KEY` or `DB_HOST` will cause the container to fail
3. **Database connectivity:** The ECS tasks run in private subnets and connect to RDS via the security group. Verify the RDS security group allows inbound on port 5432 from the ECS security group
4. **Deployment circuit breaker:** ECS has a deployment circuit breaker enabled with rollback. If a deploy fails health checks, it will automatically roll back to the previous task definition

### Database Connection Errors

- **`password authentication failed`**: The `DB_PASSWORD` in Secrets Manager doesn't match the `TF_VAR_DB_PASSWORD` used when Terraform created the RDS instance. They must be identical.
- **`user "adventus_admin_staging" does not exist`**: Wrong `DB_USERNAME` in Secrets Manager. The correct value is `adventus_admin` (set by the Terraform RDS module, same for both environments).
- **Connecting to database `postgres` instead of `adventus`**: Wrong `DB_DATABASE` in Secrets Manager. The correct value is `adventus`.
- **`CHANGE_ME` errors**: Secrets Manager still has placeholder values. Update all keys with real values and force a new ECS deployment.

### Health Check Failing (`/up` endpoint)

1. The ALB health check hits `GET /up` on port 80 with expected response `200`
2. Ensure the Laravel app is configured with `APP_URL` pointing to the ALB DNS name (set automatically by ECS task definition)
3. Check that Nginx is running inside the container (supervisord manages both Nginx and PHP-FPM)
4. The health check has a 20-second start period to allow the container to boot

### Terraform State Issues

- State is stored in S3 without DynamoDB locking. Concurrent runs are prevented via GitHub Actions concurrency groups
- If state becomes inconsistent, ensure no Terraform workflows are running, then run `terraform init` and `terraform plan` locally to inspect

### Docker Build Failures

- The Dockerfile uses `php:8.4-fpm-alpine` as the base image
- Composer dependencies are installed during build (`composer install --no-dev --optimize-autoloader`)
- If a build fails, check for new PHP extensions required by dependencies

### Database Migrations (Production)

- Production has `RUN_MIGRATIONS=false` by default. Migrations do not run automatically on deploy
- To run migrations, either:
  - Use ECS Exec to access a running container and run `php artisan migrate`
  - Temporarily set `RUN_MIGRATIONS=true` in the Secrets Manager or task definition environment variables, deploy, then revert

### Accessing the Application

- The application is available at the ALB DNS name (output: `alb_dns_name`)
- HTTPS is not configured by default. The ALB listener and security group have HTTPS (443) commented out in the Terraform modules, ready for when you add an ACM certificate
