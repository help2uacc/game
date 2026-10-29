#!/usr/bin/env bash
# Automated LAN smoke test on localhost: 1 host + N bot clients play a short
# match headless. Debug builds only (uses --bot/--autostart user args).
# Usage: tools/net_smoke_test.sh [clients=2] [seconds=90] [rounds=4]
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
CLIENTS="${1:-2}"
SECS="${2:-90}"
ROUNDS="${3:-4}"
mkdir -p build/net
rm -f build/net/*.log
"$GODOT" --headless -- --name=Host --host --bot --log --autostart=$((CLIENTS + 1)) --rounds="$ROUNDS" --quit-after="$SECS" > build/net/host.log 2>&1 &
sleep 2
DROP="${DROP:-}"
for i in $(seq 1 "$CLIENTS"); do
  extra=""
  if [ "$i" = "1" ] && [ -n "$DROP" ]; then extra="--drop-at=$DROP"; fi
  "$GODOT" --headless -- --name="Bot$i" --join=127.0.0.1 --bot --log $extra --quit-after="$((SECS - 4))" > "build/net/client$i.log" 2>&1 &
  sleep 0.5
done
wait
echo "== host"; grep -E "^\[|ERROR|SCRIPT" build/net/host.log | head -60
for i in $(seq 1 "$CLIENTS"); do
  echo "== client$i"; grep -E "^\[|ERROR|SCRIPT" "build/net/client$i.log" | head -30
done
