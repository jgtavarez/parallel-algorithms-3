mod auth;
mod dashboard;
mod error;
mod files;
mod gcp;
mod notifications;
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
    pub http: reqwest::Client,
    // Full topic name: projects/<project>/topics/<topic>. Unset when running locally.
    pub pubsub_topic: Option<String>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let database_url = with_host(&env::var("DATABASE_URL").map_err(|_| "missing DATABASE_URL")?);
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
        http: reqwest::Client::new(),
        pubsub_topic: env::var("PUBSUB_TOPIC").ok(),
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
        .route("/notifications/send", post(notifications::send))
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

// Cloud SQL socket URLs leave the host empty (postgres://user:pass@/db?host=/cloudsql/...).
// sqlx needs a host to parse the URL; the host query parameter still selects the socket.
fn with_host(database_url: &str) -> String {
    database_url.replacen("@/", "@localhost/", 1)
}

#[cfg(test)]
mod tests {
    use super::with_host;
    use sqlx::postgres::PgConnectOptions;
    use std::{path::PathBuf, str::FromStr};

    #[test]
    fn cloud_sql_socket_urls_connect_through_the_socket() {
        let url =
            with_host("postgres://api:secret@/parallel?host=/cloudsql/project:region:instance");
        let options = PgConnectOptions::from_str(&url).unwrap();
        assert_eq!(
            options.get_socket(),
            Some(&PathBuf::from("/cloudsql/project:region:instance"))
        );
        assert_eq!(options.get_database(), Some("parallel"));
    }

    #[test]
    fn regular_urls_are_not_changed() {
        let url = "postgres://user:pass@db:5432/app";
        assert_eq!(with_host(url), url);
    }
}
