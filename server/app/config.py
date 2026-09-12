import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

SERVER_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = SERVER_DIR.parent

API_HOST = os.environ.get("API_HOST", "0.0.0.0")
API_PORT = int(os.environ.get("API_PORT", "8000"))

UPLOAD_DIR = Path(os.environ.get("UPLOAD_DIR", SERVER_DIR / "uploads"))
SQLITE_PATH = Path(os.environ.get("SQLITE_PATH", SERVER_DIR / "mealee.sqlite"))
USDA_SQLITE_PATH = Path(os.environ.get("USDA_SQLITE_PATH", REPO_DIR / "data" / "usda.sqlite"))
USDA_API_KEY = os.environ.get("USDA_API_KEY", "DEMO_KEY")
USDA_API_URL = os.environ.get("USDA_API_URL", "https://api.nal.usda.gov/fdc/v1")
FOODS_YAML_PATH = Path(os.environ.get("FOODS_YAML_PATH", REPO_DIR / "data" / "foods.yaml"))
ARENA_HTML_PATH = Path(os.environ.get("ARENA_HTML_PATH", REPO_DIR / "arena" / "index.html"))

REDIS_URL = os.environ.get("REDIS_URL", "")
MONGODB_URI = os.environ.get("MONGODB_URI", "")
MONGODB_DB = os.environ.get("MONGODB_DB", "mealee")

AUTH0_DOMAIN = os.environ.get("AUTH0_DOMAIN", "")
AUTH0_CLIENT_ID = os.environ.get("AUTH0_CLIENT_ID", "")

IFM_API_KEY = os.environ.get("IFM_API_KEY", "")
IFM_BASE_URL = os.environ.get("IFM_BASE_URL", "https://api.ifm.ai/v1")
IFM_MODEL = os.environ.get("IFM_MODEL", "IFM/K2-Horizon-375B-A23B")
# api.ifm.ai rejects a multimodal messages.content array with
# "Invalid value for 'messages.content'", for every shape tried, so the vision fallback
# cannot run against it. Off unless someone points IFM_BASE_URL at an endpoint that
# accepts images; the same key is still used for the text consensus below.
IFM_VISION_ENABLED = os.environ.get("IFM_VISION_ENABLED", "").lower() in ("1", "true", "yes")
# Text models, used only to estimate a food the catalog and USDA both failed to supply.
# K2-Think-v2 is a reasoning model: it spends its budget in message.reasoning and
# returns empty content, so the non-reasoning Horizon model answers here too.
IFM_TEXT_MODEL = os.environ.get("IFM_TEXT_MODEL", "IFM/K2-Horizon-375B-A23B")
GROK_API_KEY = os.environ.get("GROK_API_KEY", "")
GROK_BASE_URL = os.environ.get("GROK_BASE_URL", "https://api.x.ai/v1")
GROK_MODEL = os.environ.get("GROK_MODEL", "grok-4.6")  # there is no plain "grok-4"
# Both models reason before answering; 8s was cutting the read off mid-body.
NUTRITION_ESTIMATE_TIMEOUT_S = float(os.environ.get("NUTRITION_ESTIMATE_TIMEOUT_S", "30"))
VISION_TIMEOUT_S = float(os.environ.get("VISION_TIMEOUT_S", "1.5"))

YOLO_WEIGHTS = os.environ.get("YOLO_WEIGHTS", "yolov8s-seg.pt")

# Nightly fights resolve at 21:00 in this zone. Pittsburgh for HackCMU.
LOCAL_TZ = os.environ.get("LOCAL_TZ", "America/New_York")
