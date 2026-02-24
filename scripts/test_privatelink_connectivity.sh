#!/usr/bin/env bash
# Test PrivateLink connectivity for Aliyun ES
# Usage:
#   bash test_privatelink_connectivity.sh \
#     --endpoint "ep-xxxx.privatelink.aliyuncs.com" \
#     --port 9200 \
#     [--es-host "https://ES1_ENDPOINT:9200"] \
#     [--es-user elastic] \
#     [--es-pass "password"] \
#     [--remote-index "source_index"] \
#     [--local-index "dest_index"]

set -euo pipefail

ENDPOINT=""
PORT=9200
ES_HOST=""
ES_USER="elastic"
ES_PASS=""
REMOTE_INDEX=""
LOCAL_INDEX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint)  ENDPOINT="$2"; shift 2;;
    --port)      PORT="$2"; shift 2;;
    --es-host)   ES_HOST="$2"; shift 2;;
    --es-user)   ES_USER="$2"; shift 2;;
    --es-pass)   ES_PASS="$2"; shift 2;;
    --remote-index) REMOTE_INDEX="$2"; shift 2;;
    --local-index)  LOCAL_INDEX="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

if [[ -z "$ENDPOINT" ]]; then
  echo "ERROR: --endpoint is required"
  exit 1
fi

echo "=== PrivateLink Connectivity Test ==="
echo ""

# Test 1: DNS resolution
echo "[1/4] DNS Resolution"
if host "$ENDPOINT" > /dev/null 2>&1; then
  IP=$(host "$ENDPOINT" | head -1 | awk '{print $NF}')
  echo "  OK: $ENDPOINT -> $IP"
else
  echo "  WARN: DNS lookup failed (may still work via internal DNS)"
fi
echo ""

# Test 2: TCP connectivity
echo "[2/4] TCP Connectivity ($ENDPOINT:$PORT)"
if timeout 5 bash -c "echo > /dev/tcp/$ENDPOINT/$PORT" 2>/dev/null; then
  echo "  OK: Port $PORT is reachable"
else
  echo "  FAIL: Cannot connect to $ENDPOINT:$PORT"
  echo "  Check: endpoint status, security groups, LB listener"
  exit 1
fi
echo ""

# Test 3: HTTP(S) probe
echo "[3/4] HTTP Probe"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
  --connect-timeout 5 "http://$ENDPOINT:$PORT/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "000" ]]; then
  # Try HTTPS
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 "https://$ENDPOINT:$PORT/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" != "000" ]]; then
    echo "  OK: HTTPS response code $HTTP_CODE"
  else
    echo "  FAIL: No HTTP/HTTPS response"
    exit 1
  fi
else
  echo "  OK: HTTP response code $HTTP_CODE"
fi
echo ""

# Test 4: Reindex test (optional)
echo "[4/4] Reindex Test"
if [[ -n "$ES_HOST" && -n "$ES_PASS" && -n "$REMOTE_INDEX" && -n "$LOCAL_INDEX" ]]; then
  echo "  Running reindex from $REMOTE_INDEX -> $LOCAL_INDEX ..."
  RESPONSE=$(curl -sk -u "$ES_USER:$ES_PASS" -X POST "$ES_HOST/_reindex?wait_for_completion=true" \
    -H 'Content-Type: application/json' -d "{
      \"source\": {
        \"remote\": {
          \"host\": \"http://$ENDPOINT:$PORT\",
          \"username\": \"$ES_USER\",
          \"password\": \"$ES_PASS\"
        },
        \"index\": \"$REMOTE_INDEX\",
        \"size\": 10
      },
      \"dest\": {
        \"index\": \"$LOCAL_INDEX\"
      }
    }" 2>/dev/null)

  if echo "$RESPONSE" | grep -q '"failures":\[\]'; then
    TOTAL=$(echo "$RESPONSE" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
    echo "  OK: Reindex succeeded (total: ${TOTAL:-unknown} docs)"
  else
    echo "  FAIL: Reindex response:"
    echo "  $RESPONSE" | head -5
    exit 1
  fi
else
  echo "  SKIPPED (provide --es-host, --es-pass, --remote-index, --local-index to test)"
fi

echo ""
echo "=== All tests passed ==="
