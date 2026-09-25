from fastapi.testclient import TestClient

from app import app

client = TestClient(app)


def test_healthz():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_info_has_expected_fields():
    body = client.get("/api/info").json()
    assert body["service"] == "backend"
    for key in ("version", "environment", "pod", "uptime_seconds"):
        assert key in body


def test_tip():
    r = client.get("/api/tip")
    assert r.status_code == 200
    assert len(r.json()["tip"]) > 10


# sdfsdf