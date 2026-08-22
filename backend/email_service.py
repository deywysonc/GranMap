from email.message import EmailMessage
import smtplib

from settings import get_settings


def send_password_reset(email: str, token: str) -> bool:
    settings = get_settings()
    if not settings.smtp_host or not settings.smtp_from_email:
        return False

    message = EmailMessage()
    message["Subject"] = "Código de recuperação do GranMap"
    message["From"] = settings.smtp_from_email
    message["To"] = email
    message.set_content(
        "Use o código abaixo no GranMap para criar uma nova senha.\n\n"
        f"{token}\n\n"
        "O código expira em 30 minutos. Se você não pediu a recuperação, "
        "ignore esta mensagem."
    )

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=12) as client:
        if settings.smtp_starttls:
            client.starttls()
        if settings.smtp_username and settings.smtp_password:
            client.login(settings.smtp_username, settings.smtp_password)
        client.send_message(message)
    return True
