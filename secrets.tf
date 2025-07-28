# ---------- RANDOM SUFFIX ----------
resource "random_id" "suffix" {
  byte_length = 4
}

# ---------- RANDOM PASSWORDS ----------
resource "random_password" "postgres" {
  count            = var.enable_postgres ? 1 : 0
  length           = 16
  special          = true
  override_special = "_!#$%^&()-=+?.,"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "opensearch" {
  count            = var.enable_opensearch ? 1 : 0
  length           = 16
  special          = true
  override_special = "_!#$%^&()-=+?.,"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}


# ---------- SECRETS MANAGER: POSTGRES ----------
resource "aws_secretsmanager_secret" "postgres_secret" {
  count                          = var.enable_postgres ? 1 : 0
  name                           = "postgres-admin-password-${random_id.suffix.hex}"
  description                    = "Admin password for PostgreSQL"
  force_overwrite_replica_secret = true
  tags                           = var.tags
}

resource "aws_secretsmanager_secret_version" "postgres_secret_value" {
  count         = var.enable_postgres ? 1 : 0
  secret_id     = aws_secretsmanager_secret.postgres_secret[0].id
  secret_string = jsonencode({ password = random_password.postgres[0].result })
}

data "aws_secretsmanager_secret_version" "postgres" {
  count      = var.enable_postgres ? 1 : 0
  depends_on = [aws_secretsmanager_secret_version.postgres_secret_value]
  secret_id  = aws_secretsmanager_secret.postgres_secret[0].id
}

# ---------- SECRETS MANAGER: OPENSEARCH ----------
resource "aws_secretsmanager_secret" "opensearch_secret" {
  count                          = var.enable_opensearch ? 1 : 0
  name                           = "opensearch-admin-password-${random_id.suffix.hex}"
  description                    = "Admin password for OpenSearch"
  force_overwrite_replica_secret = true
  tags                           = var.tags
}

resource "aws_secretsmanager_secret_version" "opensearch_secret_value" {
  count         = var.enable_opensearch ? 1 : 0
  secret_id     = aws_secretsmanager_secret.opensearch_secret[0].id
  secret_string = jsonencode({ password = random_password.opensearch[0].result })
}

data "aws_secretsmanager_secret_version" "opensearch" {
  count      = var.enable_opensearch ? 1 : 0
  depends_on = [aws_secretsmanager_secret_version.opensearch_secret_value]
  secret_id  = aws_secretsmanager_secret.opensearch_secret[0].id
}

resource "kubectl_manifest" "postgres_secret" {
  provider   = kubectl.eks
  depends_on = [data.aws_secretsmanager_secret_version.postgres]
  yaml_body  = <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: postgres-admin-secret
  namespace: default
type: Opaque
stringData:
  password: "${jsondecode(data.aws_secretsmanager_secret_version.postgres[0].secret_string)["password"]}"
YAML
}

resource "kubectl_manifest" "opensearch_secret" {
  provider   = kubectl.eks
  depends_on = [data.aws_secretsmanager_secret_version.opensearch]
  yaml_body  = <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: opensearch-admin-secret
  namespace: default
type: Opaque
stringData:
  password: "${jsondecode(data.aws_secretsmanager_secret_version.opensearch[0].secret_string)["password"]}"
YAML
}

