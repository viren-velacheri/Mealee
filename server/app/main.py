import asyncio
import contextlib
import json
import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

import cv2
import httpx
import numpy as np
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile, WebSocket
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import UnidentifiedImageError
from pydantic import BaseModel
from redis.exceptions import RedisError
from sqlalchemy import select
from sqlalchemy.orm import Session
from starlette.websockets import WebSocketDisconnect

from app import foods as food_catalog
from app import game, identity, nightly, portions
from app.config import ARENA_HTML_PATH, UPLOAD_DIR
from app.db import (CatalogFood, Fight, IntakeEvent, League, Meal, MealItem, Player,
                    init_db, request_session)
from app.foods import class_labels, food_classes, warn_if_no_usda
from app.realtime import realtime

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger("mealee")

MAX_UPLOAD_BYTES = 8 * 1024 * 1024
THUMBNAIL_PX = 112


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    (UPLOAD_DIR / "thumbs").mkdir(exist_ok=True)
    warn_if_no_usda()
    await realtime.connect()
    identity.connect()
    nightly.start(asyncio.get_running_loop())
    yield
    nightly.stop()
    await realtime.close()


app = FastAPI(title="Mealee", lifespan=lifespan)
app.mount("/uploads", StaticFiles(directory=str(UPLOAD_DIR), check_dir=False), name="uploads")


@app.exception_handler(HTTPException)
async def http_error(request: Request, error: HTTPException):
    body = error.detail if isinstance(error.detail, dict) else {"error": str(error.detail), "hint": ""}
    return JSONResponse(status_code=error.status_code, content=body)


@app.exception_handler(Exception)
async def unhandled(request: Request, error: Exception):
    log.exception("unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"error": "internal", "hint": "check server logs"})


def _player_or_422(session, player_id: str) -> Player:
    player = session.get(Player, player_id)
    if player is None:
        raise HTTPException(status_code=422, detail={"error": "unknown player", "hint": "join a league first"})
    return player


def _league_or_404(session, code: str) -> League:
    league = session.get(League, code.upper())
    if league is None:
        raise HTTPException(status_code=404, detail={"error": "unknown league", "hint": "check the 4-letter code"})
    return league


@app.get("/health")
def health():
    return {"ok": True, "classes": len(class_labels()), "time": datetime.utcnow().isoformat() + "Z"}


@app.get("/foods/search")
async def search_foods(q: str, session: Session = Depends(request_session)):
    query = q.strip()[:60]
    if len(query) < 2:
        raise HTTPException(status_code=400, detail={"error": "search too short", "hint": "enter at least 2 characters"})
    local_results = food_catalog.local_food_search(query)
    try:
        usda_results = await food_catalog.search_usda(query)
    except (httpx.HTTPError, KeyError, TypeError, ValueError) as error:
        if local_results:
            log.warning("USDA food search failed; returning local matches: %s", error)
            return {"items": [result.as_dict() for result in local_results]}
        raise HTTPException(status_code=503, detail={
            "error": "food search unavailable", "hint": "check the server connection and try again",
        })

    for result in usda_results:
        session.merge(CatalogFood(
            fdc_id=result.fdc_id, label=result.label, source=result.source,
            kcal=result.kcal, protein_g=result.protein_g, fiber_g=result.fiber_g,
            sodium_mg=result.sodium_mg, caffeine_mg=result.caffeine_mg,
            is_vegetable=result.is_vegetable,
        ))
    session.commit()
    combined = local_results + usda_results
    unique = {}
    for result in combined:
        unique.setdefault(result.fdc_id, result)
    return {"items": [result.as_dict() for result in list(unique.values())[:16]]}


class CreateLeague(BaseModel):
    name: str


@app.post("/leagues")
def create_league(body: CreateLeague, session: Session = Depends(request_session)):
    league = League(code=game.new_league_code(session), name=body.name.strip()[:64],
                    week_start=game.week_start(game.today()))
    session.add(league)
    session.commit()
    return {"code": league.code}


@app.get("/leagues/{code}")
def get_league(code: str, session: Session = Depends(request_session)):
    return game.league_payload(session, _league_or_404(session, code))


@app.get("/leagues/{code}/latest-fight")
async def get_latest_fight(code: str, session: Session = Depends(request_session)):
    league = _league_or_404(session, code)
    fight = game.latest_fight(session, league.code)
    if fight is None:
        raise HTTPException(status_code=404, detail={"error": "no fights yet", "hint": "run a quick match"})
    return game.fight_payload(session, fight)


class JoinLeague(BaseModel):
    league_code: str
    name: str
    emoji: str
    auth0_sub: str | None = None


@app.post("/players")
def join_league(body: JoinLeague, session: Session = Depends(request_session)):
    league = _league_or_404(session, body.league_code)
    player = Player(id=str(uuid.uuid4()), league_id=league.code, name=body.name.strip()[:32],
                    emoji=body.emoji[:8], auth0_sub=body.auth0_sub)
    session.add(player)
    session.commit()
    game.compute_fighter(session, player.id)
    identity.record_player(player.id, league.code, player.name, player.emoji, body.auth0_sub)
    return {"player_id": player.id, "league": game.league_payload(session, league)}


@app.get("/fighters/{player_id}/today")
def fighter_today(player_id: str, session: Session = Depends(request_session)):
    _player_or_422(session, player_id)
    return game.fighter_payload(game.compute_fighter(session, player_id))


class Intake(BaseModel):
    player_id: str
    kind: str


@app.post("/intake")
async def intake(body: Intake, session: Session = Depends(request_session)):
    if body.kind not in ("water", "coffee"):
        raise HTTPException(status_code=400, detail={"error": "bad kind", "hint": "water or coffee"})
    player = _player_or_422(session, body.player_id)
    session.add(IntakeEvent(player_id=player.id, day=game.today(), kind=body.kind))
    session.commit()
    fighter = game.compute_fighter(session, player.id)
    totals, _ = game.day_totals(session, player.id, game.today())
    await realtime.publish(player.league_id, {
        "type": "fighter_update", "player_id": player.id, "fighter": game.fighter_payload(fighter)})
    return {"day_totals": totals.as_dict(), "fighter": game.fighter_payload(fighter)}


def _save_thumbnail(image_bgr, mask, player_id: str, label: str) -> str:
    ys, xs = mask.nonzero()
    crop = image_bgr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    scale = THUMBNAIL_PX / max(crop.shape[:2])
    crop = cv2.resize(crop, (max(1, int(crop.shape[1] * scale)), max(1, int(crop.shape[0] * scale))))
    relative = f"thumbs/{player_id}_{label.replace(' ', '_')}_{game.week_start(game.today())}.jpg"
    cv2.imwrite(str(UPLOAD_DIR / relative), crop, [cv2.IMWRITE_JPEG_QUALITY, 82])
    return relative


@app.post("/meals")
async def upload_meal(player_id: str = Form(...), image: UploadFile = File(...),
                      session: Session = Depends(request_session)):
    player = _player_or_422(session, player_id)
    jpeg_bytes = await image.read()
    if not jpeg_bytes or len(jpeg_bytes) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=400, detail={"error": "bad image", "hint": "send a JPEG under 8 MB"})

    try:
        analysis = await asyncio.to_thread(portions.analyze, jpeg_bytes)
    except (UnidentifiedImageError, OSError):
        raise HTTPException(status_code=400, detail={"error": "bad image", "hint": "could not read that photo"})

    meal_id = str(uuid.uuid4())
    image_path = f"{meal_id}.jpg"
    (UPLOAD_DIR / image_path).write_bytes(jpeg_bytes)

    meal = Meal(id=meal_id, player_id=player.id, image_path=image_path,
                image_w=analysis.image_w, image_h=analysis.image_h,
                scale_ref_type=analysis.scale_type, scale_px_per_mm=analysis.px_per_mm,
                status="draft")
    session.add(meal)

    for region in analysis.regions:
        food = food_classes().get(region.label)
        session.add(MealItem(
            id=str(uuid.uuid4()), meal_id=meal_id, label=region.label,
            fdc_id=food.fdc_id if food else 0, grams=region.grams,
            grams_low=region.grams_low, grams_high=region.grams_high,
            confidence=region.confidence, area_px=region.area_px,
            polygon_json=json.dumps(region.polygon)))
    session.commit()

    new_labels = game.undiscovered_labels(
        session, player.id, [region.label for region in analysis.regions])
    payload = game.meal_payload(session, meal, new_labels)
    log.info("meal %s: %d regions, scale=%s %.2f px/mm, %.2fs", meal_id, len(analysis.regions),
             analysis.scale_type, analysis.px_per_mm, analysis.elapsed_s)
    return payload


def _meal_thumbnails(session, meal: Meal) -> dict[str, str]:
    image_bgr = portions.decode_image((UPLOAD_DIR / meal.image_path).read_bytes())
    thumbs: dict[str, str] = {}
    items = session.scalars(select(MealItem).where(MealItem.meal_id == meal.id)).all()
    for item in items:
        if item.label not in food_classes():
            continue
        polygon = json.loads(item.polygon_json)
        if len(polygon) < 3:
            continue
        mask = cv2.fillPoly(np.zeros((meal.image_h, meal.image_w), dtype=np.uint8),
                            [np.array(polygon, dtype=np.int32)], 1).astype(bool)
        thumbs[item.label] = _save_thumbnail(image_bgr, mask, meal.player_id, item.label)
    return thumbs


@app.post("/meals/{meal_id}/confirm")
async def confirm_meal(meal_id: str, session: Session = Depends(request_session)):
    meal = session.get(Meal, meal_id)
    if meal is None:
        raise HTTPException(status_code=404, detail={"error": "unknown meal", "hint": "scan the meal again"})
    if meal.status == "confirmed":
        return game.meal_payload(session, meal)

    thumbs = _meal_thumbnails(session, meal)
    meal.status = "confirmed"
    session.commit()
    new_labels = game.record_discoveries(session, meal.player_id, thumbs)
    payload = game.meal_payload(session, meal, new_labels)
    player = session.get(Player, meal.player_id)
    await realtime.publish(player.league_id, {
        "type": "fighter_update", "player_id": player.id, "fighter": payload["fighter"]})
    return payload


@app.delete("/meals/{meal_id}")
def discard_meal(meal_id: str, session: Session = Depends(request_session)):
    meal = session.get(Meal, meal_id)
    if meal is None:
        raise HTTPException(status_code=404, detail={"error": "unknown meal", "hint": "it may already be discarded"})
    if meal.status != "draft":
        raise HTTPException(status_code=409, detail={"error": "meal already confirmed", "hint": "confirmed meals cannot be discarded"})

    items = session.scalars(select(MealItem).where(MealItem.meal_id == meal.id)).all()
    for item in items:
        session.delete(item)
    session.delete(meal)
    session.commit()
    (UPLOAD_DIR / meal.image_path).unlink(missing_ok=True)
    return {"ok": True}


class MealItemUpdate(BaseModel):
    label: str | None = None
    fdc_id: int | None = None
    grams: float | None = None


class MealItemCreate(BaseModel):
    fdc_id: int
    grams: float


def _food_choice(session, label: str | None, fdc_id: int | None) -> tuple[str, int, bool]:
    if fdc_id is not None:
        fixed = next((food for food in food_classes().values() if food.fdc_id == fdc_id), None)
        if fixed is not None:
            return fixed.label, fixed.fdc_id, True
        catalog_food = session.get(CatalogFood, fdc_id)
        if catalog_food is not None:
            return catalog_food.label, catalog_food.fdc_id, False
    if label in food_classes():
        food = food_classes()[label]
        return food.label, food.fdc_id, True
    raise HTTPException(status_code=400, detail={"error": "unknown food", "hint": "search for the food first"})


def _meal_and_item(session, meal_id: str, item_id: str) -> tuple[Meal, MealItem]:
    meal = session.get(Meal, meal_id)
    item = session.get(MealItem, item_id)
    if meal is None or item is None or item.meal_id != meal_id:
        raise HTTPException(status_code=404, detail={"error": "unknown item", "hint": "reload the meal"})
    return meal, item


@app.patch("/meals/{meal_id}/items/{item_id}")
async def relabel_item(meal_id: str, item_id: str, body: MealItemUpdate,
                       session: Session = Depends(request_session)):
    meal, item = _meal_and_item(session, meal_id, item_id)
    if body.label is not None or body.fdc_id is not None:
        item.label, item.fdc_id, is_fixed = _food_choice(session, body.label, body.fdc_id)
        if body.grams is None and is_fixed and item.area_px > 0:
            item.grams, item.grams_low, item.grams_high = portions.regrams(
                item.label, item.area_px, meal.scale_px_per_mm)
    if body.grams is not None:
        if not 0.1 <= body.grams <= 5000:
            raise HTTPException(status_code=400, detail={"error": "bad amount", "hint": "enter grams between 0.1 and 5000"})
        item.grams = body.grams
        item.grams_low, item.grams_high = body.grams * 0.7, body.grams * 1.3
    item.corrected = True
    session.commit()

    if meal.status == "draft":
        new_labels = game.undiscovered_labels(session, meal.player_id, [item.label])
        return game.meal_payload(session, meal, new_labels)

    image_bgr = portions.decode_image((UPLOAD_DIR / meal.image_path).read_bytes())
    polygon = json.loads(item.polygon_json)
    mask = cv2.fillPoly(np.zeros((meal.image_h, meal.image_w), dtype=np.uint8),
                        [np.array(polygon, dtype=np.int32)], 1).astype(bool)
    new_labels = game.record_discoveries(session, meal.player_id, {
        item.label: _save_thumbnail(image_bgr, mask, meal.player_id, item.label)})
    payload = game.meal_payload(session, meal, new_labels)
    player = session.get(Player, meal.player_id)
    await realtime.publish(player.league_id, {
        "type": "fighter_update", "player_id": player.id, "fighter": payload["fighter"]})
    return payload


@app.post("/meals/{meal_id}/items")
def add_meal_item(meal_id: str, body: MealItemCreate,
                  session: Session = Depends(request_session)):
    meal = session.get(Meal, meal_id)
    if meal is None:
        raise HTTPException(status_code=404, detail={"error": "unknown meal", "hint": "scan the meal again"})
    if meal.status != "draft":
        raise HTTPException(status_code=409, detail={"error": "meal already confirmed", "hint": "edit before confirming"})
    if not 0.1 <= body.grams <= 5000:
        raise HTTPException(status_code=400, detail={"error": "bad amount", "hint": "enter grams between 0.1 and 5000"})
    label, fdc_id, _ = _food_choice(session, None, body.fdc_id)
    session.add(MealItem(
        id=str(uuid.uuid4()), meal_id=meal.id, label=label, fdc_id=fdc_id,
        grams=body.grams, grams_low=body.grams * 0.7, grams_high=body.grams * 1.3,
        confidence=1, area_px=0, polygon_json="[]", corrected=True,
    ))
    session.commit()
    new_labels = game.undiscovered_labels(session, meal.player_id, [label])
    return game.meal_payload(session, meal, new_labels)


@app.delete("/meals/{meal_id}/items/{item_id}")
def delete_meal_item(meal_id: str, item_id: str,
                     session: Session = Depends(request_session)):
    meal, item = _meal_and_item(session, meal_id, item_id)
    if meal.status != "draft":
        raise HTTPException(status_code=409, detail={"error": "meal already confirmed", "hint": "edit before confirming"})
    session.delete(item)
    session.commit()
    return game.meal_payload(session, meal)


@app.get("/players/{player_id}/discoveries")
def discoveries(player_id: str, session: Session = Depends(request_session)):
    _player_or_422(session, player_id)
    return game.discoveries_payload(session, player_id)


class StartFight(BaseModel):
    a_player_id: str
    b_player_id: str
    kind: str = "quick"


@app.post("/fights")
async def start_fight(body: StartFight, session: Session = Depends(request_session)):
    if body.kind not in ("quick", "nightly"):
        raise HTTPException(status_code=400, detail={"error": "bad kind", "hint": "quick or nightly"})
    player_a = _player_or_422(session, body.a_player_id)
    player_b = _player_or_422(session, body.b_player_id)
    if player_a.id == player_b.id:
        raise HTTPException(status_code=400, detail={"error": "same player", "hint": "pick an opponent"})
    if player_a.league_id != player_b.league_id:
        raise HTTPException(status_code=400, detail={"error": "different leagues", "hint": "both players must share a league"})

    fight = game.run_fight(session, player_a.league_id, player_a, player_b, body.kind)
    payload = game.fight_payload(session, fight)
    await realtime.publish(player_a.league_id, {"type": "fight_started", "fight": payload})
    await realtime.publish(player_a.league_id, {"type": "fight_ended", "fight": payload})
    return payload


@app.get("/fights/{fight_id}")
def get_fight(fight_id: str, session: Session = Depends(request_session)):
    fight = session.get(Fight, fight_id)
    if fight is None:
        raise HTTPException(status_code=404, detail={"error": "unknown fight", "hint": "check the id"})
    return game.fight_payload(session, fight)


@app.websocket("/ws/league/{code}")
async def league_socket(socket: WebSocket, code: str):
    try:
        await realtime.serve_socket(code.upper(), socket)
    except WebSocketDisconnect:
        return
    except RedisError as error:
        log.warning("league socket %s: redis unavailable: %s", code, error)
        with contextlib.suppress(Exception):
            await socket.close(code=1013)
    except asyncio.TimeoutError:
        with contextlib.suppress(Exception):
            await socket.close(code=1000)


@app.get("/arena/{code}", response_class=HTMLResponse)
def arena(code: str):
    return HTMLResponse(ARENA_HTML_PATH.read_text())


@app.get("/")
def root():
    return {"app": "mealee", "arena": "/arena/{code}", "health": "/health"}
