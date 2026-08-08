import pytest
from fastapi.testclient import TestClient
from main import app


client = TestClient(app)


class TestMVPEndpoints:
    """Test cases for User Brain, Memory, and Plugins API routes."""

    def test_user_brain_endpoints(self):
        # 1. Get profile
        res = client.get("/user_brain/profile")
        assert res.status_code == 200
        data = res.json()
        assert data["user_id"] == "default_user"

        # 2. Update profile
        data["display_name"] = "Alice"
        data["goals"] = ["Master clean architecture"]
        res_post = client.post("/user_brain/profile", json=data)
        assert res_post.status_code == 200
        data_post = res_post.json()
        assert data_post["display_name"] == "Alice"
        assert "Master clean architecture" in data_post["goals"]

    def test_memory_endpoints(self):
        # 1. Get memories (should have seeds)
        res = client.get("/memory/")
        assert res.status_code == 200
        mems = res.json()
        assert len(mems) >= 2

        # 2. Add memory
        res_add = client.post("/memory/?content=User loves fast coding responses")
        assert res_add.status_code == 200
        added = res_add.json()
        assert added["content"] == "User loves fast coding responses"
        mem_id = added["id"]

        # 3. Get memories again
        res_get = client.get("/memory/")
        assert any(m["id"] == mem_id for m in res_get.json())

        # 4. Delete memory
        res_del = client.delete(f"/memory/{mem_id}")
        assert res_del.status_code == 200
        assert res_del.json()["success"] is True

    def test_plugins_endpoints(self):
        # 1. List plugins
        res = client.get("/plugins/")
        assert res.status_code == 200
        plugins = res.json()
        names = [p["name"] for p in plugins]
        assert "calculator" in names
        assert "weather" in names

        # 2. Execute plugin
        res_exec = client.post("/plugins/execute?name=calculator", json={"expression": "100 / 4"})
        assert res_exec.status_code == 200
        assert res_exec.json()["success"] is True
        assert res_exec.json()["result"] == "25.0"
