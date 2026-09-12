"""Player identity in MongoDB Atlas.

Atlas holds who a player is: display name, emoji, Auth0 subject, league, discoveries.
It never sits on the request path. Every write is submitted to a single worker thread
and the request returns without waiting, because an Atlas timeout must never fail a meal
upload or a fight. SQLite remains the source of truth for everything the game reads.
"""

import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from app.config import MONGODB_DB, MONGODB_URI

log = logging.getLogger("mealee.identity")

_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="atlas")
_client = None


def connect() -> None:
    global _client
    if not MONGODB_URI:
        log.warning("MONGODB_URI unset. Player identity will not be mirrored to Atlas.")
        return
    from pymongo import MongoClient
    _client = MongoClient(MONGODB_URI, serverSelectionTimeoutMS=3000, connectTimeoutMS=3000)
    _client.admin.command("ping")
    _client[MONGODB_DB]["players"].create_index("player_id", unique=True)
    _client[MONGODB_DB]["players"].create_index("auth0_sub")
    log.info("identity: connected to Atlas")


def _upsert(collection: str, key: dict, document: dict) -> None:
    try:
        _client[MONGODB_DB][collection].update_one(key, {"$set": document}, upsert=True)
    except Exception as error:
        log.warning("atlas write failed (%s): %s", collection, error)


def record_player(player_id: str, league_code: str, name: str, emoji: str,
                  auth0_sub: str | None) -> None:
    if _client is None:
        return
    _executor.submit(_upsert, "players", {"player_id": player_id}, {
        "player_id": player_id,
        "league_code": league_code,
        "name": name,
        "emoji": emoji,
        "auth0_sub": auth0_sub,
        "updated_at": datetime.utcnow(),
    })


def record_discovery(player_id: str, label: str, week_start: str) -> None:
    if _client is None:
        return
    _executor.submit(_upsert, "discoveries",
                     {"player_id": player_id, "label": label, "week_start": week_start},
                     {"player_id": player_id, "label": label, "week_start": week_start,
                      "found_at": datetime.utcnow()})


def record_fight_result(player_id: str, fight_id: str, won: bool, kind: str) -> None:
    if _client is None:
        return
    _executor.submit(_upsert, "fight_results", {"player_id": player_id, "fight_id": fight_id},
                     {"player_id": player_id, "fight_id": fight_id, "won": won, "kind": kind,
                      "at": datetime.utcnow()})
