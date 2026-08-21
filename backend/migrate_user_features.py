"""Compatibilidade: o schema de usuário agora faz parte da inicialização normal."""

from db import init_db


init_db()

print("GranMap: schema completo preparado e migrações idempotentes aplicadas.")
print("Papéis disponíveis: student, professor, moderator, coordination, admin.")
