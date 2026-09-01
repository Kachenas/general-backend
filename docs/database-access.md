# Database Access (RDS via Bastion)

## Overview

RDS PostgreSQL is never reachable from the internet — `publicly_accessible = false`, and its security group only allows inbound port 5432 from two sources: the ECS tasks and a dedicated bastion EC2 instance (`modules/security-groups/main.tf`).

To inspect real data with a GUI client (TablePlus, DBeaver, Postico, pgAdmin), you tunnel through the bastion using AWS Systems Manager Session Manager. The bastion has:

- No public IP
- No SSH key
- No inbound security group rules at all

It's reachable exclusively through `aws ssm start-session`, authenticated by your own IAM identity — not a shared key.

```
  Your laptop --(SSM, encrypted)--> [ Bastion ] --(SG rule)--> [ RDS PostgreSQL ]
                                    (private subnet)             (private subnet)
```

> **Wrong tool, common mistake:** RDS here is PostgreSQL, not MySQL. MySQL Workbench cannot connect to it regardless of credentials — use a Postgres-capable client.

## One-Time Setup (Per Developer)

### 1. Get added to the developers group

Someone with Terraform access adds your IAM username to `developer_user_names` in the environment's `terraform.tfvars` (or applies via `TF_VAR_developer_user_names`) and runs `terraform apply`. This is managed by `modules/iam-developers` — it grants exactly one capability: `ssm:StartSession` against the bastion instance, nothing else (no other EC2 access, no direct RDS credentials in this policy).

> If your org uses AWS Identity Center instead of IAM users, attach the `developer_ssm_policy_arn` Terraform output to your permission set instead of using `developer_user_names`.

### 2. Install the AWS CLI and Session Manager plugin

```bash
brew install awscli
brew install --cask session-manager-plugin
```

### 3. Install a PostgreSQL GUI client

Any of: [TablePlus](https://tableplus.com/), [DBeaver](https://dbeaver.io/) (free), [Postico](https://eggerapps.at/postico2/) (Mac), [pgAdmin 4](https://www.pgadmin.org/).

## Connecting

### 1. Find the bastion instance ID

```bash
cd adventus-infrastructure/terraform/environments/staging   # or production
terraform output bastion_instance_id
```

Or in the AWS Console: **EC2 > Instances >** `adventus-staging-bastion` (or `adventus-production-bastion`).

### 2. Open the tunnel

```bash
aws ssm start-session \
  --target <bastion-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<rds-endpoint>"],"portNumber":["5432"],"localPortNumber":["5432"]}' \
  --region ap-southeast-1
```

Find `<rds-endpoint>` via `terraform output rds_host`, or **RDS Console > Databases >** `adventus-{env}-postgres` **> Connectivity & security > Endpoint**.

Leave this command running — it's your tunnel. Closing the terminal closes the session.

### 3. Connect your GUI client

| Field | Value |
|---|---|
| Host | `localhost` |
| Port | `5432` |
| Database | `adventus` |
| User | `adventus_admin` |
| Password | The real value from Secrets Manager (`{project_name}/app` secret, `DB_PASSWORD` key) — see [AWS-FAQ.md](./AWS-FAQ.md) for how to retrieve it |
| SSL mode | `prefer` is fine — traffic is already encrypted inside the SSM tunnel |

## Troubleshooting

**`TargetNotConnected` error from `aws ssm start-session`** — The bastion instance may still be booting (SSM agent takes ~1-2 minutes after launch to register), or your IAM identity isn't in the developers group / policy isn't attached yet. Confirm with:

```bash
aws ssm describe-instance-information --region ap-southeast-1 \
  --query "InstanceInformationList[].{ID:InstanceId,PingStatus:PingStatus}"
```

**`AccessDeniedException` on `ssm:StartSession`** — Your IAM user isn't a member of `{project_name}-developers`, or you're targeting an instance other than the bastion (the policy only allows the bastion's specific ARN). Ask whoever manages Terraform to add your username to `developer_user_names`.

**Connection refused from the GUI client** — The SSM tunnel isn't open, or it dropped. Re-run the `aws ssm start-session` command in a dedicated terminal and leave it running while you use the GUI client.

**MySQL Workbench won't connect** — Expected; this is a PostgreSQL instance. Use a Postgres-capable client instead.

## Cost and Cleanup

The bastion is a real, permanently-running `t3.micro` EC2 instance (a few dollars/month) — it's meant to stay up as standing infrastructure for developer access, not a one-off resource you tear down after use. If you want to remove it entirely (e.g. decommissioning an environment), remove the `module "bastion"` and `module "iam_developers"` blocks from that environment's `main.tf` and run `terraform apply`.

## Related

- [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) — full architecture and module reference
- [AWS-FAQ.md](./AWS-FAQ.md) — Secrets Manager values, RDS endpoint lookup, common connection errors
