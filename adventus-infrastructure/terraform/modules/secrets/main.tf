resource "aws_secretsmanager_secret" "this" {
  name        = var.secret_name
  description = "Application secrets for ${var.secret_name}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id

  # Seed with placeholder JSON. Real values are populated manually via
  # AWS Console or CLI after initial terraform apply.
  secret_string = jsonencode({
    APP_KEY              = "base64:CHANGE_ME"
    DB_HOST              = "CHANGE_ME"
    DB_PORT              = "5432"
    DB_DATABASE          = "CHANGE_ME"
    DB_USERNAME          = "CHANGE_ME"
    DB_PASSWORD          = "CHANGE_ME"
    PASSPORT_PRIVATE_KEY = "CHANGE_ME"
    PASSPORT_PUBLIC_KEY  = "CHANGE_ME"
  })

  # After the secret is created and manually populated, Terraform should
  # not overwrite the real values on subsequent applies.
  lifecycle {
    ignore_changes = [secret_string]
  }
}
