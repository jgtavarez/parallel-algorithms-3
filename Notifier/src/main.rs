use axum::{Router, body::Bytes, extract::State, http::StatusCode, routing::post};
use base64::{Engine, engine::general_purpose::STANDARD};
use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor, message::header::ContentType,
    transport::smtp::authentication::Credentials,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{env, error::Error, sync::Arc};

type BoxError = Box<dyn Error + Send + Sync>;

struct Mailer {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from: String,
}

// Pub/Sub push body: {"message": {"data": "<base64>", "messageId": "..."}, "subscription": "..."}
#[derive(Deserialize)]
struct PushRequest {
    message: PushMessage,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PushMessage {
    data: String,
    message_id: String,
}

#[derive(Deserialize)]
struct Notification {
    email: String,
    subject: String,
    message: String,
}

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let host = env::var("SMTP_HOST").unwrap_or_else(|_| "smtp.gmail.com".into());
    let smtp_port: u16 = env::var("SMTP_PORT")
        .ok()
        .and_then(|port| port.parse().ok())
        .unwrap_or(587);
    let username = env::var("SMTP_USERNAME").map_err(|_| "missing SMTP_USERNAME")?;
    let password = env::var("SMTP_PASSWORD").map_err(|_| "missing SMTP_PASSWORD")?;
    let from =
        env::var("SMTP_FROM").unwrap_or_else(|_| format!("Algoritmos Paralelos <{username}>"));

    // Port 465 uses TLS from the start; 587 starts in plain text and upgrades with STARTTLS.
    let builder = if smtp_port == 465 {
        AsyncSmtpTransport::<Tokio1Executor>::relay(&host)?
    } else {
        AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&host)?
    };
    let transport = builder
        .port(smtp_port)
        .credentials(Credentials::new(username, password))
        .build();

    let app = Router::new()
        .route("/", post(receive))
        .with_state(Arc::new(Mailer { transport, from }));

    let port = env::var("PORT").unwrap_or_else(|_| "8080".into());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await?;
    log(
        "INFO",
        "service.started",
        "Servicio de notificaciones iniciado",
        json!({ "port": port }),
    );
    axum::serve(listener, app).await?;
    Ok(())
}

// A 2xx response acknowledges the message; any other status makes Pub/Sub retry it.
async fn receive(State(mailer): State<Arc<Mailer>>, body: Bytes) -> StatusCode {
    let (message_id, notification) = match decode(&body) {
        Ok(decoded) => decoded,
        Err(error) => {
            // A malformed message would fail on every retry, so it is acknowledged and logged.
            log(
                "ERROR",
                "message.invalid",
                "Mensaje inválido descartado",
                json!({ "error": error.to_string() }),
            );
            return StatusCode::NO_CONTENT;
        }
    };
    let fields = json!({ "messageId": message_id, "to": notification.email, "subject": notification.subject });
    log(
        "INFO",
        "message.received",
        "Mensaje recibido desde Pub/Sub",
        fields.clone(),
    );

    let email = match build_email(&mailer.from, &notification) {
        Ok(email) => email,
        Err(error) => {
            log(
                "ERROR",
                "email.invalid",
                "No se pudo armar el correo",
                with_error(fields, error),
            );
            return StatusCode::NO_CONTENT;
        }
    };

    match mailer.transport.send(email).await {
        Ok(_) => {
            log("INFO", "email.sent", "Correo enviado", fields);
            StatusCode::NO_CONTENT
        }
        Err(error) => {
            log(
                "ERROR",
                "email.failed",
                "Falló el envío; Pub/Sub lo reintentará",
                with_error(fields, error.into()),
            );
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

fn decode(body: &[u8]) -> Result<(String, Notification), BoxError> {
    let push: PushRequest = serde_json::from_slice(body)?;
    let notification = serde_json::from_slice(&STANDARD.decode(push.message.data)?)?;
    Ok((push.message.message_id, notification))
}

fn build_email(from: &str, notification: &Notification) -> Result<Message, BoxError> {
    Ok(Message::builder()
        .from(from.parse()?)
        .to(notification.email.parse()?)
        .subject(&notification.subject)
        .header(ContentType::TEXT_PLAIN)
        .body(notification.message.clone())?)
}

// Cloud Logging turns each JSON line on stdout into a structured entry; severity sets the level.
fn log(severity: &str, event: &str, message: &str, fields: Value) {
    let mut entry = json!({ "severity": severity, "event": event, "message": message });
    if let (Some(entry), Value::Object(fields)) = (entry.as_object_mut(), fields) {
        entry.extend(fields);
    }
    println!("{entry}");
}

fn with_error(mut fields: Value, error: BoxError) -> Value {
    fields["error"] = json!(error.to_string());
    fields
}

#[cfg(test)]
mod tests {
    use super::{Notification, build_email, decode};
    use base64::{Engine, engine::general_purpose::STANDARD};
    use serde_json::json;

    fn push_body(data: &str) -> Vec<u8> {
        json!({ "message": { "data": data, "messageId": "42" }, "subscription": "s" })
            .to_string()
            .into_bytes()
    }

    #[test]
    fn decodes_a_pub_sub_push_message() {
        let data =
            STANDARD.encode(r#"{"email":"ana@test.com","subject":"Hola","message":"Prueba"}"#);
        let (id, notification) = decode(&push_body(&data)).unwrap();
        assert_eq!(id, "42");
        assert_eq!(notification.email, "ana@test.com");
        assert_eq!(notification.subject, "Hola");
    }

    #[test]
    fn rejects_malformed_messages() {
        assert!(decode(b"no es json").is_err());
        assert!(decode(&push_body("%%% no es base64")).is_err());
        assert!(decode(&push_body(&STANDARD.encode("{}"))).is_err());
    }

    #[test]
    fn builds_emails_and_rejects_invalid_addresses() {
        let notification = |email: &str| Notification {
            email: email.into(),
            subject: "Hola".into(),
            message: "Prueba".into(),
        };
        let from = "Algoritmos Paralelos <bot@test.com>";
        assert!(build_email(from, &notification("ana@test.com")).is_ok());
        assert!(build_email(from, &notification("sin-arroba")).is_err());
    }
}
