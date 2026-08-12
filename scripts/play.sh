#!/usr/bin/env bash
#
# Run a house from the checkout and open its page.
#
# It boots with or without a mesh. With no station configured every call comes
# back unreachable, the page says so in as many words, and the purse and the
# ledger work exactly as they will on a real game. That is the fastest way to
# look at the page.
#
#   scripts/play.sh                      # config/local.config
#   scripts/play.sh config/mine.config   # your own
#
# Set a station and a realm in the config file to reach real ports.

set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-config/local.config}"

cd "$here"
mkdir -p run

echo "house    : http://localhost:8461"
echo "health   : http://localhost:8460/health"
echo "snapshot : curl -s http://localhost:8461/view | jq ."
echo "ledger   : $here/run/house.log"
echo

exec rebar3 shell --config "$config" --apps hecate_tom_player
