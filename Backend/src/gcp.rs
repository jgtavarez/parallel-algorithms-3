use crate::error::{AppError, AppResult};
use serde::Deserialize;

const METADATA_TOKEN_URL: &str =
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";

#[derive(Deserialize)]
struct AccessToken {
    access_token: String,
}

// On Cloud Run, the metadata server returns a token for the service's own account.
pub async fn access_token(http: &reqwest::Client) -> AppResult<String> {
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
