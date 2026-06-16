import json
import unittest
from pathlib import Path
from unittest import mock

from script import registry


class RegistryHttpTests(unittest.TestCase):
    def test_load_registry_sets_user_agent(self):
        seen = {}

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def read(self):
                return b'{"version": 1}'

        def fake_urlopen(request, timeout):
            seen["user_agent"] = request.headers.get("User-agent")
            seen["timeout"] = timeout
            return Response()

        with mock.patch("urllib.request.urlopen", fake_urlopen):
            registry.load_registry(remote_url="https://example.test/registry.json")

        self.assertIn("OtakuRoomServerProxy", seen["user_agent"])
        self.assertEqual(seen["timeout"], 5)


class LocalRegistryDataTests(unittest.TestCase):
    def test_local_web_registry_validates(self):
        path = Path("D:/OtakuRoomWeb/network/registry.json")
        if not path.exists():
            self.skipTest("local web registry is not present")

        model = json.loads(path.read_text(encoding="utf-8"))
        registry.validate(model)


class RouteBackendTests(unittest.TestCase):
    def test_route_backend_must_define_route_service(self):
        model = {
            "version": 1,
            "services": {"netdata": {"parent": {"node": "pin-server-all"}}},
            "nodes": [
                {
                    "id": "pin-server-all",
                    "ipv4": "67.215.234.162",
                    "services": {"netdata": 19999, "ai_chat": 2084},
                },
                {
                    "id": "user-server",
                    "ipv4": "8.219.123.14",
                    "services": {},
                },
                {"id": "proxy-us-cn2-0", "ipv4": "69.63.221.26"},
            ],
            "edge_routes": [
                {
                    "id": "ai-chat",
                    "service": "ai_chat",
                    "entry_nodes": ["proxy-us-cn2-0"],
                    "listen_port": 2084,
                    "backend_node": "user-server",
                    "protocols": ["tcp"],
                }
            ],
        }

        with self.assertRaisesRegex(ValueError, "node user-server does not define service ai_chat"):
            registry.validate(model)

    def test_node_host_field_is_ignored(self):
        model = {
            "version": 1,
            "services": {"netdata": {"parent": {"node": "pin-server-all"}}},
            "nodes": [
                {
                    "id": "pin-server-all",
                    "host": "ipfs.otakuroom.net",
                    "ipv4": "67.215.234.162",
                    "services": {"netdata": 19999, "iperf": 5201},
                },
            ],
            "edge_routes": [],
        }

        registry.validate(model)
        self.assertEqual(
            registry.iperf_csv(model),
            "Name,Host,Port\npin-server-all,67.215.234.162,5201\n",
        )

    def test_iperf_csv_uses_node_ip_address_for_direct_endpoint(self):
        model = {
            "version": 1,
            "services": {"netdata": {"parent": {"node": "pin-server-all"}}},
            "nodes": [
                {
                    "id": "pin-server-all",
                    "ipv4": "67.215.234.162",
                    "services": {"netdata": 19999, "iperf": 5201},
                },
            ],
            "edge_routes": [],
        }

        self.assertEqual(
            registry.iperf_csv(model),
            "Name,Host,Port\npin-server-all,67.215.234.162,5201\n",
        )


if __name__ == "__main__":
    unittest.main()
