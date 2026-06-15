#!/usr/bin/env python3
import argparse
import csv
import io
import json
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path


REMOTE_REGISTRY_URL = "https://www.otakuroom.net/network/registry.json"
HTTP_USER_AGENT = "OtakuRoomServerProxy/1.0"
WEB_REGISTRY = Path("D:/OtakuRoomWeb/network/registry.json")
PIN_PROXY_FILE = Path("D:/OtakuRoomPinServer/param/proxy/global.txt")
FORBIDDEN_PUBLIC_KEYS = {"NETDATA_API_KEY", "api_key", "password", "secret", "token"}
PRIMARY_NODE_ID = "pin-server-all"


def load_registry(path=None, remote_url=None):
    if path:
        return json.loads(Path(path).read_text(encoding="utf-8"))

    request = urllib.request.Request(
        remote_url or REMOTE_REGISTRY_URL,
        headers={"User-Agent": HTTP_USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def node_map(registry):
    return {node["id"]: node for node in registry["nodes"]}


def public_address(node):
    return node.get("host") or node.get("ipv4") or node.get("ipv6")


def node_services(node):
    return node.get("services") or {}


def ip_addresses(node):
    addresses = []
    if node.get("ipv4"):
        addresses.append(("ipv4", node["ipv4"]))
    if node.get("ipv6"):
        addresses.append(("ipv6", node["ipv6"]))
    return addresses


def select_address(node, node_id, address=None, require_ip=False):
    if address:
        if address == "public":
            host = public_address(node)
        elif address in ("host", "ipv4", "ipv6"):
            host = node.get(address)
        else:
            raise ValueError(f"node {node_id} has invalid address selector: {address}")
    else:
        host = node.get("ipv4") if require_ip else public_address(node)
    if not host:
        label = address or ("ipv4" if require_ip else "public")
        raise ValueError(f"node {node_id} has no usable {label} address")
    return host


def service_endpoint(registry, node_id, service_name, require_ip=False, address=None):
    nodes = node_map(registry)
    if node_id not in nodes:
        raise ValueError(f"unknown node: {node_id}")
    node = nodes[node_id]
    services = node_services(node)
    if service_name not in services:
        raise ValueError(f"node {node_id} does not define service {service_name}")
    host = select_address(node, node_id, address=address, require_ip=require_ip)
    return host, services[service_name]


def direct_service_endpoints(registry, service_name):
    for node in registry.get("nodes", []):
        if service_name in node_services(node):
            node_id = node["id"]
            host, port = service_endpoint(registry, node_id, service_name)
            yield {
                "name": node_id,
                "node_id": node_id,
                "host": host,
                "port": port,
                "source": "direct",
            }


def edge_routes_for_service(registry, service_name):
    return [route for route in registry.get("edge_routes", []) if route.get("service") == service_name]


def edge_service_endpoints(registry, service_name):
    nodes = node_map(registry)
    for route in edge_routes_for_service(registry, service_name):
        route_id = route["id"]
        for node_id in route["entry_nodes"]:
            node = nodes[node_id]
            for family, host in ip_addresses(node):
                if family == "ipv4":
                    name = f"{node_id}-via-{route_id}"
                else:
                    name = f"{node_id}-{family}-via-{route_id}"
                yield {
                    "name": name,
                    "node_id": node_id,
                    "host": host,
                    "port": route["listen_port"],
                    "route_id": route_id,
                    "source": "edge",
                    "address_family": family,
                }


def service_endpoints(registry, service_name, include_direct=True, include_edge=True):
    if include_direct:
        yield from direct_service_endpoints(registry, service_name)
    if include_edge:
        yield from edge_service_endpoints(registry, service_name)


def ensure_no_secret(value, path="$"):
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower()
            if key in FORBIDDEN_PUBLIC_KEYS or any(word in lowered for word in ("secret", "password", "token", "api_key")):
                raise ValueError(f"secret-looking key is not allowed in public registry: {path}.{key}")
            ensure_no_secret(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            ensure_no_secret(child, f"{path}[{index}]")
    elif isinstance(value, str):
        if "NETDATA_API_KEY" in value or "replace-with-private" in value:
            raise ValueError(f"secret-looking value is not allowed in public registry: {path}")


def validate(registry):
    if registry.get("version") != 1:
        raise ValueError("only registry version 1 is supported")
    ensure_no_secret(registry)

    nodes = registry.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValueError("nodes must be a non-empty list")
    if nodes[0].get("id") != PRIMARY_NODE_ID:
        raise ValueError(f"nodes[0].id must be {PRIMARY_NODE_ID}")

    seen = set()
    for node in nodes:
        node_id = node.get("id")
        if not node_id:
            raise ValueError("every node must have an id")
        if node_id in seen:
            raise ValueError(f"duplicate node id: {node_id}")
        seen.add(node_id)
        if not (node.get("host") or node.get("ipv4") or node.get("ipv6")):
            raise ValueError(f"node {node_id} must define host, ipv4, or ipv6")
        services = node.get("services", {})
        if services is None:
            services = {}
        if not isinstance(services, dict):
            raise ValueError(f"node {node_id} services must be an object")
        for name, port in services.items():
            if not isinstance(name, str) or not name:
                raise ValueError(f"node {node_id} has invalid service name")
            if not isinstance(port, int) or port < 1 or port > 65535:
                raise ValueError(f"node {node_id} service {name} has invalid port")

    service_config = registry.get("services") or {}
    if not isinstance(service_config, dict):
        raise ValueError("services must be an object")

    parent = service_config.get("netdata", {}).get("parent", {}).get("node")
    service_endpoint(registry, parent, "netdata")

    edge_routes = registry.get("edge_routes", [])
    if not isinstance(edge_routes, list):
        raise ValueError("edge_routes must be a list")
    nodes_by_id = node_map(registry)
    route_ids = set()
    for route in edge_routes:
        route_id = route.get("id")
        if not isinstance(route_id, str) or not route_id:
            raise ValueError("edge route id is required")
        if route_id in route_ids:
            raise ValueError(f"duplicate edge route id: {route_id}")
        route_ids.add(route_id)

        service_name = route.get("service")
        if not isinstance(service_name, str) or not service_name:
            raise ValueError(f"edge route {route_id} service is required")

        listen_port = route.get("listen_port")
        if not isinstance(listen_port, int) or listen_port < 1 or listen_port > 65535:
            raise ValueError(f"edge route {route_id} has invalid listen_port")

        protocols = route.get("protocols")
        if not isinstance(protocols, list) or not protocols or any(protocol not in ("tcp", "udp") for protocol in protocols):
            raise ValueError(f"edge route {route_id} has invalid protocols")

        entry_nodes = route.get("entry_nodes")
        if not isinstance(entry_nodes, list) or not entry_nodes:
            raise ValueError(f"edge route {route_id} entry_nodes must be a non-empty list")
        for entry_node in entry_nodes:
            if entry_node not in nodes_by_id:
                raise ValueError(f"edge route {route_id} has unknown entry node: {entry_node}")
            if not ip_addresses(nodes_by_id[entry_node]):
                raise ValueError(f"edge route {route_id} entry node {entry_node} has no ip address")

        service_endpoint(registry, route.get("backend_node"), service_name, require_ip=True)


def iperf_csv(registry):
    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["Name", "Host", "Port"])
    for endpoint in service_endpoints(registry, "iperf"):
        writer.writerow([endpoint["name"], endpoint["host"], endpoint["port"]])
    return output.getvalue()


def pin_proxy(registry):
    lines = []
    nodes = node_map(registry)
    for route in edge_routes_for_service(registry, "ipfs"):
        if "tcp" not in route["protocols"]:
            continue
        for node_id in route["entry_nodes"]:
            node = nodes[node_id]
            lines.append(f"# {node_id} via {route['id']}")
            if node.get("ipv4"):
                lines.append(f"/ip4/{node['ipv4']}/tcp/{{port}}")
            if node.get("ipv6"):
                lines.append(f"/ip6/{node['ipv6']}/tcp/{{port}}")
            lines.append("")
    if not lines:
        return ""
    return "\n".join(lines).rstrip() + "\n"


def netdata_parent(registry):
    parent = registry["services"]["netdata"]["parent"]["node"]
    host, port = service_endpoint(registry, parent, "netdata")
    return f"{host}:{port}"


def stream_config(route, host, port):
    listen = route["listen_port"]
    upstream = route["id"].replace("-", "_")
    title = route["id"].replace("-", " ").title()
    blocks = [f"# {title}", ""]

    if "tcp" in route["protocols"]:
        blocks.extend([
            f"upstream backend_{upstream}_tcp {{",
            f"    server {host}:{port};",
            "}",
            "",
            "server {",
            f"    listen 0.0.0.0:{listen};",
            f"    listen [::]:{listen};",
            "    proxy_connect_timeout 5s;",
            "    proxy_timeout 300s;",
            f"    proxy_pass backend_{upstream}_tcp;",
            "",
            f"    access_log /var/log/nginx/stream_{listen}_tcp_bandwidth.log proxy_bandwidth;",
            "}",
            "",
        ])

    if "udp" in route["protocols"]:
        blocks.extend([
            f"upstream backend_{upstream}_udp {{",
            f"    server {host}:{port};",
            "}",
            "",
            "server {",
            f"    listen 0.0.0.0:{listen} udp;",
            f"    listen [::]:{listen} udp;",
            "    proxy_timeout 120s;",
            f"    proxy_pass backend_{upstream}_udp;",
            "",
            f"    access_log /var/log/nginx/stream_{listen}_udp_bandwidth.log proxy_bandwidth;",
            "}",
            "",
        ])

    return "\n".join(blocks).rstrip() + "\n"


def generate_nginx_streams(registry, output_dir):
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    expected = []
    for route in registry["edge_routes"]:
        host, port = service_endpoint(registry, route["backend_node"], route["service"], require_ip=True)
        file_path = output_path / f"{route['id']}.conf"
        file_path.write_text(stream_config(route, host, port), encoding="utf-8")
        expected.append(file_path.name)
    for existing in output_path.glob("*.conf"):
        if existing.name not in expected:
            existing.unlink()


def write_text(path, text):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def publish(registry, destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(registry, indent=2) + "\n", encoding="utf-8")


def replace_if_changed(target, source):
    target = Path(target)
    source = Path(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    new_content = source.read_bytes()
    if target.exists() and target.read_bytes() == new_content:
        return False
    target.write_bytes(new_content)
    return True


def disabled_stream_name(conf_name):
    if not conf_name.endswith(".conf"):
        raise ValueError(f"stream config must end with .conf: {conf_name}")
    return conf_name[:-5] + ".off"


def sync_nginx_streams(generated_dir, output_dir):
    stream_output_dir = Path(output_dir)
    stream_output_dir.mkdir(parents=True, exist_ok=True)

    changed = []
    expected = set()
    for generated in Path(generated_dir).glob("*.conf"):
        active_path = stream_output_dir / generated.name
        disabled_path = stream_output_dir / disabled_stream_name(generated.name)
        if disabled_path.exists() and not active_path.exists():
            target = disabled_path
        else:
            target = active_path

        expected.add(target.name)
        if replace_if_changed(target, generated):
            changed.append(str(target))

    for existing in list(stream_output_dir.glob("*.conf")) + list(stream_output_dir.glob("*.off")):
        if existing.name not in expected:
            existing.unlink()
            changed.append(str(existing))

    return changed


def atomic_refresh(registry, args):
    with tempfile.TemporaryDirectory(prefix="otaku-registry-") as tmp:
        tmp_path = Path(tmp)
        iperf_path = tmp_path / "iperf-lines.csv"
        pin_proxy_path = tmp_path / "global.txt"
        nginx_path = tmp_path / "streams"

        write_text(iperf_path, iperf_csv(registry))
        write_text(pin_proxy_path, pin_proxy(registry))
        generate_nginx_streams(registry, nginx_path)

        if args.dry_run:
            print(f"validated refresh outputs in {tmp_path}")
            return

        changed = []
        if args.iperf_output and replace_if_changed(args.iperf_output, iperf_path):
            changed.append(str(args.iperf_output))
        if args.pin_proxy_output and replace_if_changed(args.pin_proxy_output, pin_proxy_path):
            changed.append(str(args.pin_proxy_output))

        changed.extend(sync_nginx_streams(nginx_path, args.nginx_output_dir))

        if args.reload_nginx and any("/nginx/streams/" in path.replace("\\", "/") for path in changed):
            import subprocess

            subprocess.run(["nginx", "-t"], check=True)
            subprocess.run(["systemctl", "reload", "nginx"], check=True)

        print("refreshed registry outputs")
        if changed:
            for path in changed:
                print(f"changed: {path}")
        else:
            print("no changes")


def main():
    parser = argparse.ArgumentParser(description="Validate and derive OtakuRoom network registry outputs.")
    parser.add_argument("--registry", default=None)
    parser.add_argument("--remote-url", default=REMOTE_REGISTRY_URL)
    subcommands = parser.add_subparsers(dest="command", required=True)

    subcommands.add_parser("validate")
    subcommands.add_parser("netdata-parent")
    subcommands.add_parser("iperf-csv")
    subcommands.add_parser("pin-proxy")

    write_iperf = subcommands.add_parser("write-iperf-csv")
    write_iperf.add_argument("--output", required=True)

    write_pin = subcommands.add_parser("write-pin-proxy")
    write_pin.add_argument("--output", default=str(PIN_PROXY_FILE))

    write_nginx = subcommands.add_parser("write-nginx-streams")
    write_nginx.add_argument("--output-dir", default="/etc/nginx/streams")

    publish_cmd = subcommands.add_parser("publish")
    publish_cmd.add_argument("--output", default=str(WEB_REGISTRY))

    refresh_cmd = subcommands.add_parser("refresh")
    refresh_cmd.add_argument("--iperf-output", default=None)
    refresh_cmd.add_argument("--pin-proxy-output", default=None)
    refresh_cmd.add_argument("--nginx-output-dir", default="/etc/nginx/streams")
    refresh_cmd.add_argument("--dry-run", action="store_true")
    refresh_cmd.add_argument("--reload-nginx", action="store_true")

    args = parser.parse_args()
    registry = load_registry(args.registry, args.remote_url)
    validate(registry)

    if args.command == "validate":
        print("registry ok")
    elif args.command == "netdata-parent":
        print(netdata_parent(registry))
    elif args.command == "iperf-csv":
        sys.stdout.write(iperf_csv(registry))
    elif args.command == "pin-proxy":
        sys.stdout.write(pin_proxy(registry))
    elif args.command == "write-iperf-csv":
        write_text(args.output, iperf_csv(registry))
    elif args.command == "write-pin-proxy":
        write_text(args.output, pin_proxy(registry))
    elif args.command == "write-nginx-streams":
        generate_nginx_streams(registry, args.output_dir)
    elif args.command == "publish":
        publish(registry, args.output)
    elif args.command == "refresh":
        atomic_refresh(registry, args)


if __name__ == "__main__":
    main()
