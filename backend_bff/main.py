import csv
import io
import logging
import os
import zipfile
from pathlib import Path
from typing import List, Optional

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Transit Chat BFF", version="0.2.0")

allowed_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",")]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

AZURE_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT", "").rstrip("/")
AZURE_DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT", "")
AZURE_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "")
AZURE_API_KEY = os.getenv("AZURE_OPENAI_API_KEY", "")
GTFS_STOPS_PATH = os.getenv("GTFS_STOPS_PATH", "data/stops.txt")
GTFS_SWEDEN3_STATIC_KEY = os.getenv("GTFS_SWEDEN3_STATIC_KEY", "")
GTFS_SWEDEN3_STATIC_URL = os.getenv(
    "GTFS_SWEDEN3_STATIC_URL", "https://opendata.samtrafiken.se/gtfs/sweden3/latest.zip"
)

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "Du är en UL reseplanerare och svarar på svenska. Hjälp användaren att boka resor snabbt. "
    "Standard: avresa nu och starta från användarens aktuella position om inget annat anges. "
    "Om användaren bara anger destination (t.ex. 'jag vill boka en bussresa till Flogsta'), anta nu som tid och nuvarande plats som start. "
    "Gör svaret kort i 2-4 punkter: ursprung, destination, avgångstid, förslag på linje/rutt och nästa åtgärd (öppna karta, välj hållplats eller köp biljett)."
)

class ChatMessage(BaseModel):
    role: str = Field(..., pattern="^(system|user|assistant)$")
    content: str


class ChatRequest(BaseModel):
    messages: List[ChatMessage]
    temperature: float = 0.3
    max_tokens: Optional[int] = 256


class ChatResponse(BaseModel):
    content: str


class PlanRequest(BaseModel):
    prompt: str
    temperature: float = 0.3
    max_tokens: Optional[int] = 180


class StopOut(BaseModel):
    id: str
    name: str
    lat: float
    lon: float


_stops_cache: Optional[List[StopOut]] = None


@app.get("/health")
def health():
    return {"status": "ok"}


def _parse_stops(reader: csv.DictReader) -> List[StopOut]:
    required = {"stop_id", "stop_name", "stop_lat", "stop_lon"}
    if not required.issubset(set(reader.fieldnames or [])):
        raise ValueError("GTFS stops file missing required columns")

    stops: List[StopOut] = []
    for row in reader:
        try:
            stops.append(
                StopOut(
                    id=row.get("stop_id", "").strip(),
                    name=row.get("stop_name", "").strip(),
                    lat=float(row.get("stop_lat", 0)),
                    lon=float(row.get("stop_lon", 0)),
                )
            )
        except Exception:
            logger.warning("Skipping invalid stop row", exc_info=True)
            continue
    return stops


def _download_gtfs_sweden3() -> List[StopOut]:
    if not GTFS_SWEDEN3_STATIC_KEY:
        raise RuntimeError("GTFS_SWEDEN3_STATIC_KEY is not set; cannot download GTFS")

    url = (
        f"{GTFS_SWEDEN3_STATIC_URL}?key={GTFS_SWEDEN3_STATIC_KEY}"
        if "?" not in GTFS_SWEDEN3_STATIC_URL
        else f"{GTFS_SWEDEN3_STATIC_URL}&key={GTFS_SWEDEN3_STATIC_KEY}"
    )
    logger.info("Downloading GTFS Sweden3 feed from %s", url)
    with httpx.stream("GET", url, timeout=60.0) as resp:
        resp.raise_for_status()
        content = resp.read()

    with zipfile.ZipFile(io.BytesIO(content)) as zf:
        if "stops.txt" not in zf.namelist():
            raise FileNotFoundError("stops.txt not found inside GTFS zip")
        with zf.open("stops.txt") as f:
            reader = csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))
            return _parse_stops(reader)


def _load_stops() -> List[StopOut]:
    global _stops_cache
    if _stops_cache is not None:
        return _stops_cache

    path = Path(GTFS_STOPS_PATH)
    try:
        if path.exists():
            with path.open("r", encoding="utf-8-sig", newline="") as fh:
                stops = _parse_stops(csv.DictReader(fh))
            logger.info("Loaded %d stops from %s", len(stops), path)
        else:
            logger.warning("GTFS stops file not found at %s; attempting Sweden3 download", path)
            stops = _download_gtfs_sweden3()
            logger.info("Loaded %d stops from Sweden3 feed", len(stops))
    except Exception as exc:
        logger.exception("Failed to load GTFS stops")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    if not stops:
        raise HTTPException(status_code=500, detail="No stops loaded from GTFS stops source")

    _stops_cache = stops
    return stops


async def call_openai(messages: List[dict], temperature: float, max_tokens: Optional[int]) -> str:
    if not all([AZURE_ENDPOINT, AZURE_DEPLOYMENT, AZURE_API_VERSION, AZURE_API_KEY]):
        raise HTTPException(status_code=500, detail="Server is missing Azure config")

    url = f"{AZURE_ENDPOINT}/openai/deployments/{AZURE_DEPLOYMENT}/chat/completions?api-version={AZURE_API_VERSION}"
    headers = {"api-key": AZURE_API_KEY, "Content-Type": "application/json"}
    payload = {
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(url, headers=headers, json=payload)
    if resp.status_code >= 300:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)

    data = resp.json()
    content = ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "")
    return content


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    content = await call_openai([m.model_dump() for m in req.messages], req.temperature, req.max_tokens)
    return ChatResponse(content=content)


@app.post("/plan", response_model=ChatResponse)
async def plan(req: PlanRequest):
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": req.prompt},
    ]
    content = await call_openai(messages, req.temperature, req.max_tokens)
    return ChatResponse(content=content)


@app.get("/stops", response_model=List[StopOut])
def list_stops(
    min_lat: Optional[float] = None,
    max_lat: Optional[float] = None,
    min_lon: Optional[float] = None,
    max_lon: Optional[float] = None,
    limit: int = 5000,
):
    stops = _load_stops()

    def within_bounds(stop: StopOut) -> bool:
        if min_lat is not None and stop.lat < min_lat:
            return False
        if max_lat is not None and stop.lat > max_lat:
            return False
        if min_lon is not None and stop.lon < min_lon:
            return False
        if max_lon is not None and stop.lon > max_lon:
            return False
        return True

    filtered = [s for s in stops if within_bounds(s)] if any(v is not None for v in [min_lat, max_lat, min_lon, max_lon]) else stops

    if limit and limit > 0:
        filtered = filtered[:limit]

    return filtered


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8001")))
