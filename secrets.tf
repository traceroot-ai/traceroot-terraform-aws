# secrets.tf
# Kubernetes namespace and application secrets for the active environment.
# Environment is controlled by var.environment (e.g. "staging", "production").
#
# var.manage_app_secrets (default true) selects how app secrets are delivered:
#   true  — this module generates the app secrets and writes the Kubernetes
#           Secrets itself. The turnkey, self-hosting path (unchanged behaviour).
#   false — the module creates none of the app Secrets and generates none of the
#           app-only values. Bring your own delivery (e.g. External Secrets
#           Operator syncing from a secret manager). The Helm chart still
#           references the same Secret names; the operator provides them.
#
# Infrastructure passwords (RDS/ElastiCache — rds.tf/elasticache.tf) are always
# managed here regardless, since the module owns those data stores.

resource "random_password" "better_auth_secret" {
  count   = var.manage_app_secrets ? 1 : 0
  length  = 64
  special = false
}

resource "random_password" "internal_api_secret" {
  count   = var.manage_app_secrets ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "clickhouse" {
  count   = var.manage_app_secrets ? 1 : 0
  length  = 32
  special = false
}

resource "random_id" "encryption_key" {
  count       = var.manage_app_secrets ? 1 : 0
  byte_length = 32 # 32 bytes = 64 hex characters = 256 bits
}

# Slack OAuth state-param signing secret. Rotating invalidates only in-flight
# install flows (state tokens are short-lived); already-stored bot tokens are
# unaffected.
resource "random_password" "slack_state_secret" {
  count   = var.manage_app_secrets ? 1 : 0
  length  = 64
  special = false
}

# Namespace for this environment (always managed)
resource "kubernetes_namespace" "app" {
  metadata { name = local.namespace }
  depends_on = [module.eks]
}

# Core secrets
resource "kubernetes_secret" "app" {
  count = var.manage_app_secrets ? 1 : 0

  metadata {
    name      = "traceroot"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "postgres-password"   = random_password.postgres.result
    "redis-password"      = random_password.redis.result
    "better-auth-secret"  = random_password.better_auth_secret[0].result
    "internal-api-secret" = random_password.internal_api_secret[0].result
    "clickhouse-password" = random_password.clickhouse[0].result
    "database-url"        = "postgresql://traceroot:${random_password.postgres.result}@${aws_rds_cluster.postgres.endpoint}:5432/${local.database_name}"
    "redis-url"           = "rediss://:${random_password.redis.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0"
    "encryption-key"      = random_id.encryption_key[0].hex
  }

  depends_on = [module.eks]
}

# GitHub App secret (conditional — only if github_app_id is provided)
resource "kubernetes_secret" "github" {
  count = var.manage_app_secrets && var.github_app_id != "" ? 1 : 0

  metadata {
    name      = "traceroot-github"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "github-app-id"             = var.github_app_id
    "github-app-name"           = var.github_app_name
    "github-app-client-id"      = var.github_app_client_id
    "github-app-client-secret"  = var.github_app_client_secret
    "github-app-private-key"    = var.github_app_private_key
    "github-oauth-redirect-uri" = var.domain != "" ? "https://${var.domain}/api/github/callback" : ""
  }

  depends_on = [module.eks]
}

# LLM API keys secret (conditional — only if any key is provided)
resource "kubernetes_secret" "llm_keys" {
  count = var.manage_app_secrets && (var.anthropic_api_key != "" || var.openai_api_key != "") ? 1 : 0

  metadata {
    name      = "traceroot-llm-keys"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "anthropic-api-key" = var.anthropic_api_key
    "openai-api-key"    = var.openai_api_key
    "daytona-api-key"   = var.daytona_api_key
  }

  depends_on = [module.eks]
}

# Stripe secret (conditional)
resource "kubernetes_secret" "stripe" {
  count = var.manage_app_secrets && var.stripe_secret_key != "" ? 1 : 0

  metadata {
    name      = "traceroot-stripe"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "stripe-secret-key"              = var.stripe_secret_key
    "stripe-webhook-signing-secret"  = var.stripe_webhook_signing_secret
    "stripe-price-id-starter"        = var.stripe_price_id_starter
    "stripe-price-id-pro"            = var.stripe_price_id_pro
    "stripe-price-id-ai-usage"       = var.stripe_price_id_ai_usage
    "stripe-price-id-rca-usage"      = var.stripe_price_id_rca_usage
    "stripe-price-id-detector-usage" = var.stripe_price_id_detector_usage
  }

  depends_on = [module.eks]
}

# Slack OAuth secret (conditional — only if slack_client_id is provided).
resource "kubernetes_secret" "slack" {
  count = var.manage_app_secrets && var.slack_client_id != "" && var.slack_client_secret != "" && var.domain != "" ? 1 : 0

  metadata {
    name      = "traceroot-slack"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "slack-client-id"     = var.slack_client_id
    "slack-client-secret" = var.slack_client_secret
    "slack-state-secret"  = random_password.slack_state_secret[0].result
    "slack-redirect-uri"  = var.domain != "" ? "https://${var.domain}/api/slack/oauth/callback" : ""
  }

  depends_on = [module.eks]
}

# Google OAuth secret (conditional)
resource "kubernetes_secret" "google_oauth" {
  count = var.manage_app_secrets && var.google_oauth_client_id != "" ? 1 : 0

  metadata {
    name      = "traceroot-google-oauth"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "google-client-id"     = var.google_oauth_client_id
    "google-client-secret" = var.google_oauth_client_secret
  }

  depends_on = [module.eks]
}

# SMTP secret (conditional)
resource "kubernetes_secret" "smtp" {
  count = var.manage_app_secrets && var.smtp_url != "" ? 1 : 0

  metadata {
    name      = "traceroot-smtp"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "smtp-url"       = var.smtp_url
    "smtp-mail-from" = var.smtp_mail_from
  }

  depends_on = [module.eks]
}

# Enterprise license secret (conditional)
resource "kubernetes_secret" "enterprise" {
  count = var.manage_app_secrets && var.enterprise_license_key != "" ? 1 : 0

  metadata {
    name      = "traceroot-enterprise"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "ee-license-key" = var.enterprise_license_key
  }

  depends_on = [module.eks]
}
