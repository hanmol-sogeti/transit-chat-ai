import os
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

SYSTEM_PROMPT = (
    "You are a UL transit planner. You can: plan trips, suggest nearby stops, list routes, and outline ticket booking steps. "
    "Keep replies concise: 2-4 bullet points covering origin, destination, time, and suggested route, plus the next action (e.g., open map, pick stop, choose ticket)."
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


@app.get("/health")
def health():
    return {"status": "ok"}


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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8001")))
