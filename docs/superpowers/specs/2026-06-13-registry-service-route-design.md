# Registry Service Route Design

## Goal

Redesign the public network registry so it remains version `1` while clearly separating source services from proxy routes. The registry is both the service-discovery source and the deployment-config source.

## Principles

- Facts are written once.
- `nodes[].services` means services running on that source node.
- Proxy nodes do not list services they merely forward.
- `edge_routes` describes proxy entry points and their backend service.
- Consumer outputs are derived from `nodes` and `edge_routes`.
- Service-level configuration exists only for properties that cannot be inferred.

## Registry Shape

```json
{
  "version": 1,
  "updated_at": "2026-06-11T00:00:00Z",
  "services": {
    "netdata": {
      "parent": {
        "node": "pin-server-all"
      }
    }
  },
  "nodes": [
    {
      "id": "pin-server-all",
      "host": "ipfs.otakuroom.net",
      "ipv4": "67.215.234.162",
      "ipv6": null,
      "services": {
        "netdata": 19999,
        "ipfs": 4001,
        "iperf": 5201
      }
    },
    {
      "id": "user-server",
      "host": null,
      "ipv4": "8.219.123.14",
      "ipv6": null,
      "services": {
        "user_http": 3001,
        "user_p2p": 2053,
        "gm_http": 2083,
        "ai_chat": 2084,
        "l10n": 2085
      }
    },
    {
      "id": "proxy-us-0",
      "host": null,
      "ipv4": "23.94.212.231",
      "ipv6": null,
      "roles": ["edge-proxy"]
    }
  ],
  "edge_routes": [
    {
      "id": "user-http",
      "service": "user_http",
      "entry_nodes": ["proxy-us-0", "proxy-us-1", "proxy-us-cn2-1"],
      "listen_port": 3001,
      "backend_node": "user-server",
      "protocols": ["tcp"]
    },
    {
      "id": "iperf",
      "service": "iperf",
      "entry_nodes": ["proxy-us-0", "proxy-us-1", "proxy-us-cn2-1"],
      "listen_port": 5201,
      "backend_node": "pin-server-all",
      "protocols": ["tcp", "udp"]
    }
  ]
}
```

## Derived Outputs

`nginx` stream config is generated directly from `edge_routes`. For each route, the backend endpoint is `backend_node.services[service]`, and the public listen endpoint is `entry_node` at `listen_port`.

`iperf-csv` is generated from all endpoints for service `iperf`: direct source endpoints plus edge route endpoints.

`pin-proxy` is generated from edge route endpoints for service `ipfs`. It should not include direct source endpoints unless a command explicitly asks for them.

`netdata-parent` is generated from `services.netdata.parent.node` and that node's `netdata` source service port.

## Endpoint Defaults

The registry does not store discovery defaults. Commands choose address output for their use case:

- Direct endpoint preferred address: `host`, then `ipv4`, then `ipv6`.
- Edge endpoint addresses: include each available `ipv4` and `ipv6` for the entry node.
- `pin-proxy`: include IP addresses only, not hostnames.

## Removed Fields

These fields are no longer stored because they duplicate facts from `nodes` and `edge_routes`:

- `nginx_streams`
- `iperf.targets`
- `pin_server.proxy_nodes`

## Compatibility

The registry remains `version: 1`. Existing commands keep their names, but their implementations derive outputs from the new service/route model.
