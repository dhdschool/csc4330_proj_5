"""Per-user Gradescope sessions.

The library's bundled server keeps ONE global GSConnection, so every user would
share it. Here each login gets its own GSConnection, looked up by a random
bearer token that the Flutter app sends on every request.

Sessions live in memory: they disappear when the server restarts, and this only
works with a single server process (run uvicorn with --workers 1). If you scale
out later, move this to Redis or similar.
"""

import secrets
import threading
import time
from dataclasses import dataclass, field

from gradescopeapi.classes.connection import GSConnection

SESSION_TTL_SECONDS = 2 * 60 * 60  # idle sessions expire after 2 hours


@dataclass
class UserSession:
    connection: GSConnection
    email: str
    last_used: float = field(default_factory=time.time)


class SessionStore:
    def __init__(self, ttl: int = SESSION_TTL_SECONDS):
        self._ttl = ttl
        self._sessions: dict[str, UserSession] = {}
        self._lock = threading.Lock()

    def create(self, email: str, password: str) -> str:
        """Log in to Gradescope and return a new token. Raises ValueError on bad login."""
        conn = GSConnection()
        conn.login(email, password)  # raises ValueError if credentials are wrong
        token = secrets.token_urlsafe(32)
        with self._lock:
            self._purge_expired()
            self._sessions[token] = UserSession(connection=conn, email=email)
        return token

    def get(self, token: str) -> UserSession | None:
        with self._lock:
            self._purge_expired()
            session = self._sessions.get(token)
            if session:
                session.last_used = time.time()
            return session

    def delete(self, token: str) -> None:
        with self._lock:
            session = self._sessions.pop(token, None)
        if session:
            try:
                session.connection.logout()
            except Exception:
                pass

    def _purge_expired(self) -> None:
        now = time.time()
        expired = [t for t, s in self._sessions.items() if now - s.last_used > self._ttl]
        for t in expired:
            self._sessions.pop(t, None)
