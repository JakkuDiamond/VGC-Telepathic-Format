#!/usr/bin/env bash
# Starts the Showdown server AND a free Cloudflare quick tunnel so friends can join over the internet.
# Needs: ./setup.sh already run, and `cloudflared` installed:
#   macOS:   brew install cloudflared
#   Windows: winget install Cloudflare.cloudflared   (run this script inside WSL, or see README)
#   Linux:   https://github.com/cloudflare/cloudflared/releases (download the .deb / binary)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SD="$HERE/pokemon-showdown"
[ -d "$SD" ] || SD="$(pwd)/pokemon-showdown"
[ -d "$SD" ] || { echo "Run ./setup.sh first (from this folder)."; exit 1; }
command -v cloudflared >/dev/null || { echo "cloudflared not found. See the install lines at the top of this script."; exit 1; }

# The tunnel makes every player look like 127.0.0.1 unless we trust the proxy's forwarded IP header.
if ! grep -q "^exports.proxyip = \['127.0.0.1'\]" "$SD/config/config.js"; then
  sed -i.bak "s|^exports.proxyip = .*|exports.proxyip = ['127.0.0.1'];|" "$SD/config/config.js"
fi

SERVER_PID=""
TUNNEL_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    pkill -P "$SERVER_PID" 2>/dev/null || true   # server worker processes
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Refuse to run if the custom rules are missing (means setup.sh was not rerun after an update).
for rule in "Shared Ally Team" "Shared Bench" "Confusion Friendly Fire" "Infatuation Friendly Fire" "Ally Switch Trade" "Team Healing" "One Mega Per Team" "Multi Bo3 Series" "VGC Blitz Timer" "No Chat"; do
  grep -q "name: '$rule'" "$SD/data/rulesets.ts" || { echo "ERROR: your server is missing the '$rule' rule. Run ./setup.sh again, then retry."; exit 1; }
done

# An old server still running on port 8000 would silently serve OLD rules. Stop it first.
if (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ':8000 ') || curl -s -m 2 localhost:8000/showdown/info >/dev/null 2>&1; then
  echo "ERROR: something is already running on port 8000 (probably an old copy of this server)."
  echo "Stop it with:  pkill -f pokemon-showdown   (then run this script again)"
  exit 1
fi

SDLOG="$HERE/server.log"
( cd "$SD" && exec node pokemon-showdown 8000 >"$SDLOG" 2>&1 ) &
SERVER_PID=$!
for _ in $(seq 1 60); do
  curl -s -m 1 localhost:8000/showdown/info >/dev/null 2>&1 && break
  sleep 1
done
curl -s -m 2 localhost:8000/showdown/info >/dev/null 2>&1 || { echo "Server did not start. Log:"; tail -20 "$SDLOG"; exit 1; }
if grep -q CRASH "$SDLOG"; then echo "Server reported an error. Log:"; tail -20 "$SDLOG"; exit 1; fi
echo "Server is up with the latest rules (Shared Ally Team, Shared Bench, Confusion Friendly Fire, Infatuation Friendly Fire, Ally Switch Trade, Team Healing, One Mega Per Team, Multi Bo3 Series, VGC Blitz Timer, No Chat)."

LOG="$(mktemp)"
URL=""
# Cloudflare's quick-tunnel service is sometimes slow to answer, so try up to 3 times.
# Attempts 2 and 3 use IPv4 and TCP (http2), which helps on networks that block UDP or IPv6.
for attempt in 1 2 3; do
  EXTRA=""
  [ "$attempt" -gt 1 ] && EXTRA="--protocol http2 --edge-ip-version 4"
  echo "Starting the tunnel (attempt $attempt of 3)..."
  : >"$LOG"
  cloudflared tunnel --no-autoupdate $EXTRA --url http://localhost:8000 >"$LOG" 2>&1 &
  TUNNEL_PID=$!
  for _ in $(seq 1 25); do
    # Ignore api.trycloudflare.com: that is Cloudflare's own server, which shows up in error messages.
    URL="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | grep -v '^https://api\.' | head -1 || true)"
    [ -n "$URL" ] && break
    kill -0 "$TUNNEL_PID" 2>/dev/null || break
    sleep 1
  done
  if [ -n "$URL" ]; then
    # The link exists, but wait until cloudflared reports a working connection to Cloudflare.
    for _ in $(seq 1 25); do
      grep -q "Registered tunnel connection" "$LOG" && break
      kill -0 "$TUNNEL_PID" 2>/dev/null || break
      sleep 1
    done
    if grep -q "Registered tunnel connection" "$LOG"; then break; fi
    echo "The tunnel link was created but it did not connect to Cloudflare."
  fi
  kill "$TUNNEL_PID" 2>/dev/null || true
  TUNNEL_PID=""
  URL=""
done
if [ -z "$URL" ]; then
  echo
  echo "Could not start the tunnel after 3 tries. Last log:"
  tail -8 "$LOG"
  echo
  echo "This is a network problem between your PC and Cloudflare (the game server itself is fine)."
  echo "Check it with:  curl -sS -m 10 -o /dev/null -w '%{http_code}\n' https://api.trycloudflare.com"
  echo "If that times out, see the README section 'Tunnel will not start'."
  exit 1
fi
HOST="${URL#https://}"

echo
echo "=============================================================="
echo " Share this link with your friends (and open it yourself too):"
echo "   https://play.pokemonshowdown.com/~~${HOST}"
echo " If that doesn't connect, try:"
echo "   https://play.pokemonshowdown.com/~~${HOST}:443"
echo " Keep this window open while you play. Ctrl+C stops everything."
echo " The link changes every time you restart the tunnel."
echo "=============================================================="
wait "$SERVER_PID"
