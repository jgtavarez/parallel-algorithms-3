# project_id, region, database_url, jwt_secret, smtp_username and smtp_password come from GitHub Secrets
# as TF_VAR_* environment variables, so they are not written here.

db_instance_name = "parallel-db"
db_tier          = "db-f1-micro"
max_instances    = 3
smtp_host        = "smtp.gmail.com"
smtp_port        = 587
