use crate::error::{AppError, AppResult};
use serde::Deserialize;
use std::{env, path::PathBuf};

const METADATA_TOKEN_URL: &str =
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";

// Local disk for docker compose; a Cloud Storage bucket on Cloud Run,
// where the container's disk is lost when the instance stops.
#[derive(Clone)]
pub enum Storage {
    Local(PathBuf),
    Bucket { name: String, http: reqwest::Client },
}

#[derive(Deserialize)]
struct AccessToken {
    access_token: String,
}

impl Storage {
    pub async fn from_env() -> std::io::Result<Self> {
        if let Ok(name) = env::var("GCS_BUCKET") {
            return Ok(Self::Bucket {
                name,
                http: reqwest::Client::new(),
            });
        }
        let dir = PathBuf::from(env::var("UPLOAD_DIR").unwrap_or_else(|_| "uploads".into()));
        tokio::fs::create_dir_all(&dir).await?;
        Ok(Self::Local(dir))
    }

    pub fn local_dir(&self) -> Option<&PathBuf> {
        match self {
            Self::Local(dir) => Some(dir),
            Self::Bucket { .. } => None,
        }
    }

    // Returns the public URL of the saved file.
    pub async fn save(
        &self,
        filename: &str,
        bytes: &[u8],
        content_type: &str,
    ) -> AppResult<String> {
        match self {
            Self::Local(dir) => {
                tokio::fs::write(dir.join(filename), bytes)
                    .await
                    .map_err(AppError::internal)?;
                Ok(format!("/uploads/{filename}"))
            }
            Self::Bucket { name, http } => {
                http.post(format!(
                    "https://storage.googleapis.com/upload/storage/v1/b/{name}/o?uploadType=media&name={filename}"
                ))
                .bearer_auth(access_token(http).await?)
                .header("Content-Type", content_type)
                .body(bytes.to_vec())
                .send()
                .await
                .and_then(|response| response.error_for_status())
                .map_err(AppError::internal)?;
                Ok(format!("https://storage.googleapis.com/{name}/{filename}"))
            }
        }
    }

    pub async fn delete(&self, filename: &str) {
        let result = match self {
            Self::Local(dir) => tokio::fs::remove_file(dir.join(filename))
                .await
                .map_err(|error| error.to_string()),
            Self::Bucket { name, http } => match access_token(http).await {
                Ok(token) => http
                    .delete(format!(
                        "https://storage.googleapis.com/storage/v1/b/{name}/o/{filename}"
                    ))
                    .bearer_auth(token)
                    .send()
                    .await
                    .and_then(|response| response.error_for_status())
                    .map(|_| ())
                    .map_err(|error| error.to_string()),
                Err(error) => Err(error.1),
            },
        };
        if let Err(error) = result {
            eprintln!("could not delete {filename}: {error}");
        }
    }
}

// On Cloud Run, the metadata server returns a token for the service's own account.
async fn access_token(http: &reqwest::Client) -> AppResult<String> {
    let token: AccessToken = http
        .get(METADATA_TOKEN_URL)
        .header("Metadata-Flavor", "Google")
        .send()
        .await
        .and_then(|response| response.error_for_status())
        .map_err(AppError::internal)?
        .json()
        .await
        .map_err(AppError::internal)?;
    Ok(token.access_token)
}
