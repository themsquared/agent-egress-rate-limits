#!/usr/bin/env bash
# Narrated walkthrough: the same burst of requests through an unguarded
# agentgateway route and a guarded one (localRateLimit policy).
set -euo pipefail

UNGUARDED=http://localhost:13300
GUARDED=http://localhost:13301
N=${1:-40}

reset() {
  curl -s "$1/reset" >/dev/null || true
}

burst() {
  local base="$1"
  local ok=0 limited=0
  for _ in $(seq 1 "$N"); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$base/sparql")
    if [ "$code" = "200" ]; then ok=$((ok + 1)); else limited=$((limited + 1)); fi
  done
  echo "  $ok x 200, $limited x 429"
}

echo "agentgateway, local rate limiting on ordinary HTTP egress"
echo "=========================================================="
echo
echo "Resetting both upstream counters..."
reset "$UNGUARDED"
reset "$GUARDED"
echo

echo "1. UNGUARDED route: no localRateLimit policy."
echo "   Sending $N requests as fast as curl can fire them:"
burst "$UNGUARDED"
stats=$(curl -s "$UNGUARDED/stats")
echo "   Upstream (the mock third-party API) saw: $stats"
echo

echo "2. GUARDED route: localRateLimit { maxTokens: 20, tokensPerFill: 5, fillInterval: 1s, type: requests }"
echo "   Same $N requests, same speed:"
burst "$GUARDED"
stats=$(curl -s "$GUARDED/stats")
echo "   Upstream (the mock third-party API) saw: $stats"
echo
echo "The config difference is the policy block in config/guarded.yaml."
echo "Nothing about the destination changed -- it is still an allowed host."
echo "The gateway is now the thing deciding how often an agent may ask it."
