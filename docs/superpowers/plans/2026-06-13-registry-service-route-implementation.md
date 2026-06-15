# Registry Service Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved registry model where source services live on nodes and proxy exposure is described by `edge_routes`, while registry `version` remains `1`.

**Architecture:** `script/registry.py` will derive outputs from source node services and edge routes. `D:/OtakuRoomWeb/network/registry.json` will remove duplicated consumer lists and proxy-forwarded services. Tests will cover endpoint derivation, CSV output, pin proxy output, netdata parent lookup, and nginx stream generation.

**Tech Stack:** Python standard library, `unittest`, Bash structure checks.

---

### Task 1: Tests for Service and Route Model

**Files:**
- Modify: `tests/test_registry.py`

- [ ] **Step 1: Write failing tests**

Add tests that build a version-1 registry with `services.netdata.parent`, source services on `pin-server-all` and `user-server`, proxy nodes with no forwarded services in `nodes[].services`, and `edge_routes` for `ipfs`, `iperf`, and user services. Assert:

```python
registry.iperf_csv(model) == (
    "Name,Host,Port\n"
    "pin-server-all,ipfs.otakuroom.net,5201\n"
    "proxy-us-0-via-iperf,23.94.212.231,5201\n"
    "proxy-us-cn2-1-via-iperf,154.17.226.134,5201\n"
    "proxy-us-cn2-1-ipv6-via-iperf,2605:52c0:1:4f0:be24:11ff:fe17:6583,5201\n"
)
```

Also assert `pin_proxy(model)` includes only edge `ipfs` entries, `netdata_parent(model)` returns `ipfs.otakuroom.net:19999`, and `validate(model)` accepts proxy nodes without `services`.

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests.test_registry`

Expected: FAIL because current code still expects old `iperf.targets`, `pin_server.proxy_nodes`, and `nginx_streams`.

### Task 2: Registry Logic

**Files:**
- Modify: `script/registry.py`

- [ ] **Step 1: Implement endpoint helpers**

Add helpers to read source node services and edge route endpoints:

```python
def node_services(node):
    return node.get("services") or {}

def direct_endpoint(registry, node_id, service):
    node = node_map(registry)[node_id]
    port = node_services(node)[service]
    return preferred_public_address(node), port
```

Add route validation so each route has `id`, `service`, `entry_nodes`, `listen_port`, `backend_node`, and `protocols`, and so `backend_node.services[service]` exists.

- [ ] **Step 2: Derive outputs**

Update:

```text
iperf_csv -> direct endpoints for iperf + edge route endpoints for iperf
pin_proxy -> edge route endpoints for ipfs only
netdata_parent -> services.netdata.parent.node + node netdata port
generate_nginx_streams -> edge_routes
```

- [ ] **Step 3: Run focused tests**

Run: `python -m unittest tests.test_registry`

Expected: PASS.

### Task 3: Registry Data and Generated Files

**Files:**
- Modify: `D:/OtakuRoomWeb/network/registry.json`
- Do not commit generated nginx stream files; generate them into a temporary directory or `/etc/nginx/streams`
- Modify: `tests/test_setup_scripts.sh`

- [ ] **Step 1: Update registry JSON**

Keep `"version": 1`. Add top-level `services.netdata.parent.node`. Remove `nginx_streams`, `iperf`, and `pin_server`. Remove proxy-forwarded services from proxy nodes. Add `edge_routes` for existing nginx streams: `user-p2p`, `user-http`, `gm-http`, `pin-server`, and `iperf`.

- [ ] **Step 2: Refresh generated outputs**

Run:

```powershell
python script/registry.py --registry D:\OtakuRoomWeb\network\registry.json write-nginx-streams --output-dir <temporary-or-runtime-stream-dir>
```

Do not write `iperf-lines.csv` under project config. Use `python script/registry.py iperf-csv` at runtime, or explicitly pass `write-iperf-csv --output <temporary-or-user-path>` when a standalone CSV is needed.

- [ ] **Step 3: Update structure checks**

Update `tests/test_setup_scripts.sh` so it checks for `edge_routes`, `services.netdata.parent`, and generated CSV/proxy output from the new model.

- [ ] **Step 4: Run final verification**

Run:

```powershell
python -m unittest tests.test_registry
python script/registry.py --registry D:\OtakuRoomWeb\network\registry.json validate
python script/registry.py --registry D:\OtakuRoomWeb\network\registry.json iperf-csv
bash tests/test_setup_scripts.sh
```

Expected: all commands exit `0`.
