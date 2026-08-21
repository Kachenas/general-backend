# =============================================================================
# Terraform S3 Backend Configuration (Documentation)
# =============================================================================
#
# State is stored in S3 with a partial backend configuration. Each environment
# directory (environments/staging/, environments/production/) declares:
#
#   terraform {
#     backend "s3" {}
#   }
#
# The actual bucket name, region, and state key are passed at `terraform init`
# time via GitHub Actions secrets:
#
#   terraform init \
#     -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}" \
#     -backend-config="key=adventus/<env>/terraform.tfstate" \
#     -backend-config="region=${{ secrets.AWS_REGION }}"
#
# Why partial config?
# -------------------
# - Bucket names and regions are sensitive deployment details.
# - They differ between AWS accounts (staging vs production).
# - Keeping them out of version control lets the same code target any account.
#
# DynamoDB locking is NOT used. Instead, GitHub Actions `concurrency` groups
# prevent parallel Terraform runs against the same environment.
# =============================================================================
