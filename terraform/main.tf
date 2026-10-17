locals {
  apis = [
    "apigateway.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "servicecontrol.googleapis.com",
    "servicemanagement.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ]

  # The Cloud SQL user, password and database are read from DATABASE_URL,
  # so the GitHub secret is the single source for those values.
  db = regex("^postgres://(?P<user>[^:]+):(?P<password>[^@]+)@/(?P<name>[^?]+)\\?host=/cloudsql/(?P<connection>.+)$", var.database_url)
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

# Artifact Registry

resource "google_artifact_registry_repository" "api" {
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# Cloud SQL PostgreSQL

resource "google_sql_database_instance" "main" {
  name                = var.db_instance_name
  database_version    = "POSTGRES_17"
  region              = var.region
  deletion_protection = false

  settings {
    edition           = "ENTERPRISE"
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "app" {
  name     = local.db.name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "app" {
  name     = local.db.user
  instance = google_sql_database_instance.main.name
  password = local.db.password
}

# Secret Manager

resource "google_secret_manager_secret" "database_url" {
  secret_id = "database-url"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = var.database_url
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "jwt-secret"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = var.jwt_secret
}

# Storage bucket for uploaded files. Cloud Run's disk is lost when an instance stops.

resource "google_storage_bucket" "files" {
  name                        = "${var.project_id}-files"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  depends_on                  = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "files_public_read" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Service accounts and IAM roles

resource "google_service_account" "api" {
  account_id   = "api-runtime"
  display_name = "Cloud Run API"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "gateway" {
  account_id   = "api-gateway"
  display_name = "API Gateway to Cloud Run"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "build" {
  account_id   = "cloud-build"
  display_name = "Cloud Build image builds"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "api_roles" {
  for_each = toset(["roles/cloudsql.client", "roles/logging.logWriter"])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.api.member
}

resource "google_secret_manager_secret_iam_member" "api_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}

resource "google_secret_manager_secret_iam_member" "api_jwt_secret" {
  secret_id = google_secret_manager_secret.jwt_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}

resource "google_storage_bucket_iam_member" "api_files" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.api.member
}

# Cloud Build: builds the image with its own service account and pushes it to Artifact Registry.
resource "google_project_iam_member" "build_roles" {
  for_each = toset(["roles/logging.logWriter", "roles/storage.objectViewer"])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.build.member
}

resource "google_artifact_registry_repository_iam_member" "build_push" {
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.build.member
}

# Cloud Run

resource "google_cloud_run_v2_service" "api" {
  name                = var.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    scaling {
      max_instance_count = var.max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.initial_image

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.files.name
      }

      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.notifications.id
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  lifecycle {
    # The pipeline deploys each new image with gcloud run deploy.
    ignore_changes = [template[0].containers[0].image, client, client_version]

    precondition {
      condition     = local.db.connection == google_sql_database_instance.main.connection_name
      error_message = "DATABASE_URL must use host=/cloudsql/<connection name of the Cloud SQL instance>."
    }
  }

  depends_on = [
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.jwt_secret,
    google_secret_manager_secret_iam_member.api_database_url,
    google_secret_manager_secret_iam_member.api_jwt_secret,
  ]
}

# Only API Gateway can call Cloud Run directly.
resource "google_cloud_run_v2_service_iam_member" "gateway_invoker" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = google_service_account.gateway.member
}

# API Gateway

resource "google_api_gateway_api" "api" {
  provider   = google-beta
  api_id     = "parallel-api"
  depends_on = [google_project_service.apis]
}

resource "google_api_gateway_api_config" "api" {
  provider             = google-beta
  api                  = google_api_gateway_api.api.api_id
  api_config_id_prefix = "parallel-"

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tftpl", {
        backend_url = google_cloud_run_v2_service.api.uri
      }))
    }
  }

  gateway_config {
    backend_config {
      google_service_account = google_service_account.gateway.email
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "api" {
  provider   = google-beta
  region     = var.region
  gateway_id = "parallel-gateway"
  api_config = google_api_gateway_api_config.api.id
}

# Each API Gateway API is a managed service that must be enabled in the project.
# It only exists after the first API config is created.
resource "google_project_service" "gateway_managed_service" {
  service            = google_api_gateway_api.api.managed_service
  disable_on_destroy = false
  depends_on         = [google_api_gateway_api_config.api]
}

# Cloud Logging: counts the API's 5xx responses from the Cloud Run request logs.

resource "google_logging_metric" "api_errors" {
  name   = "parallel-api-5xx"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.service_name}\" AND httpRequest.status>=500"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.apis]
}

# Pub/Sub: the API publishes emails here and notification-cloud-run receives them.

data "google_project" "current" {}

resource "google_pubsub_topic" "notifications" {
  name       = "notifications"
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_topic_iam_member" "api_publisher" {
  topic  = google_pubsub_topic.notifications.id
  role   = "roles/pubsub.publisher"
  member = google_service_account.api.member
}

# Notification Cloud Run

resource "google_service_account" "notifier" {
  account_id   = "notifier-runtime"
  display_name = "notification-cloud-run"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "notifier_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.notifier.member
}

resource "google_secret_manager_secret" "smtp_password" {
  secret_id = "smtp-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "smtp_password" {
  secret      = google_secret_manager_secret.smtp_password.id
  secret_data = var.smtp_password
}

resource "google_secret_manager_secret_iam_member" "notifier_smtp_password" {
  secret_id = google_secret_manager_secret.smtp_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.notifier.member
}

resource "google_cloud_run_v2_service" "notifier" {
  name                = var.notifier_service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.notifier.email

    scaling {
      max_instance_count = 2
    }

    containers {
      image = var.initial_image

      env {
        name  = "SMTP_HOST"
        value = var.smtp_host
      }

      env {
        name  = "SMTP_PORT"
        value = tostring(var.smtp_port)
      }

      env {
        name  = "SMTP_USERNAME"
        value = var.smtp_username
      }

      env {
        name = "SMTP_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.smtp_password.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    # The pipeline deploys each new image with gcloud run deploy.
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }

  depends_on = [
    google_secret_manager_secret_version.smtp_password,
    google_secret_manager_secret_iam_member.notifier_smtp_password,
  ]
}

# Pub/Sub -> Cloud Run push subscription. Pub/Sub signs each request with
# an OIDC token of this account, the only one allowed to invoke the service.

resource "google_service_account" "pubsub_push" {
  account_id   = "pubsub-push"
  display_name = "Pub/Sub push to notification-cloud-run"
  depends_on   = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  name     = google_cloud_run_v2_service.notifier.name
  location = google_cloud_run_v2_service.notifier.location
  role     = "roles/run.invoker"
  member   = google_service_account.pubsub_push.member
}

# Lets Pub/Sub create the OIDC tokens for the push account.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.pubsub_push.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "notifier" {
  name                 = "notification-cloud-run-push"
  topic                = google_pubsub_topic.notifications.id
  ack_deadline_seconds = 60

  push_config {
    push_endpoint = google_cloud_run_v2_service.notifier.uri

    oidc_token {
      service_account_email = google_service_account.pubsub_push.email
      audience              = google_cloud_run_v2_service.notifier.uri
    }
  }

  # Failed deliveries (non-2xx) are retried with a growing wait.
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  expiration_policy {
    ttl = ""
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.pubsub_invoker,
    google_service_account_iam_member.pubsub_token_creator,
  ]
}

# Cloud Logging: the notifier writes one JSON log per event.

resource "google_logging_metric" "emails_sent" {
  name   = "notification-emails-sent"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.notifier_service_name}\" AND jsonPayload.event=\"email.sent\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.apis]
}

resource "google_logging_metric" "emails_failed" {
  name   = "notification-emails-failed"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.notifier_service_name}\" AND jsonPayload.event=\"email.failed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.apis]
}
