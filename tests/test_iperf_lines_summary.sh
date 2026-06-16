#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/iperf3" <<'MOCK'
#!/bin/bash
host=""
reverse=0
connect_timeout=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      host="$2"
      shift 2
      ;;
    --connect-timeout)
      connect_timeout="$2"
      shift 2
      ;;
    --reverse)
      reverse=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$connect_timeout" != "5000" ]; then
  echo "missing connect timeout" >&2
  exit 2
fi

if [ "$host" = "203.0.113.10" ] && [ "$reverse" -eq 0 ]; then
  echo "[  5]   0.00-1.00   sec  12.0 MBytes   100 Mbits/sec  receiver"
elif [ "$host" = "203.0.113.10" ]; then
  echo "[  5]   0.00-1.00   sec  24.0 MBytes   200 Mbits/sec  receiver"
elif [ "$host" = "2001:db8::1" ] && [ "$reverse" -eq 0 ]; then
  echo "[SUM]   0.00-1.00   sec   128 MBytes  1.00 Gbits/sec  receiver"
elif [ "$host" = "2001:db8::1" ]; then
  echo "[SUM]   0.00-1.00   sec  76.8 MBytes   600 Mbits/sec  receiver"
else
  exit 1
fi
MOCK
chmod +x "$tmp_dir/iperf3"

cat >"$tmp_dir/targets.csv" <<'CSV'
Name,Host,Port
node-a,203.0.113.10,5201
node-b,2001:db8::1,5201
CSV

output="$(
  PATH="$tmp_dir:$PATH" bash "$ROOT_DIR/test-iperf-lines.sh" -c "$tmp_dir/targets.csv" -t 1
)"

grep -F "Summary:" <<<"$output" >/dev/null
grep -E '^Name[[:space:]]+Host[[:space:]]+Upload[[:space:]]+Download[[:space:]]*$' <<<"$output" >/dev/null
grep -E '^node-a[[:space:]]+203\.0\.113\.10[[:space:]]+100 Mbits/sec[[:space:]]+200 Mbits/sec[[:space:]]*$' <<<"$output" >/dev/null
grep -E '^node-b[[:space:]]+2001:db8::1[[:space:]]+1\.00 Gbits/sec[[:space:]]+600 Mbits/sec[[:space:]]*$' <<<"$output" >/dev/null

cat >"$tmp_dir/python" <<'MOCK'
#!/bin/bash
echo "registry failed" >&2
exit 42
MOCK
chmod +x "$tmp_dir/python"

set +e
failure_output="$(PATH="$tmp_dir:$PATH" PYTHON_BIN=python bash "$ROOT_DIR/test-iperf-lines.sh" -t 1 2>&1)"
failure_status=$?
set -e

[ "$failure_status" -ne 0 ]
grep -F "registry failed" <<<"$failure_output" >/dev/null
grep -F "Failed to load iperf targets from network registry." <<<"$failure_output" >/dev/null
if grep -F "Completed 0 line(s) successfully." <<<"$failure_output" >/dev/null; then
  echo "script reported success after registry failure" >&2
  exit 1
fi
