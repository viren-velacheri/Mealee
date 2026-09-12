from datetime import date, datetime

from sqlalchemy import (Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text,
                        create_engine)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from app.config import SQLITE_PATH


class Base(DeclarativeBase):
    pass


class League(Base):
    __tablename__ = "leagues"
    code: Mapped[str] = mapped_column(String(4), primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    week_start: Mapped[date] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Player(Base):
    __tablename__ = "players"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    league_id: Mapped[str] = mapped_column(ForeignKey("leagues.code"), index=True)
    name: Mapped[str] = mapped_column(String(32))
    emoji: Mapped[str] = mapped_column(String(8))
    auth0_sub: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Meal(Base):
    __tablename__ = "meals"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    taken_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    image_path: Mapped[str] = mapped_column(String(256))
    image_w: Mapped[int] = mapped_column(Integer)
    image_h: Mapped[int] = mapped_column(Integer)
    scale_ref_type: Mapped[str] = mapped_column(String(16))
    scale_px_per_mm: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(16), default="confirmed")


class MealItem(Base):
    __tablename__ = "meal_items"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    meal_id: Mapped[str] = mapped_column(ForeignKey("meals.id"), index=True)
    label: Mapped[str] = mapped_column(String(160))
    fdc_id: Mapped[int] = mapped_column(Integer)
    grams: Mapped[float] = mapped_column(Float)
    grams_low: Mapped[float] = mapped_column(Float)
    grams_high: Mapped[float] = mapped_column(Float)
    confidence: Mapped[float] = mapped_column(Float)
    area_px: Mapped[int] = mapped_column(Integer)
    polygon_json: Mapped[str] = mapped_column(Text)
    corrected: Mapped[bool] = mapped_column(Boolean, default=False)


class CatalogFood(Base):
    __tablename__ = "catalog_foods"
    fdc_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    label: Mapped[str] = mapped_column(String(160))
    source: Mapped[str] = mapped_column(String(64))
    kcal: Mapped[float] = mapped_column(Float)
    protein_g: Mapped[float] = mapped_column(Float)
    fiber_g: Mapped[float] = mapped_column(Float)
    sodium_mg: Mapped[float] = mapped_column(Float)
    caffeine_mg: Mapped[float] = mapped_column(Float, default=0)
    is_vegetable: Mapped[bool] = mapped_column(Boolean, default=False)


class IntakeEvent(Base):
    __tablename__ = "intake_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    day: Mapped[date] = mapped_column(Date, index=True)
    kind: Mapped[str] = mapped_column(String(8))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Fighter(Base):
    __tablename__ = "fighters"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    day: Mapped[date] = mapped_column(Date, index=True)
    attack: Mapped[float] = mapped_column(Float)
    defense: Mapped[float] = mapped_column(Float)
    stamina: Mapped[float] = mapped_column(Float)
    speed: Mapped[float] = mapped_column(Float)
    focus: Mapped[float] = mapped_column(Float)
    recovery: Mapped[float] = mapped_column(Float)
    crash_turn: Mapped[int | None] = mapped_column(Integer, nullable=True)
    hp_max: Mapped[int] = mapped_column(Integer)
    first_strike: Mapped[bool] = mapped_column(Boolean)
    reasons_json: Mapped[str] = mapped_column(Text, default="[]")
    computed_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Fight(Base):
    __tablename__ = "fights"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    league_id: Mapped[str] = mapped_column(ForeignKey("leagues.code"), index=True)
    a_player_id: Mapped[str] = mapped_column(ForeignKey("players.id"))
    b_player_id: Mapped[str] = mapped_column(ForeignKey("players.id"))
    a_fighter_id: Mapped[str] = mapped_column(ForeignKey("fighters.id"))
    b_fighter_id: Mapped[str] = mapped_column(ForeignKey("fighters.id"))
    seed: Mapped[int] = mapped_column(Integer)
    winner_id: Mapped[str] = mapped_column(ForeignKey("players.id"))
    kind: Mapped[str] = mapped_column(String(8))
    a_damage_dealt: Mapped[int] = mapped_column(Integer, default=0)
    b_damage_dealt: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class FightTurn(Base):
    __tablename__ = "fight_turns"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fight_id: Mapped[str] = mapped_column(ForeignKey("fights.id"), index=True)
    turn: Mapped[int] = mapped_column(Integer)
    actor: Mapped[str] = mapped_column(String(1))
    action: Mapped[str] = mapped_column(String(8))
    damage: Mapped[int] = mapped_column(Integer)
    a_hp: Mapped[int] = mapped_column(Integer)
    b_hp: Mapped[int] = mapped_column(Integer)
    note: Mapped[str] = mapped_column(String(128))


class Discovery(Base):
    __tablename__ = "discoveries"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    label: Mapped[str] = mapped_column(String(32))
    week_start: Mapped[date] = mapped_column(Date)
    thumbnail_path: Mapped[str] = mapped_column(String(256))
    found_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


engine = create_engine(f"sqlite:///{SQLITE_PATH}", connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def init_db() -> None:
    SQLITE_PATH.parent.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(engine)


def get_session() -> Session:
    return SessionLocal()


def request_session():
    session = get_session()
    try:
        yield session
    finally:
        session.close()
