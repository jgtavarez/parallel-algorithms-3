output "gateway_url" {
  description = "URL the mobile app uses."
  value       = "https://${google_api_gateway_gateway.api.default_hostname}"
}

output "cloud_run_url" {
  description = "Private: only API Gateway can call it."
  value       = google_cloud_run_v2_service.api.uri
}

output "image_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.api.repository_id}"
}

output "sql_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "files_bucket" {
  value = google_storage_bucket.files.name
}

output "build_service_account" {
  value = google_service_account.build.email
}
