use crate::{
    AppState,
    error::{AppError, AppResult},
    users::{self, NewUser, User},
};
use argon2::{
    Argon2,
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString, rand_core::OsRng},
};
use axum::{
    Json,
    extract::{FromRequestParts, State},
    http::{StatusCode, header::AUTHORIZATION, request::Parts},
};
use chrono::{Duration, Utc};
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};

const TOKEN_HOURS: i64 = 24;

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: String,
    exp: i64,
}

#[derive(Deserialize)]
pub struct LoginInput {
    email: String,
    password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    token: String,
    user: User,
}

pub struct AuthUser {
    pub id: i64,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> AppResult<Self> {
        let unauthorized = || AppError::new(StatusCode::UNAUTHORIZED, "Token inválido o vencido");
        // API Gateway authenticates itself to Cloud Run with its own Authorization header
        // and moves the client's header to X-Forwarded-Authorization.
        let headers = &parts.headers;
        let token = headers
            .get("x-forwarded-authorization")
            .or_else(|| headers.get(AUTHORIZATION))
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.strip_prefix("Bearer "))
            .ok_or_else(unauthorized)?;
        let data = decode::<Claims>(
            token,
            &DecodingKey::from_secret(state.jwt_secret.as_bytes()),
            &Validation::default(),
        )
        .map_err(|_| unauthorized())?;
        let id = data.claims.sub.parse().map_err(|_| unauthorized())?;
        Ok(AuthUser { id })
    }
}

pub async fn register(
    State(state): State<AppState>,
    Json(input): Json<NewUser>,
) -> AppResult<(StatusCode, Json<AuthResponse>)> {
    let user = users::insert(&state.db, input).await?;
    let token = create_token(&state, user.id)?;
    Ok((StatusCode::CREATED, Json(AuthResponse { token, user })))
}

pub async fn login(
    State(state): State<AppState>,
    Json(input): Json<LoginInput>,
) -> AppResult<Json<AuthResponse>> {
    let invalid = || AppError::new(StatusCode::UNAUTHORIZED, "Email o contraseña incorrectos");
    let row: Option<(i64, String)> =
        sqlx::query_as("SELECT id, password_hash FROM users WHERE email = $1")
            .bind(input.email.trim().to_lowercase())
            .fetch_optional(&state.db)
            .await?;
    let Some((id, password_hash)) = row else {
        return Err(invalid());
    };
    if !verify_password(input.password, password_hash).await {
        return Err(invalid());
    }

    let user = users::find(&state.db, id).await?;
    let token = create_token(&state, id)?;
    Ok(Json(AuthResponse { token, user }))
}

fn create_token(state: &AppState, user_id: i64) -> AppResult<String> {
    let claims = Claims {
        sub: user_id.to_string(),
        exp: (Utc::now() + Duration::hours(TOKEN_HOURS)).timestamp(),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(AppError::internal)
}

// Argon2 is intentionally slow, so it runs outside the async worker threads.
pub async fn hash_password(password: String) -> AppResult<String> {
    tokio::task::spawn_blocking(move || {
        let salt = SaltString::generate(&mut OsRng);
        Argon2::default()
            .hash_password(password.as_bytes(), &salt)
            .map(|hash| hash.to_string())
    })
    .await
    .map_err(AppError::internal)?
    .map_err(AppError::internal)
}

async fn verify_password(password: String, hash: String) -> bool {
    tokio::task::spawn_blocking(move || {
        PasswordHash::new(&hash).is_ok_and(|parsed| {
            Argon2::default()
                .verify_password(password.as_bytes(), &parsed)
                .is_ok()
        })
    })
    .await
    .unwrap_or(false)
}
