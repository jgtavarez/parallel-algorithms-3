locals {
  apis = [
    "apigateway.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
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
