"""Resolve every league's nightly fights at 21:00 local and push results to the arena.

The scheduler lives in the worker process, so the deployment runs exactly one uvicorn
worker (see Dockerfile and railway.toml). Two workers would resolve every fight twice.
"""

import asyncio
import logging
from zoneinfo import ZoneInfo

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app import game
from app.config import LOCAL_TZ
from app.db import League, Player, get_session
from app.realtime import realtime

log = logging.getLogger("mealee.nightly")

_scheduler = BackgroundScheduler(timezone=ZoneInfo(LOCAL_TZ))
_loop: asyncio.AbstractEventLoop | None = None


def resolve_all_leagues() -> int:
    session = get_session()
    resolved = 0
    for league in session.scalars(select(League)).all():
        players = session.scalars(select(Player).where(Player.league_id == league.code)).all()
        for player_a, player_b in game.nightly_pairings(players, game.today()):
            if player_b is None:
                continue
            fight = game.run_fight(session, league.code, player_a, player_b, "nightly")
            payload = game.fight_payload(session, fight)
            _publish(league.code, {"type": "fight_ended", "fight": payload})
            resolved += 1
    session.close()
    log.info("nightly: resolved %d fights", resolved)
    return resolved


def _publish(league_code: str, message: dict) -> None:
    if _loop is None:
        return
    future = asyncio.run_coroutine_threadsafe(realtime.publish(league_code, message), _loop)
    future.add_done_callback(
        lambda done: done.exception() and log.error("nightly publish for %s failed: %r", league_code, done.exception()))


def start(loop: asyncio.AbstractEventLoop) -> None:
    global _loop
    _loop = loop
    _scheduler.add_job(resolve_all_leagues, CronTrigger(hour=21, minute=0), id="nightly",
                       replace_existing=True)
    _scheduler.start()


def stop() -> None:
    if _scheduler.running:
        _scheduler.shutdown(wait=False)
