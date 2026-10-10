use crate::{
    AppState,
    auth::{self, AuthUser},
    error::{AppError, AppResult},
};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgPool};

const COLUMNS: &str = "id, first_name, last_name, email, photo, created_at";

#[derive(Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct User {
    pub id: i64,
    pub first_name: String,
    pub last_name: String,
    pub email: String,
    pub photo: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NewUser {
    first_name: String,
    last_name: String,
    email: String,
    password: String,
}

// Every field is optional: only the fields that are sent get updated.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateUser {
    first_name: Option<String>,
    last_name: Option<String>,
    email: Option<String>,
    password: Option<String>,
    photo: Option<String>,
}

pub async fn list(State(state): State<AppState>, _: AuthUser) -> AppResult<Json<Vec<User>>> {
    let users = sqlx::query_as(&format!("SELECT {COLUMNS} FROM users ORDER BY id"))
        .fetch_all(&state.db)
        .await?;
    Ok(Json(users))
}

pub async fn get(
    State(state): State<AppState>,
    _: AuthUser,
    Path(id): Path<i64>,
) -> AppResult<Json<User>> {
    Ok(Json(find(&state.db, id).await?))
}

pub async fn create(
    State(state): State<AppState>,
    _: AuthUser,
    Json(input): Json<NewUser>,
) -> AppResult<(StatusCode, Json<User>)> {
    Ok((StatusCode::CREATED, Json(insert(&state.db, input).await?)))
}

pub async fn update(
    State(state): State<AppState>,
    _: AuthUser,
    Path(id): Path<i64>,
    Json(input): Json<UpdateUser>,
) -> AppResult<Json<User>> {
    let first_name = input
        .first_name
        .map(|value| required(value, "nombre"))
        .transpose()?;
    let last_name = input
        .last_name
        .map(|value| required(value, "apellido"))
        .transpose()?;
    let email = input.email.map(normalize_email).transpose()?;
    let password_hash = match input.password {
        Some(password) => Some(auth::hash_password(validate_password(password)?).await?),
        None => None,
    };

    let user = sqlx::query_as(&format!(
        "UPDATE users SET
            first_name = COALESCE($2, first_name),
            last_name = COALESCE($3, last_name),
            email = COALESCE($4, email),
            password_hash = COALESCE($5, password_hash),
            photo = COALESCE($6, photo)
        WHERE id = $1
        RETURNING {COLUMNS}"
    ))
    .bind(id)
    .bind(first_name)
    .bind(last_name)
    .bind(email)
    .bind(password_hash)
    .bind(input.photo)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(user))
}

pub async fn delete(
    State(state): State<AppState>,
    _: AuthUser,
    Path(id): Path<i64>,
) -> AppResult<StatusCode> {
    // The files rows are removed by ON DELETE CASCADE; the stored files are removed here.
    let filenames: Vec<String> =
        sqlx::query_scalar("SELECT filename FROM files WHERE user_id = $1")
            .bind(id)
            .fetch_all(&state.db)
            .await?;
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::new(
            StatusCode::NOT_FOUND,
            "Usuario no encontrado",
        ));
    }
    for filename in filenames {
        state.storage.delete(&filename).await;
    }
    Ok(StatusCode::NO_CONTENT)
}

pub async fn find(db: &PgPool, id: i64) -> AppResult<User> {
    Ok(
        sqlx::query_as(&format!("SELECT {COLUMNS} FROM users WHERE id = $1"))
            .bind(id)
            .fetch_one(db)
            .await?,
    )
}

pub async fn insert(db: &PgPool, input: NewUser) -> AppResult<User> {
    let first_name = required(input.first_name, "nombre")?;
    let last_name = required(input.last_name, "apellido")?;
    let email = normalize_email(input.email)?;
    let password_hash = auth::hash_password(validate_password(input.password)?).await?;

    Ok(sqlx::query_as(&format!(
        "INSERT INTO users (first_name, last_name, email, password_hash)
        VALUES ($1, $2, $3, $4)
        RETURNING {COLUMNS}"
    ))
    .bind(first_name)
    .bind(last_name)
    .bind(email)
    .bind(password_hash)
    .fetch_one(db)
    .await?)
}

fn required(value: String, field: &str) -> AppResult<String> {
    let value = value.trim().to_string();
    if value.is_empty() {
        return Err(AppError::bad_request(format!(
            "El campo {field} es obligatorio"
        )));
    }
    Ok(value)
}

fn normalize_email(email: String) -> AppResult<String> {
    let email = email.trim().to_lowercase();
    if !email.contains('@') || email.len() < 3 {
        return Err(AppError::bad_request("Email inválido"));
    }
    Ok(email)
}

fn validate_password(password: String) -> AppResult<String> {
    if password.chars().count() < 6 {
        return Err(AppError::bad_request(
            "La contraseña debe tener al menos 6 caracteres",
        ));
    }
    Ok(password)
}

#[cfg(test)]
mod tests {
    use super::{normalize_email, required, validate_password};

    #[test]
    fn normalizes_emails_and_rejects_invalid_ones() {
        assert_eq!(
            normalize_email("  Ana@Test.COM ".into()).ok(),
            Some("ana@test.com".into())
        );
        assert!(normalize_email("sin-arroba".into()).is_err());
    }

    #[test]
    fn requires_names_and_six_character_passwords() {
        assert!(required("   ".into(), "nombre").is_err());
        assert_eq!(required(" Ana ".into(), "nombre").ok(), Some("Ana".into()));
        assert!(validate_password("12345".into()).is_err());
        assert!(validate_password("123456".into()).is_ok());
    }
}
