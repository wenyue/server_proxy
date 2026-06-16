#!/bin/bash
# Run iperf3 speed tests for every target listed in the network registry.

set -u

CONFIG_FILE=""
DURATION="10"
PARALLEL="1"
CONNECT_TIMEOUT="5000"
RUN_REVERSE=1
PYTHON_BIN="${PYTHON_BIN:-python}"

usage() {
  cat <<EOF
Usage: bash test-iperf-lines.sh [options]

Options:
  -c, --config FILE     CSV file with Name,Host,Port columns (default: generated from registry)
  -t, --time SECONDS    Test duration per direction (default: 10)
  -P, --parallel N      Parallel streams passed to iperf3 (default: 1)
      --connect-timeout MS
                         Control connection timeout in milliseconds (default: 5000)
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
    --connect-timeout)
      CONNECT_TIMEOUT="${2:-}"
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

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "Python is required to read the network registry." >&2
    exit 1
  fi
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
  echo "--time must be a positive integer" >&2
  exit 2
fi

if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [ "$PARALLEL" -lt 1 ]; then
  echo "--parallel must be a positive integer" >&2
  exit 2
fi

if ! [[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$CONNECT_TIMEOUT" -lt 1 ]; then
  echo "--connect-timeout must be a positive integer" >&2
  exit 2
fi

echo "Running iperf3 line tests"
if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  CONFIG_SOURCE="$CONFIG_FILE"
else
  CONFIG_SOURCE="network registry"
fi

echo "Config: $CONFIG_SOURCE"
echo "Duration: ${DURATION}s per direction"
echo "Parallel streams: $PARALLEL"
echo "Connect timeout: ${CONNECT_TIMEOUT}ms"
echo ""

total=0
failed=0
TARGETS_FILE=""
TARGETS_TMP=""
summary_names=()
summary_hosts=()
summary_uploads=()
summary_downloads=()
LAST_SPEED=""

extract_bitrate() {
  awk '
    /bits\/sec/ {
      speed = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /bits\/sec$/ && i > 1) {
          speed = $(i - 1) " " $i
          break
        }
      }
      if (speed == "") {
        next
      }
      if ($0 ~ /receiver/) {
        receiver = speed
      } else if ($0 ~ /sender/) {
        sender = speed
      } else {
        other = speed
      }
    }
    END {
      if (receiver != "") {
        print receiver
      } else if (sender != "") {
        print sender
      } else if (other != "") {
        print other
      } else {
        print "n/a"
      }
    }
  ' <<<"$1"
}

print_summary() {
  local name_width=4
  local host_width=4
  for i in "${!summary_names[@]}"; do
    if [ "${#summary_names[$i]}" -gt "$name_width" ]; then
      name_width="${#summary_names[$i]}"
    fi
    if [ "${#summary_hosts[$i]}" -gt "$host_width" ]; then
      host_width="${#summary_hosts[$i]}"
    fi
  done

  echo "Summary:"
  printf "%-*s %-*s %-15s %-15s\n" "$name_width" "Name" "$host_width" "Host" "Upload" "Download"
  for i in "${!summary_names[@]}"; do
    printf "%-*s %-*s %-15s %-15s\n" \
      "$name_width" \
      "${summary_names[$i]}" \
      "$host_width" \
      "${summary_hosts[$i]}" \
      "${summary_uploads[$i]}" \
      "${summary_downloads[$i]}"
  done
  echo ""
}

cleanup() {
  if [ -n "$TARGETS_TMP" ]; then
    rm -f "$TARGETS_TMP"
  fi
}
trap cleanup EXIT

run_test() {
  local name="$1"
  local host="$2"
  local port="$3"
  local direction="$4"
  shift 4

  echo "[$name] $direction $host:$port"
  LAST_SPEED=""
  local output
  output="$(iperf3 -c "$host" -p "$port" -t "$DURATION" -P "$PARALLEL" --connect-timeout "$CONNECT_TIMEOUT" "$@" 2>&1)"
  local status=$?
  printf "%s\n" "$output"
  if [ "$status" -eq 0 ]; then
    LAST_SPEED="$(extract_bitrate "$output")"
    echo "[$name] $direction OK"
    echo ""
    return 0
  fi

  echo "[$name] $direction FAILED" >&2
  echo ""
  return 1
}

if [ -n "$CONFIG_FILE" ]; then
  TARGETS_FILE="$CONFIG_FILE"
else
  TARGETS_TMP="$(mktemp)"
  if ! "$PYTHON_BIN" script/registry.py iperf-csv >"$TARGETS_TMP"; then
    echo "Failed to load iperf targets from network registry." >&2
    exit 1
  fi
  TARGETS_FILE="$TARGETS_TMP"
fi

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

  upload_speed="FAILED"
  if ! run_test "$name" "$host" "$port" "upload"; then
    failed=$((failed + 1))
  else
    upload_speed="$LAST_SPEED"
  fi

  download_speed="SKIPPED"
  if [ "$RUN_REVERSE" -eq 1 ]; then
    if ! run_test "$name" "$host" "$port" "download" --reverse; then
      failed=$((failed + 1))
      download_speed="FAILED"
    else
      download_speed="$LAST_SPEED"
    fi
  fi

  summary_names+=("$name")
  summary_hosts+=("$host")
  summary_uploads+=("$upload_speed")
  summary_downloads+=("$download_speed")
done < <(tail -n +2 "$TARGETS_FILE")

print_summary

if [ "$failed" -gt 0 ]; then
  echo "Completed $total line(s) with $failed failed test(s)." >&2
  exit 1
fi

echo "Completed $total line(s) successfully."
