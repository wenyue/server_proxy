#!/bin/bash
# Run iperf3 speed tests for every line listed in config/iperf-lines.csv.

set -u

CONFIG_FILE="config/iperf-lines.csv"
DURATION="10"
PARALLEL="1"
RUN_REVERSE=1

usage() {
  cat <<EOF
Usage: bash test-iperf-lines.sh [options]

Options:
  -c, --config FILE     CSV file with Name,Host,Port columns (default: config/iperf-lines.csv)
  -t, --time SECONDS    Test duration per direction (default: 10)
  -P, --parallel N      Parallel streams passed to iperf3 (default: 1)
      --no-reverse      Only test client -> server
  -h, --help            Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c|--config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    -t|--time)
      DURATION="${2:-}"
      shift 2
      ;;
    -P|--parallel)
      PARALLEL="${2:-}"
      shift 2
      ;;
    --no-reverse)
      RUN_REVERSE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v iperf3 >/dev/null 2>&1; then
  echo "iperf3 is required. Install it first." >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
  echo "--time must be a positive integer" >&2
  exit 2
fi

if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [ "$PARALLEL" -lt 1 ]; then
  echo "--parallel must be a positive integer" >&2
  exit 2
fi

echo "Running iperf3 line tests"
echo "Config: $CONFIG_FILE"
echo "Duration: ${DURATION}s per direction"
echo "Parallel streams: $PARALLEL"
echo ""

total=0
failed=0

run_test() {
  local name="$1"
  local host="$2"
  local port="$3"
  local direction="$4"
  shift 4

  echo "[$name] $direction $host:$port"
  if iperf3 -c "$host" -p "$port" -t "$DURATION" -P "$PARALLEL" "$@"; then
    echo "[$name] $direction OK"
    echo ""
    return 0
  fi

  echo "[$name] $direction FAILED" >&2
  echo ""
  return 1
}

while IFS=, read -r name host port extra; do
  name="${name//$'\r'/}"
  host="${host//$'\r'/}"
  port="${port//$'\r'/}"

  if [ -z "$name" ] && [ -z "$host" ] && [ -z "$port" ]; then
    continue
  fi

  if [ -n "${extra:-}" ] || [ -z "$name" ] || [ -z "$host" ] || [ -z "$port" ]; then
    echo "Invalid CSV row: $name,$host,$port${extra:+,$extra}" >&2
    exit 2
  fi

  total=$((total + 1))

  if ! run_test "$name" "$host" "$port" "upload"; then
    failed=$((failed + 1))
  fi

  if [ "$RUN_REVERSE" -eq 1 ]; then
    if ! run_test "$name" "$host" "$port" "download" --reverse; then
      failed=$((failed + 1))
    fi
  fi
done < <(tail -n +2 "$CONFIG_FILE")

if [ "$failed" -gt 0 ]; then
  echo "Completed $total line(s) with $failed failed test(s)." >&2
  exit 1
fi

echo "Completed $total line(s) successfully."
