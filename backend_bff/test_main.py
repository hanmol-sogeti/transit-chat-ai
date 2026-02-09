import os

import pytest
from fastapi.testclient import TestClient

from main import app


def _has_azure_env() -> bool:
    required = [
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_OPENAI_DEPLOYMENT",
        "AZURE_OPENAI_API_VERSION",
        "AZURE_OPENAI_API_KEY",
    ]
    return all(os.getenv(k, "").strip() for k in required)


client = TestClient(app)


@pytest.mark.skipif(not _has_azure_env(), reason="Azure env vars missing; integration test skipped")
def test_plan_endpoint_returns_content():
    payload = {
        "prompt": "Plan a trip from Main Station to Central Park at 5pm with minimal transfers",
        "temperature": 0.2,
        "max_tokens": 120,
    }

    resp = client.post("/plan", json=payload)

    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert isinstance(data, dict)
    assert data.get("content", "").strip() != ""


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}