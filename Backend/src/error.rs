use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;
use std::fmt::Display;

pub struct AppError(pub StatusCode, pub String);

pub type AppResult<T> = Result<T, AppError>;

impl AppError {
    pub fn new(status: StatusCode, message: impl Into<String>) -> Self {
        Self(status, message.into())
    }

    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, message)
    }

    pub fn internal(error: impl Display) -> Self {
        eprintln!("internal error: {error}");
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Error interno del servidor",
        )
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({ "error": self.1 }))).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(error: sqlx::Error) -> Self {
        match &error {
            sqlx::Error::RowNotFound => Self::new(StatusCode::NOT_FOUND, "No encontrado"),
            sqlx::Error::Database(db) if db.is_unique_violation() => {
                Self::new(StatusCode::CONFLICT, "El email ya está registrado")
            }
            _ => Self::internal(error),
        }
    }
}
