# Backend · Rust + Axum + PostgreSQL

Requisitos: Docker Desktop abierto.

```bash
cp .env.example .env      # cambiar contraseña y JWT_SECRET
docker compose up -d --build
```

La API queda en `http://localhost:3000`. La primera compilación tarda unos minutos.

```bash
docker compose logs -f api   # ver logs
docker compose down          # detener (los datos se conservan)
docker compose down -v       # detener y borrar base de datos y archivos
```

## Endpoints

Públicos:

| Método | Ruta | Uso |
|---|---|---|
| POST | /register | Crear cuenta. Devuelve `token` y `user` |
| POST | /login | Iniciar sesión. Devuelve `token` y `user` |

Requieren `Authorization: Bearer TOKEN`:

| Método | Ruta | Uso |
|---|---|---|
| GET | /users | Listar usuarios |
| GET | /users/{id} | Ver usuario |
| POST | /users | Crear usuario |
| PUT | /users/{id} | Actualizar (solo los campos enviados) |
| DELETE | /users/{id} | Eliminar usuario y sus archivos |
| POST | /upload | Subir archivo (multipart, campo `file`; JPG, PNG, WEBP o PDF; máx. 5 MB) |
| DELETE | /upload/{id} | Eliminar archivo propio |
| GET | /files | Archivos del usuario actual |
| GET | /profile | Usuario actual |
| GET | /stats | Total de usuarios y de archivos |

Los archivos subidos se sirven en `GET /uploads/{filename}`.

Prueba rápida:

```bash
curl -X POST http://localhost:3000/register -H 'Content-Type: application/json' \
  -d '{"firstName":"Ana","lastName":"Pérez","email":"ana@test.com","password":"secreto1"}'
```

## En Cloud Run

La misma imagen funciona en Cloud Run con estas variables, que configura Terraform:

| Variable | Uso |
|---|---|
| `PORT` | Puerto donde escuchar; lo define Cloud Run |
| `DATABASE_URL` | Conexión a Cloud SQL por socket: `postgres://USER:CLAVE@/DB?host=/cloudsql/PROYECTO:REGION:INSTANCIA` |
| `JWT_SECRET` | Desde Secret Manager |
| `GCS_BUCKET` | Si existe, los archivos se guardan en ese bucket de Cloud Storage en lugar del disco |
