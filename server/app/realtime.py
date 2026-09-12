"""Fan-out of league events to phones and the arena page.

With REDIS_URL set, every server worker publishes to one Redis channel per league and
each open WebSocket subscribes to it, so the arena and the phones see the same events no
matter which worker they are attached to. Without REDIS_URL, a single-process in-memory
set of sockets does the same job for local development.

Nothing durable lives in Redis: the plan is 29 MB. Live fight state carries a TTL.
"""

import asyncio
import contextlib
import json
import logging

from fastapi import WebSocket
from starlette.websockets import WebSocketDisconnect

from app.config import REDIS_URL

log = logging.getLogger("mealee.realtime")

LIVE_FIGHT_TTL_S = 600


class Realtime:
    def __init__(self) -> None:
        self._redis = None
        self._local_sockets: dict[str, set[WebSocket]] = {}

    async def connect(self) -> None:
        if not REDIS_URL:
            log.warning("REDIS_URL unset. Realtime is in-process only; run one worker.")
            return
        import redis.asyncio as redis_async
        self._redis = redis_async.from_url(REDIS_URL, socket_connect_timeout=3, socket_timeout=3)
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
            await self._redis.publish(self._channel(league_code), payload)
            if message.get("type") in ("fight_started", "fight_ended"):
                await self._redis.set(f"mealee:live:{league_code}", payload, ex=LIVE_FIGHT_TTL_S)
            return
        for socket in list(self._local_sockets.get(league_code, ())):
            try:
                await socket.send_text(payload)
            except (WebSocketDisconnect, RuntimeError):
                self._local_sockets[league_code].discard(socket)

    async def live_fight(self, league_code: str) -> dict | None:
        if self._redis is None:
            return None
        raw = await self._redis.get(f"mealee:live:{league_code}")
        return json.loads(raw) if raw else None

    async def serve_socket(self, league_code: str, socket: WebSocket) -> None:
        """Runs until the client disconnects. Pings every 20 s so venue wifi NAT does not
        drop an idle socket during a long stretch with no fights."""
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
        await pubsub.subscribe(self._channel(league_code))
        forward = asyncio.create_task(self._forward(pubsub, socket))
        try:
            await self._hold_open(socket)
        finally:
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
            log.info("forward stopped: %r", error)

    @staticmethod
    async def _hold_open(socket: WebSocket) -> None:
        while True:
            message = await asyncio.wait_for(socket.receive_text(), timeout=20)
            if message == "ping":
                await socket.send_text('{"type":"pong"}')


realtime = Realtime()
