# Algoritmos Paralelos · Despliegue serverless en GCP.

```
Mobile App (Flutter)
    │
API Gateway
    │
Cloud Run parallel-api (Rust + Axum) ── Cloud Storage (archivos)
    │                     │
Cloud SQL PostgreSQL      │ POST /notifications/send
                          ▼
                     Pub/Sub (notifications)
                          │ push
                          ▼
              Cloud Run notification-cloud-run ── SMTP ──▶ correo
```

```
Backend/        API REST (Rust + Axum), Dockerfile y cloudbuild.yaml
Notifier/       notification-cloud-run: recibe mensajes de Pub/Sub y envía correos por SMTP
Mobile/         App Flutter (MVVM)
terraform/      Infraestructura como código
.github/        Workflow de GitHub Actions
```

## Pipeline

Cada push a `main` ejecuta `.github/workflows/deploy.yml`:

1. **Build** (API y Notifier en paralelo): dependencias, build, pruebas y `docker build`.
2. **Terraform**: `init`, `validate`, `plan` y `apply -auto-approve`. Crea Cloud Run, API Gateway, Artifact Registry, Cloud SQL, Pub/Sub (tema y suscripción push), el Cloud Run de notificaciones, cuentas de servicio, roles IAM, Secret Manager, el bucket de archivos y métricas de Cloud Logging.
3. **Deploy** (los dos servicios en paralelo): `gcloud builds submit` construye cada imagen y la publica en Artifact Registry; `gcloud run deploy` la despliega en su Cloud Run.

El estado de Terraform se guarda en el bucket `<proyecto>-tfstate`, que el pipeline crea si no existe.

## Secrets de GitHub

| Secret | Valor |
|---|---|
| `GCP_PROJECT_ID` | ID del proyecto de GCP |
| `GCP_REGION` | Región, por ejemplo `us-central1` |
| `GCP_SA_KEY` | JSON de la llave de la cuenta de servicio del pipeline |
| `DATABASE_URL` | `postgres://api:CLAVE@/parallel?host=/cloudsql/PROYECTO:REGION:parallel-db` |
| `JWT_SECRET` | Texto aleatorio largo |
| `SMTP_USERNAME` | Cuenta que envía los correos, por ejemplo una de Gmail |
| `SMTP_PASSWORD` | Contraseña SMTP; en Gmail, una contraseña de aplicación |
| `ARTIFACT_REGISTRY` | Opcional. Nombre del repositorio de imágenes (por defecto `parallel`) |
| `CLOUD_RUN_SERVICE` | Opcional. Nombre del servicio (por defecto `parallel-api`) |

Terraform toma el usuario, la contraseña y la base de datos de `DATABASE_URL` para crearlos en Cloud SQL, y guarda la URL en Secret Manager. Usar solo letras y números en la contraseña.

## Preparar GCP (una sola vez)

```bash
PROJECT_ID=mi-proyecto
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com iam.googleapis.com --project="$PROJECT_ID"
gcloud iam service-accounts create github-deployer --project="$PROJECT_ID"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:github-deployer@${PROJECT_ID}.iam.gserviceaccount.com" --role=roles/owner
gcloud iam service-accounts keys create key.json \
  --iam-account="github-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
```

El contenido de `key.json` va en el secret `GCP_SA_KEY`. Después, borrar el archivo.

## App móvil

Usar la URL de API Gateway (`terraform output gateway_url`):

```bash
cd Mobile
flutter run --dart-define=API_URL=https://parallel-gateway-xxxx.uc.gateway.dev
```

## Borrar todo

Cloud SQL cobra mientras exista. Al terminar:

```bash
cd terraform
export TF_VAR_project_id=$PROJECT_ID TF_VAR_region=us-central1 \
  TF_VAR_database_url='...' TF_VAR_jwt_secret='...'
terraform init -backend-config="bucket=${PROJECT_ID}-tfstate"
terraform destroy
```
# parallel-algorithms-3

## Probar el envío de correos

```bash
curl -X POST https://<gateway>/notifications/send \
  -H "Authorization: Bearer <JWT>" -H 'Content-Type: application/json' \
  -d '{"email":"usuario@correo.com","subject":"Prueba PUB/SUB","message":"Hola desde GCP Serverless"}'
```

La API responde `202` con el `messageId` de Pub/Sub. El correo lo envía `notification-cloud-run`; sus logs muestran `message.received` y `email.sent` (o `email.failed`, y Pub/Sub lo reintenta).
