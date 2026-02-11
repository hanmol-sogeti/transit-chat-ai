import os

import pytest
from fastapi.testclient import TestClient

from main import SYSTEM_PROMPT, app, _load_stops


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


def test_system_prompt_defaults_to_swedish_and_now_from_current_location():
    text = SYSTEM_PROMPT.lower()
    assert "svenska" in text  # responds in Swedish
    assert "nu" in text  # default time is now
    assert "aktuell" in text or "aktuella" in text  # current location as origin
    assert "destination" in text  # trip target mentioned


def test_load_stops_reads_local_file(tmp_path, monkeypatch):
    stops_file = tmp_path / "stops.txt"
    stops_file.write_text(
        "stop_id,stop_name,stop_lat,stop_lon\n"
        "1,Alpha,59.1,17.1\n"
        "2,Beta,59.2,17.2\n",
        encoding="utf-8",
    )

    # Ensure cached stops and download path do not interfere.
    monkeypatch.setattr("main._stops_cache", None)
    monkeypatch.setattr("main.GTFS_STOPS_PATH", str(stops_file))
    monkeypatch.setattr("main._download_gtfs_sweden3", lambda: (_ for _ in ()).throw(AssertionError("should not download")))

    stops = _load_stops()

    assert len(stops) == 2
    assert stops[0].name == "Alpha"
    assert stops[1].id == "2"
    assert stops[1].lat == pytest.approx(59.2)


def test_stops_endpoint_serves_data_from_file(tmp_path, monkeypatch):
    stops_file = tmp_path / "stops.txt"
    stops_file.write_text(
        "stop_id,stop_name,stop_lat,stop_lon\n"
        "10,Test Stop,59.0,18.0\n",
        encoding="utf-8",
    )

    monkeypatch.setattr("main._stops_cache", None)
    monkeypatch.setattr("main.GTFS_STOPS_PATH", str(stops_file))
    monkeypatch.setattr("main._download_gtfs_sweden3", lambda: (_ for _ in ()).throw(AssertionError("should not download")))

    resp = client.get("/stops")

    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list) and data
    assert data[0]["id"] == "10"
    assert data[0]["name"] == "Test Stop"