"""Fan-out of league events to phones and the arena page.

With REDIS_URL set, every server worker publishes to one Redis channel per league and
each open WebSocket subscribes to it, so the arena and the phones see the same events no
matter which worker they are attached to. Without REDIS_URL, a single-process in-memory
set of sockets does the same job for local development.

Redis carries pub/sub only. Nothing is stored there: the arena's polling fallback and
the phones read fights from SQLite through /leagues/{code}/latest-fight.
"""

import asyncio
import contextlib
import json
import logging

from fastapi import WebSocket
from redis.exceptions import RedisError
from starlette.websockets import WebSocketDisconnect

from app.config import REDIS_URL

log = logging.getLogger("mealee.realtime")

IDLE_TIMEOUT_S = 20

# Publish holds one pooled connection under a lock, so a worker uses 1 + open sockets.
# The cap only matters against a local Redis; Redis Cloud enforces its own, lower one.
MAX_REDIS_CONNECTIONS = 200


class Realtime:
    def __init__(self) -> None:
        self._redis = None
        self._local_sockets: dict[str, set[WebSocket]] = {}
        self._publish_lock = asyncio.Lock()

    async def connect(self) -> None:
        if not REDIS_URL:
            log.warning("REDIS_URL unset. Realtime is in-process only; run one worker.")
            return
        import redis.asyncio as redis_async
        from redis.asyncio.retry import Retry
        from redis.backoff import NoBackoff
        # One immediate retry: after a Redis restart an idle pooled connection still
        # reports connected and fails on first use. Without this the first publish after
        # every failover is lost. No backoff, so a real outage costs nothing extra.
        self._redis = redis_async.from_url(REDIS_URL, socket_connect_timeout=2, socket_timeout=1,
                                           max_connections=MAX_REDIS_CONNECTIONS,
                                           retry=Retry(NoBackoff(), 1))
        await self._redis.ping()
        log.info("realtime: connected to Redis")

    async def close(self) -> None:
        if self._redis is not None:
            await self._redis.aclose()

    @staticmethod
    def _channel(league_code: str) -> str:
        return f"mealee:league:{league_code}"

    async def publish(self, league_code: str, message: dict) -> None:
        payload = json.dumps(message)
        if self._redis is not None:
            # Best effort: the row is already committed and the arena polls SQLite, so a
            # Redis outage costs one log line, never a 500 after a successful save.
            async with self._publish_lock:
                try:
                    await self._redis.publish(self._channel(league_code), payload)
                except RedisError as error:
                    log.warning("publish to %s failed: %s", league_code, error)
            return
        for socket in list(self._local_sockets.get(league_code, ())):
            try:
                await socket.send_text(payload)
            except (WebSocketDisconnect, RuntimeError):
                self._local_sockets[league_code].discard(socket)

    async def serve_socket(self, league_code: str, socket: WebSocket) -> None:
        """Runs until the client disconnects. Pings every 15 s from the client keep venue
        wifi NAT from dropping an idle socket during a long stretch with no fights."""
        await socket.accept()
        if self._redis is None:
            self._local_sockets.setdefault(league_code, set()).add(socket)
            try:
                await self._hold_open(socket)
            finally:
                self._local_sockets[league_code].discard(socket)
            return

        # _hold_open only ever returns by raising (client closed, or 20 s of silence), so
        # the teardown must sit in a finally or the pub/sub connection leaks for good.
        pubsub = self._redis.pubsub()
        forward = None
        try:
            await pubsub.subscribe(self._channel(league_code))
            forward = asyncio.create_task(self._forward(pubsub, socket))
            await self._hold_open(socket)
        finally:
            if forward is not None:
                forward.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await forward
            await pubsub.aclose()

    @staticmethod
    async def _forward(pubsub, socket: WebSocket) -> None:
        try:
            async for item in pubsub.listen():
                if item["type"] == "message":
                    await socket.send_text(item["data"].decode())
        except (WebSocketDisconnect, RuntimeError) as error:
            log.info("forward stopped, client gone: %s", error)
        except Exception as error:
            # The subscription is dead but the client still gets pongs and would wait
            # forever. Closing it makes the arena and the phone reconnect.
            log.warning("forward stopped, closing client: %s", error)
            with contextlib.suppress(Exception):
                await socket.close(code=1012)

    @staticmethod
    async def _hold_open(socket: WebSocket) -> None:
        while True:
            message = await asyncio.wait_for(socket.receive_text(), timeout=IDLE_TIMEOUT_S)
            if message == "ping":
                await socket.send_text('{"type":"pong"}')


realtime = Realtime()
