from dataclasses import dataclass
import hashlib
import hmac

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError


LEGACY_PBKDF2_ITERATIONS = 210_000
PASSWORD_ALGORITHM = "argon2id"
_password_hasher = PasswordHasher(
    time_cost=2,
    memory_cost=19 * 1024,
    parallelism=1,
    hash_len=32,
    salt_len=16,
)


@dataclass(frozen=True)
class PasswordVerification:
    valid: bool
    upgraded_hash: str | None = None


def hash_password(password: str) -> str:
    return _password_hasher.hash(password)


def verify_password(
    password: str,
    stored_hash: str,
    algorithm: str | None,
    legacy_salt_hex: str = "",
) -> PasswordVerification:
    if algorithm == PASSWORD_ALGORITHM or stored_hash.startswith("$argon2"):
        try:
            valid = _password_hasher.verify(stored_hash, password)
        except (VerifyMismatchError, InvalidHashError):
            return PasswordVerification(False)
        upgraded = (
            _password_hasher.hash(password)
            if valid and _password_hasher.check_needs_rehash(stored_hash)
            else None
        )
        return PasswordVerification(valid, upgraded)

    try:
        salt = bytes.fromhex(legacy_salt_hex)
    except ValueError:
        return PasswordVerification(False)

    candidate = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        LEGACY_PBKDF2_ITERATIONS,
    ).hex()
    valid = hmac.compare_digest(candidate, stored_hash)
    return PasswordVerification(
        valid,
        hash_password(password) if valid else None,
    )


def hash_session_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
