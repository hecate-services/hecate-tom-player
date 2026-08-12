#!/usr/bin/env bash
#
# Boot a house for real, with no mesh under it, and check that the page, the
# health endpoint and the JSON snapshot all answer.
#
# This exists because every test in this repository runs against a function, and
# a service that passes all of them can still fail to boot. Nothing here mocks
# anything: it starts the OTP release's applications, binds two ports and asks
# them questions over TCP.
#
#   scripts/smoke.sh

set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

rebar3 compile >/dev/null

run_dir="$(mktemp -d)"
log="$run_dir/boot.log"
trap 'kill "${node_pid:-0}" 2>/dev/null || true; rm -rf "$run_dir"' EXIT

erl -noshell \
    -pa _build/default/lib/*/ebin \
    -config config/local \
    -hecate_tom_player ledger "\"$run_dir/house.log\"" \
    -eval 'application:ensure_all_started(hecate_tom_player), receive stop -> ok end.' \
    > "$log" 2>&1 &
node_pid=$!

for _ in $(seq 1 60); do
    if curl -fsS -m 2 http://localhost:8461/view >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

fail() {
    echo "FAIL: $1"
    echo "--- boot log ---"
    cat "$log"
    exit 1
}

# A house with no station under it is DEGRADED, and says so with a 503. That is
# the honest report: it has its purse, its history and its page, and it cannot
# do the one thing it exists to do until a station answers. Anything else here
# would be a service reporting healthy while reaching nobody.
curl -sS -m 5 http://localhost:8460/health | grep -q '"status":"degraded"' \
    || fail "/health did not report a house with no mesh as degraded"
echo "ok   /health answers, and says degraded with no station under it"

view="$(curl -fsS -m 5 http://localhost:8461/view)"
grep -q '"player":"raf"'        <<<"$view" || fail "/view did not name the player"
grep -q '"purse":1.0e3'         <<<"$view" || fail "/view did not carry the genesis purse"
grep -q '"standing":"unknown"'  <<<"$view" || fail "/view claimed to know where the ship is"
grep -q 'no_mesh'               <<<"$view" || fail "/view hid the fact that nobody answered"
echo "ok   /view reports the purse and admits it has not found the ship"

page="$(curl -fsS -m 5 http://localhost:8461/)"
grep -q '<!doctype html>' <<<"$page" || fail "/ served no document"
grep -q 'santa_clara'     <<<"$page" || fail "/ did not name the ship"
grep -q 'value="buy"'     <<<"$page" || fail "/ had no way to buy anything"
grep -q 'value="sail"'    <<<"$page" || fail "/ had no way to sail"
echo "ok   / serves a page with a helm on it"

# The stream has to start pushing without being asked twice. It never ends on
# its own, so the reader is cut off after a moment and what arrived is checked.
timeout 5 curl -sS -N http://localhost:8461/stream > "$run_dir/stream.txt" 2>/dev/null || true
grep -q 'event: board' "$run_dir/stream.txt" || fail "/stream pushed no board"
if grep -q 'The helm' "$run_dir/stream.txt"; then
    fail "/stream pushed the controls too, which would eat what a player is typing"
fi
echo "ok   /stream pushes a board the moment it is opened"

# With no mesh under it, every act is refused politely rather than crashing.
curl -fsS -m 5 -X POST http://localhost:8461/act \
     -H 'accept: application/json' \
     -d 'do=buy&good=pepper&quantity=10' | grep -q '"ok":false' \
    || fail "a buy with no mesh did not come back refused"
echo "ok   an act with no mesh is refused, not a crash"

echo
echo "the house boots, serves and holds together."
