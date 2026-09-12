"""Every ended WebSocket must release what it held, on both realtime paths. A leak here
takes down every publish on the worker once the Redis pool or the socket set fills up."""

import asyncio
import shutil
import socket as socket_module
import subprocess
import time

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.realtime import Realtime


class FakeSocket:
    def __init__(self, lifetime_s: float) -> None:
        self.lifetime_s = lifetime_s
        self.sent: list[str] = []

    async def accept(self) -> None:
        pass

    async def send_text(self, text: str) -> None:
        self.sent.append(text)

    async def receive_text(self) -> str:
        await asyncio.sleep(self.lifetime_s)
        from starlette.websockets import WebSocketDisconnect
        raise WebSocketDisconnect()


def test_in_process_publish_survives_a_closed_client():
    with TestClient(app) as client:
        league = client.post("/leagues", json={"name": "Leak"}).json()["code"]
        player = client.post("/players", json={"league_code": league, "name": "Lea", "emoji": "🫧"}).json()["player_id"]
        for _ in range(3):
            with client.websocket_connect(f"/ws/league/{league}"):
                pass
        response = client.post("/intake", json={"player_id": player, "kind": "water"})
        assert response.status_code == 200, response.text


def _free_port() -> int:
    with socket_module.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


@pytest.fixture
def local_redis(monkeypatch):
    if shutil.which("redis-server") is None:
        pytest.skip("redis-server not installed")
    port = _free_port()
    process = subprocess.Popen(["redis-server", "--port", str(port), "--save", "", "--appendonly", "no"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket_module.create_connection(("127.0.0.1", port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    monkeypatch.setattr("app.realtime.REDIS_URL", f"redis://127.0.0.1:{port}")
    yield port
    process.terminate()
    process.wait(timeout=5)


def test_redis_subscription_is_released_when_the_client_goes_away(local_redis):
    async def run() -> tuple[int, int, list[str]]:
        realtime = Realtime()
        await realtime.connect()
        sockets = [FakeSocket(lifetime_s=0.3) for _ in range(5)]
        await asyncio.gather(*(realtime.serve_socket("DEMO", s) for s in sockets), return_exceptions=True)
        await asyncio.sleep(0.2)
        subscribers = (await realtime._redis.pubsub_numsub("mealee:league:DEMO"))[0][1]
        in_use = len(realtime._redis.connection_pool._in_use_connections)
        await realtime.publish("DEMO", {"type": "fighter_update"})
        await realtime.close()
        return subscribers, in_use, [s.sent for s in sockets]

    subscribers, in_use, sent = asyncio.run(run())
    assert subscribers == 0
    assert in_use == 0
    assert all(messages == [] for messages in sent)


def test_redis_live_subscriber_still_receives_after_others_left(local_redis):
    async def run() -> list[str]:
        realtime = Realtime()
        await realtime.connect()
        gone = [FakeSocket(lifetime_s=0.2) for _ in range(3)]
        staying = FakeSocket(lifetime_s=3.0)
        serving = asyncio.gather(*(realtime.serve_socket("DEMO", s) for s in gone + [staying]), return_exceptions=True)
        await asyncio.sleep(0.6)
        await realtime.publish("DEMO", {"type": "fighter_update", "n": 1})
        await asyncio.sleep(0.3)
        await serving
        await realtime.close()
        return staying.sent

    received = asyncio.run(run())
    assert len(received) == 1 and '"n": 1' in received[0]
