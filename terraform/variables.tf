variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Region for Cloud Run, Cloud SQL, Artifact Registry and API Gateway."
}

variable "database_url" {
  type        = string
  sensitive   = true
  description = "postgres://USER:PASSWORD@/DATABASE?host=/cloudsql/PROJECT:REGION:INSTANCE"

  validation {
    condition     = can(regex("^postgres://[^:]+:[^@]+@/[^?]+\\?host=/cloudsql/[^:]+:[^:]+:.+$", var.database_url))
    error_message = "database_url must look like postgres://USER:PASSWORD@/DATABASE?host=/cloudsql/PROJECT:REGION:INSTANCE."
  }
}

variable "jwt_secret" {
  type        = string
  sensitive   = true
  description = "Secret used to sign the API's JWTs."
}

variable "service_name" {
  type    = string
  default = "parallel-api"
}

variable "repository_id" {
  type    = string
  default = "parallel"
}

variable "db_instance_name" {
  type    = string
  default = "parallel-db"
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}

# Only used when Cloud Run is created. Later images are deployed by the pipeline with gcloud run deploy.
variable "initial_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "max_instances" {
  type    = number
  default = 3
}

variable "notifier_service_name" {
  type    = string
  default = "notification-cloud-run"
}

variable "smtp_host" {
  type    = string
  default = "smtp.gmail.com"
}

variable "smtp_port" {
  type    = number
  default = 587
}

variable "smtp_username" {
  type        = string
  description = "SMTP account that sends the emails."
}

variable "smtp_password" {
  type        = string
  sensitive   = true
  description = "SMTP password (for Gmail, an app password)."
}
