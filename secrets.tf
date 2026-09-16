# One secret per DB (auth, orders) holding connection details.
# Injected into the containers at runtime via the ECS task definition's
# "secrets" block (see ecs.tf) - never baked into the image or env vars in plaintext.

resource "aws_secretsmanager_secret" "db" {
  for_each = toset(["auth", "orders"])
  name     = "${var.project_name}/${each.key}/db-credentials"
  tags     = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  for_each  = aws_secretsmanager_secret.db
  secret_id = each.value.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.service[each.key].address
    port     = 5432
    dbname   = "${each.key}db"
  })
}

# Generic app-level secret (e.g. JWT signing key, third-party API keys)
resource "aws_secretsmanager_secret" "app" {
  for_each = var.services
  name     = "${var.project_name}/${each.key}/app-secrets"
  tags     = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each  = aws_secretsmanager_secret.app
  secret_id = each.value.id
  secret_string = jsonencode({
    jwt_secret = "REPLACE_ME_MANUALLY_OR_VIA_PIPELINE"
  })

  lifecycle {
    ignore_changes = [secret_string] # don't let plan clobber values rotated outside TF
  }
}
