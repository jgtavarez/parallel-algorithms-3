# notification-cloud-run

Recibe los mensajes que Pub/Sub le envía por push y manda cada uno como correo por SMTP.

| Variable | Uso |
|---|---|
| `SMTP_HOST` | Servidor SMTP (por defecto `smtp.gmail.com`) |
| `SMTP_PORT` | 587 (STARTTLS) o 465 (TLS) |
| `SMTP_USERNAME` | Cuenta que envía |
| `SMTP_PASSWORD` | Contraseña SMTP (desde Secret Manager) |
| `SMTP_FROM` | Opcional. Remitente visible |

Responde 204 cuando el correo se envió o cuando el mensaje es inválido (Pub/Sub no lo reintenta) y 500 cuando falla el envío (Pub/Sub lo reintenta).

```bash
cargo test --locked
```
