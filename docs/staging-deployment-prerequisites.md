# Staging Deployment Prerequisites

This document covers the one-time AWS and GitHub setup required before the staging CI/CD pipeline (`.github/workflows/staging.yml`) can run.

## AWS Setup

### 1. Create an ECR Repository

```bash
aws ecr create-repository \
  --repository-name backend-staging \
  --region <your-region>
```

### 2. Create an ECS Cluster and Service

Create a Fargate cluster, task definition, and service. The task definition should:

- Use the `awsvpc` network mode
- Define a single container (note the container name — you'll need it for `ECS_CONTAINER_NAME`)
- Map port 80
- Set environment variables your app needs (`APP_KEY`, `DB_HOST`, `DB_PASSWORD`, etc.)
- Use an execution role with ECR pull permissions
- Configure log driver as `awslogs` so Fargate sends container logs to CloudWatch

### 3. Create an IAM OIDC Identity Provider

This allows GitHub Actions to authenticate with AWS without static access keys.

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 4. Create an IAM Role for GitHub Actions

Create a role with the following trust policy (replace `<ACCOUNT_ID>`, `<OWNER>`, and `<REPO>`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:ref:refs/heads/staging"
        }
      }
    }
  ]
}
```

### 5. Attach Permissions to the Role

The role needs two permission sets:

**ECR access** — push images:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/backend-staging"
    }
  ]
}
```

**ECS access** — deploy services:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "arn:aws:ecs:<REGION>:<ACCOUNT_ID>:service/<CLUSTER_NAME>/<SERVICE_NAME>"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:role/<ECS_TASK_ROLE>",
        "arn:aws:iam::<ACCOUNT_ID>:role/<ECS_EXECUTION_ROLE>"
      ]
    }
  ]
}
```

## GitHub Configuration

### Secrets

Set these in **Settings > Secrets and variables > Actions > Secrets**:

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | ARN of the IAM role created in step 4 (e.g. `arn:aws:iam::123456789012:role/github-actions-staging`) |
| `AWS_ACCOUNT_ID` | Your AWS account ID |

### Variables

Set these in **Settings > Secrets and variables > Actions > Variables**:

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_REGION` | AWS region for ECR and ECS | `ap-southeast-1` |
| `ECR_REPOSITORY` | ECR repository name | `backend-staging` |
| `ECS_CLUSTER` | ECS cluster name | `staging-cluster` |
| `ECS_SERVICE` | ECS service name | `backend-staging-service` |
| `ECS_TASK_DEFINITION` | Task definition family name | `backend-staging-task` |
| `ECS_CONTAINER_NAME` | Container name in the task definition | `backend` |

## Verification

After completing all steps, push a commit to the `staging` branch. The workflow should:

1. Run tests and linting
2. Build the Docker image and push it to ECR
3. Update the ECS task definition with the new image
4. Deploy the updated service and wait for stability
