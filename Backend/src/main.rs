mod auth;
mod dashboard;
mod error;
mod files;
mod storage;
mod users;

use axum::{
    Router,
    extract::DefaultBodyLimit,
    routing::{delete, get, post},
};
use sqlx::{PgPool, postgres::PgPoolOptions};
use std::{env, error::Error};
use storage::Storage;
use tower_http::services::ServeDir;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub jwt_secret: String,
    pub storage: Storage,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let database_url = env::var("DATABASE_URL").map_err(|_| "missing DATABASE_URL")?;
    let jwt_secret = env::var("JWT_SECRET").map_err(|_| "missing JWT_SECRET")?;
    // Cloud Run tells the container which port to listen on through PORT.
    let address = match env::var("PORT") {
        Ok(port) => format!("0.0.0.0:{port}"),
        Err(_) => env::var("API_ADDR").unwrap_or_else(|_| "0.0.0.0:3000".into()),
    };
    let storage = Storage::from_env().await?;
    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await?;
    sqlx::migrate!().run(&db).await?;

    let local_dir = storage.local_dir().cloned();
    let state = AppState {
        db,
        jwt_secret,
        storage,
    };

    let mut app = Router::new()
        .route("/register", post(auth::register))
        .route("/login", post(auth::login))
        .route("/profile", get(dashboard::profile))
        .route("/stats", get(dashboard::stats))
        .route("/users", get(users::list).post(users::create))
        .route(
            "/users/{id}",
            get(users::get).put(users::update).delete(users::delete),
        )
        .route("/files", get(files::list))
        .route(
            "/upload",
            post(files::upload).layer(DefaultBodyLimit::max(files::MAX_SIZE + 1024 * 1024)),
        )
        .route("/upload/{id}", delete(files::delete));
    if let Some(dir) = local_dir {
        app = app.nest_service("/uploads", ServeDir::new(dir));
    }
    let app = app.with_state(state);

    let listener = tokio::net::TcpListener::bind(&address).await?;
    println!("API listening on http://{}", listener.local_addr()?);
    axum::serve(listener, app).await?;
    Ok(())
}
