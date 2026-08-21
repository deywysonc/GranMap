import sys

from db import connect, init_db

VALID_ROLES = {
    "student",
    "professor",
    "moderator",
    "coordination",
    "admin",
}

if len(sys.argv) != 3:
    print("Uso: python promote_user.py EMAIL ROLE")
    print("Roles:", ", ".join(sorted(VALID_ROLES)))
    raise SystemExit(1)

email = sys.argv[1].strip().lower()
role = sys.argv[2].strip().lower()

if role not in VALID_ROLES:
    print("Role inválida.")
    raise SystemExit(1)

init_db()

with connect() as con:
    cursor = con.execute(
        "UPDATE users SET role = ?, updated_at = CURRENT_TIMESTAMP "
        "WHERE email = ? COLLATE NOCASE",
        (role, email),
    )
    con.commit()

if cursor.rowcount == 0:
    print("Usuário não encontrado.")
    raise SystemExit(1)

print(f"{email} agora possui o papel: {role}")
