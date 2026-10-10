# project_id, region, database_url and jwt_secret come from GitHub Secrets
# as TF_VAR_* environment variables, so they are not written here.

db_instance_name = "integrador-db"
db_tier          = "db-f1-micro"
max_instances    = 3
