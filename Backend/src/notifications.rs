use crate::{
    AppState,
    auth::AuthUser,
    error::{AppError, AppResult},
    gcp::access_token,
};
use axum::{Json, extract::State, http::StatusCode};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};
use serde_json::json;

const MAX_SUBJECT: usize = 200;
const MAX_MESSAGE: usize = 5_000;

#[derive(Deserialize, Serialize)]
pub struct NotificationInput {
    email: String,
    subject: String,
    message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Queued {
    message_id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PublishResponse {
    message_ids: Vec<String>,
}

// Publishes the email to Pub/Sub and returns right away; notification-cloud-run sends it.
pub async fn send(
    State(state): State<AppState>,
    _: AuthUser,
    Json(input): Json<NotificationInput>,
) -> AppResult<(StatusCode, Json<Queued>)> {
    let notification = validate(input)?;
    let Some(topic) = &state.pubsub_topic else {
        return Err(AppError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "Las notificaciones no están configuradas",
        ));
    };

    let data = STANDARD.encode(serde_json::to_vec(&notification).map_err(AppError::internal)?);
    let response: PublishResponse = state
        .http
        .post(format!("https://pubsub.googleapis.com/v1/{topic}:publish"))
        .bearer_auth(access_token(&state.http).await?)
        .json(&json!({ "messages": [{ "data": data }] }))
        .send()
        .await
        .and_then(|response| response.error_for_status())
        .map_err(AppError::internal)?
        .json()
        .await
        .map_err(AppError::internal)?;

    let message_id = response.message_ids.into_iter().next().unwrap_or_default();
    Ok((StatusCode::ACCEPTED, Json(Queued { message_id })))
}

fn validate(input: NotificationInput) -> AppResult<NotificationInput> {
    let email = input.email.trim().to_lowercase();
    let subject = input.subject.trim().to_string();
    let message = input.message.trim().to_string();

    if !email.contains('@') || email.contains(char::is_whitespace) {
        return Err(AppError::bad_request("Email inválido"));
    }
    if subject.is_empty() || subject.chars().count() > MAX_SUBJECT {
        return Err(AppError::bad_request(format!(
            "El asunto debe tener entre 1 y {MAX_SUBJECT} caracteres"
        )));
    }
    if message.is_empty() || message.chars().count() > MAX_MESSAGE {
        return Err(AppError::bad_request(format!(
            "El mensaje debe tener entre 1 y {MAX_MESSAGE} caracteres"
        )));
    }
    Ok(NotificationInput {
        email,
        subject,
        message,
    })
}

#[cfg(test)]
mod tests {
    use super::{NotificationInput, validate};

    fn input(email: &str, subject: &str, message: &str) -> NotificationInput {
        NotificationInput {
            email: email.into(),
            subject: subject.into(),
            message: message.into(),
        }
    }

    #[test]
    fn accepts_and_normalizes_valid_requests() {
        let valid = validate(input(" Ana@Test.com ", " Prueba ", " Hola "))
            .ok()
            .unwrap();
        assert_eq!(valid.email, "ana@test.com");
        assert_eq!(valid.subject, "Prueba");
        assert_eq!(valid.message, "Hola");
    }

    #[test]
    fn rejects_invalid_requests() {
        assert!(validate(input("sin-arroba", "Prueba", "Hola")).is_err());
        assert!(validate(input("ana@test.com", "  ", "Hola")).is_err());
        assert!(validate(input("ana@test.com", "Prueba", "")).is_err());
        assert!(validate(input("ana@test.com", &"x".repeat(201), "Hola")).is_err());
    }
}
