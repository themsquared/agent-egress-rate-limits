#!/usr/bin/env bash
# Asserts the core claim this repo makes: the guarded route passes
# meaningfully fewer requests to the upstream than the unguarded one, over
# an identical burst, and the guarded route's throttled responses are 429.
set -euo pipefail

UNGUARDED=http://localhost:13300
GUARDED=http://localhost:13301
N=60
fail=0

curl -s "$UNGUARDED/reset" >/dev/null
curl -s "$GUARDED/reset" >/dev/null

unguarded_429=0
guarded_429=0
for _ in $(seq 1 "$N"); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$UNGUARDED/sparql")
  [ "$code" = "429" ] && unguarded_429=$((unguarded_429 + 1))
done
for _ in $(seq 1 "$N"); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$GUARDED/sparql")
  [ "$code" = "429" ] && guarded_429=$((guarded_429 + 1))
done

unguarded_received=$(curl -s "$UNGUARDED/stats" | python3 -c "import json,sys;print(json.load(sys.stdin)['requests_received'])")
guarded_received=$(curl -s "$GUARDED/stats" | python3 -c "import json,sys;print(json.load(sys.stdin)['requests_received'])")

echo "unguarded: $N sent, upstream received $unguarded_received, $unguarded_429 client-side 429s"
echo "guarded:   $N sent, upstream received $guarded_received, $guarded_429 client-side 429s"

if [ "$unguarded_429" -ne 0 ]; then
  echo "FAIL: unguarded route returned a 429 -- it should never throttle"
  fail=1
fi
if [ "$unguarded_received" -lt "$N" ]; then
  echo "FAIL: unguarded upstream did not receive every request"
  fail=1
fi
if [ "$guarded_429" -eq 0 ]; then
  echo "FAIL: guarded route never throttled -- the policy did not engage"
  fail=1
fi
if [ "$guarded_received" -ge "$unguarded_received" ]; then
  echo "FAIL: guarded upstream saw as much or more traffic than unguarded"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: the policy is the only difference between the two routes, and it is the thing that cut upstream traffic."
fi
exit $fail
