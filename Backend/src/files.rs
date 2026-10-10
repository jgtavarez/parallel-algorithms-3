use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
};
use axum::{
    Json,
    extract::{Multipart, Path, State},
    http::StatusCode,
};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;
use uuid::Uuid;

pub const MAX_SIZE: usize = 5 * 1024 * 1024;
const COLUMNS: &str = "id, user_id, filename, original_name, content_type, size, url, created_at";

#[derive(Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct StoredFile {
    id: i64,
    user_id: i64,
    filename: String,
    original_name: String,
    content_type: String,
    size: i64,
    url: String,
    created_at: DateTime<Utc>,
}

pub async fn list(
    State(state): State<AppState>,
    auth: AuthUser,
) -> AppResult<Json<Vec<StoredFile>>> {
    let files = sqlx::query_as(&format!(
        "SELECT {COLUMNS} FROM files WHERE user_id = $1 ORDER BY id DESC"
    ))
    .bind(auth.id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(files))
}

pub async fn upload(
    State(state): State<AppState>,
    auth: AuthUser,
    mut multipart: Multipart,
) -> AppResult<(StatusCode, Json<StoredFile>)> {
    let unreadable = |error: axum::extract::multipart::MultipartError| {
        AppError::new(error.status(), "No se pudo leer el archivo (máximo 5 MB)")
    };
    let field = loop {
        match multipart.next_field().await.map_err(unreadable)? {
            Some(field) if field.name() == Some("file") => break field,
            Some(_) => continue,
            None => return Err(AppError::bad_request("Falta el campo file")),
        }
    };
    let original_name = field.file_name().unwrap_or("archivo").to_string();
    let bytes = field.bytes().await.map_err(unreadable)?;

    if bytes.is_empty() || bytes.len() > MAX_SIZE {
        return Err(AppError::bad_request(
            "El archivo debe pesar entre 1 byte y 5 MB",
        ));
    }
    let Some((content_type, extension)) = detect_type(&bytes) else {
        return Err(AppError::new(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            "Solo se aceptan JPG, PNG, WEBP o PDF",
        ));
    };

    let filename = format!("{}.{extension}", Uuid::new_v4());
    let url = state.storage.save(&filename, &bytes, content_type).await?;

    let file = sqlx::query_as(&format!(
        "INSERT INTO files (user_id, filename, original_name, content_type, size, url)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING {COLUMNS}"
    ))
    .bind(auth.id)
    .bind(&filename)
    .bind(original_name)
    .bind(content_type)
    .bind(bytes.len() as i64)
    .bind(url)
    .fetch_one(&state.db)
    .await?;
    Ok((StatusCode::CREATED, Json(file)))
}

pub async fn delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<i64>,
) -> AppResult<StatusCode> {
    let file: StoredFile = sqlx::query_as(&format!("SELECT {COLUMNS} FROM files WHERE id = $1"))
        .bind(id)
        .fetch_one(&state.db)
        .await?;
    if file.user_id != auth.id {
        return Err(AppError::new(
            StatusCode::FORBIDDEN,
            "Solo quien subió el archivo puede eliminarlo",
        ));
    }

    sqlx::query("DELETE FROM files WHERE id = $1")
        .bind(id)
        .execute(&state.db)
        .await?;
    sqlx::query("UPDATE users SET photo = NULL WHERE photo = $1")
        .bind(&file.url)
        .execute(&state.db)
        .await?;
    state.storage.delete(&file.filename).await;
    Ok(StatusCode::NO_CONTENT)
}

// The type comes from the file's first bytes, not from the name or the header the client sends.
fn detect_type(bytes: &[u8]) -> Option<(&'static str, &'static str)> {
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(("image/jpeg", "jpg"))
    } else if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some(("image/png", "png"))
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some(("image/webp", "webp"))
    } else if bytes.starts_with(b"%PDF-") {
        Some(("application/pdf", "pdf"))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::detect_type;

    #[test]
    fn detects_supported_types_by_their_first_bytes() {
        assert_eq!(
            detect_type(&[0xFF, 0xD8, 0xFF, 0xE0]),
            Some(("image/jpeg", "jpg"))
        );
        assert_eq!(
            detect_type(b"\x89PNG\r\n\x1a\n...."),
            Some(("image/png", "png"))
        );
        assert_eq!(
            detect_type(b"RIFF\0\0\0\0WEBPVP8 "),
            Some(("image/webp", "webp"))
        );
        assert_eq!(detect_type(b"%PDF-1.7"), Some(("application/pdf", "pdf")));
    }

    #[test]
    fn rejects_files_whose_content_is_not_supported() {
        assert_eq!(detect_type(b"hola"), None);
        assert_eq!(detect_type(b""), None);
    }
}
