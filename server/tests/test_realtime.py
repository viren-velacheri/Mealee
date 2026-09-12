"""Every ended WebSocket must release what it held, on both realtime paths. A leak here
takes down every publish on the worker once the Redis pool or the socket set fills up."""

import asyncio
import contextlib
import shutil
import socket as socket_module
import subprocess
import time
import types

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.main import app
from app.realtime import Realtime


class FakeSocket:
    def __init__(self, lifetime_s: float) -> None:
        self.lifetime_s = lifetime_s
        self.sent: list[str] = []
        self.closed_with: int | None = None
        self._closed = asyncio.Event()

    async def accept(self) -> None:
        pass

    async def send_text(self, text: str) -> None:
        self.sent.append(text)

    async def receive_text(self) -> str:
        with contextlib.suppress(asyncio.TimeoutError):
            await asyncio.wait_for(self._closed.wait(), timeout=self.lifetime_s)
        raise WebSocketDisconnect()

    async def close(self, code: int = 1000) -> None:
        self.closed_with = code
        self._closed.set()


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
    yield types.SimpleNamespace(port=port, process=process)
    if process.poll() is None:
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


def test_publish_is_best_effort_when_redis_is_down(local_redis, caplog):
    async def run() -> None:
        realtime = Realtime()
        await realtime.connect()
        local_redis.process.terminate()
        local_redis.process.wait(timeout=5)
        await realtime.publish("DEMO", {"type": "fighter_update"})
        await realtime.close()

    asyncio.run(run())
    assert "publish to DEMO failed" in caplog.text


def test_redis_drop_closes_the_client_so_it_reconnects(local_redis):
    async def run() -> int | None:
        realtime = Realtime()
        await realtime.connect()
        socket = FakeSocket(lifetime_s=10)
        serving = asyncio.create_task(realtime.serve_socket("DEMO", socket))
        await asyncio.sleep(0.3)
        local_redis.process.terminate()
        local_redis.process.wait(timeout=5)
        with contextlib.suppress(Exception):
            await asyncio.wait_for(serving, timeout=5)
        await realtime.close()
        return socket.closed_with

    assert asyncio.run(run()) == 1012


def test_idle_client_gets_a_clean_close(monkeypatch):
    monkeypatch.setattr("app.realtime.IDLE_TIMEOUT_S", 0.3)
    with TestClient(app) as client:
        league = client.post("/leagues", json={"name": "Idle"}).json()["code"]
        with client.websocket_connect(f"/ws/league/{league}") as socket:
            with pytest.raises(WebSocketDisconnect) as closed:
                socket.receive_text()
            assert closed.value.code == 1000


def test_first_publish_after_a_redis_restart_reaches_a_new_subscriber(local_redis):
    async def run() -> list[str]:
        realtime = Realtime()
        await realtime.connect()
        gone = FakeSocket(lifetime_s=10)
        serving_gone = asyncio.create_task(realtime.serve_socket("DEMO", gone))
        await asyncio.sleep(0.3)
        await realtime.publish("DEMO", {"type": "fighter_update", "n": 0})

        local_redis.process.terminate()
        local_redis.process.wait(timeout=5)
        with contextlib.suppress(Exception):
            await asyncio.wait_for(serving_gone, timeout=5)
        local_redis.process = subprocess.Popen(
            ["redis-server", "--port", str(local_redis.port), "--save", "", "--appendonly", "no"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        await asyncio.sleep(0.5)

        fresh = FakeSocket(lifetime_s=3)
        serving_fresh = asyncio.create_task(realtime.serve_socket("DEMO", fresh))
        await asyncio.sleep(0.3)
        await realtime.publish("DEMO", {"type": "fighter_update", "n": 1})
        await asyncio.sleep(0.3)
        await fresh.close()
        with contextlib.suppress(Exception):
            await asyncio.wait_for(serving_fresh, timeout=5)
        await realtime.close()
        return fresh.sent

    received = asyncio.run(run())
    assert len(received) == 1 and '"n": 1' in received[0]
