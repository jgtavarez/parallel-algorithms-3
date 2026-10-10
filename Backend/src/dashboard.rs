use crate::{
    AppState,
    auth::AuthUser,
    error::AppResult,
    users::{self, User},
};
use axum::{Json, extract::State};
use serde::Serialize;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Stats {
    total_users: i64,
    total_files: i64,
}

pub async fn profile(State(state): State<AppState>, auth: AuthUser) -> AppResult<Json<User>> {
    Ok(Json(users::find(&state.db, auth.id).await?))
}

pub async fn stats(State(state): State<AppState>, _: AuthUser) -> AppResult<Json<Stats>> {
    let total_users = sqlx::query_scalar("SELECT COUNT(*) FROM users").fetch_one(&state.db);
    let total_files = sqlx::query_scalar("SELECT COUNT(*) FROM files").fetch_one(&state.db);

    // Both queries are independent, so they run at the same time on different pool connections.
    let (total_users, total_files) = tokio::try_join!(total_users, total_files)?;

    Ok(Json(Stats {
        total_users,
        total_files,
    }))
}
