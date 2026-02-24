#!/usr/bin/env bash
# Test PrivateLink connectivity for Aliyun ES
# Usage:
#   bash test_privatelink_connectivity.sh \
#     --endpoint "ep-xxxx.privatelink.aliyuncs.com" \
#     --port 9200 \
#     --protocol http \
#     [--es-host "https://ES1_ENDPOINT:9200"] \
#     [--es-user elastic] \
#     [--es-pass "password"] \
#     [--remote-index "source_index"] \
#     [--local-index "dest_index"] \
#     [--cleanup]

set -euo pipefail

ENDPOINT=""
PORT=9200
PROTOCOL="http"
ES_HOST=""
ES_USER="elastic"
ES_PASS=""
REMOTE_INDEX=""
LOCAL_INDEX=""
CLEANUP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint)      ENDPOINT="$2"; shift 2;;
    --port)          PORT="$2"; shift 2;;
    --protocol)      PROTOCOL="$2"; shift 2;;
    --es-host)       ES_HOST="$2"; shift 2;;
    --es-user)       ES_USER="$2"; shift 2;;
    --es-pass)       ES_PASS="$2"; shift 2;;
    --remote-index)  REMOTE_INDEX="$2"; shift 2;;
    --local-index)   LOCAL_INDEX="$2"; shift 2;;
    --cleanup)       CLEANUP=true; shift;;
    -h|--help)
      echo "Usage: bash test_privatelink_connectivity.sh --endpoint <domain> [options]"
      echo ""
      echo "Required:"
      echo "  --endpoint       PrivateLink endpoint domain (e.g., ep-xxxx.privatelink.aliyuncs.com)"
      echo ""
      echo "Optional:"
      echo "  --port           Port to test (default: 9200)"
      echo "  --protocol       Protocol for ES connections: http or https (default: http)"
      echo "  --es-host        ES_1 endpoint URL for reindex test (e.g., https://ES1:9200)"
      echo "  --es-user        ES username (default: elastic)"
      echo "  --es-pass        ES password"
      echo "  --remote-index   Source index name on remote ES (via PrivateLink)"
      echo "  --local-index    Destination index name on ES_1"
      echo "  --cleanup        Delete the local test index after successful reindex test"
      exit 0;;
    *) echo "Unknown option: $1 (use --help for usage)"; exit 1;;
  esac
done

if [[ -z "$ENDPOINT" ]]; then
  echo "ERROR: --endpoint is required (use --help for usage)"
  exit 1
fi

if [[ "$PROTOCOL" != "http" && "$PROTOCOL" != "https" ]]; then
  echo "ERROR: --protocol must be 'http' or 'https'"
  exit 1
fi

PASS=0
FAIL=0
SKIP=0

echo "=== PrivateLink Connectivity Test ==="
echo "  Endpoint: $ENDPOINT:$PORT"
echo "  Protocol: $PROTOCOL"
echo ""

# Test 1: DNS resolution
echo "[1/4] DNS Resolution"
if command -v host &>/dev/null; then
  if host "$ENDPOINT" > /dev/null 2>&1; then
    IP=$(host "$ENDPOINT" | grep -m1 "has address" | awk '{print $NF}')
    echo "  PASS: $ENDPOINT -> ${IP:-resolved}"
    ((PASS++))
  else
    echo "  WARN: DNS lookup failed via 'host' (may still work via internal DNS)"
    ((SKIP++))
  fi
elif command -v nslookup &>/dev/null; then
  if nslookup "$ENDPOINT" > /dev/null 2>&1; then
    IP=$(nslookup "$ENDPOINT" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
    echo "  PASS: $ENDPOINT -> ${IP:-resolved}"
    ((PASS++))
  else
    echo "  WARN: DNS lookup failed via 'nslookup' (may still work via internal DNS)"
    ((SKIP++))
  fi
else
  echo "  SKIP: neither 'host' nor 'nslookup' available"
  ((SKIP++))
fi
echo ""

# Test 2: TCP connectivity
echo "[2/4] TCP Connectivity ($ENDPOINT:$PORT)"
if timeout 5 bash -c "echo > /dev/tcp/$ENDPOINT/$PORT" 2>/dev/null; then
  echo "  PASS: Port $PORT is reachable"
  ((PASS++))
else
  echo "  FAIL: Cannot connect to $ENDPOINT:$PORT"
  echo "  Check: endpoint status, security groups, LB listener, AZ match"
  ((FAIL++))
fi
echo ""

# Test 3: HTTP(S) probe
echo "[3/4] HTTP Probe ($PROTOCOL://$ENDPOINT:$PORT)"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
  --connect-timeout 5 "$PROTOCOL://$ENDPOINT:$PORT/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" != "000" ]]; then
  echo "  PASS: $PROTOCOL response code $HTTP_CODE"
  ((PASS++))
else
  # Try the other protocol as fallback
  ALT_PROTOCOL="https"
  [[ "$PROTOCOL" == "https" ]] && ALT_PROTOCOL="http"
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 "$ALT_PROTOCOL://$ENDPOINT:$PORT/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" != "000" ]]; then
    echo "  WARN: $PROTOCOL failed but $ALT_PROTOCOL returned $HTTP_CODE (consider --protocol $ALT_PROTOCOL)"
    ((PASS++))
  else
    echo "  FAIL: No HTTP/HTTPS response from $ENDPOINT:$PORT"
    echo "  Check: backend service running, LB listener port, health check status"
    ((FAIL++))
  fi
fi
echo ""

# Test 4: Reindex test (optional)
echo "[4/4] Reindex Test"
if [[ -n "$ES_HOST" && -n "$ES_PASS" && -n "$REMOTE_INDEX" && -n "$LOCAL_INDEX" ]]; then
  echo "  Running reindex from $REMOTE_INDEX -> $LOCAL_INDEX (sample: 10 docs) ..."
  RESPONSE=$(curl -sk -u "$ES_USER:$ES_PASS" -X POST "$ES_HOST/_reindex?wait_for_completion=true" \
    -H 'Content-Type: application/json' -d "{
      \"source\": {
        \"remote\": {
          \"host\": \"$PROTOCOL://$ENDPOINT:$PORT\",
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

  # Parse response — prefer jq, fall back to grep
  REINDEX_OK=false
  if command -v jq &>/dev/null; then
    FAILURES=$(echo "$RESPONSE" | jq -r '.failures | length' 2>/dev/null || echo "unknown")
    TOTAL=$(echo "$RESPONSE" | jq -r '.total // "unknown"' 2>/dev/null)
    CREATED=$(echo "$RESPONSE" | jq -r '.created // "unknown"' 2>/dev/null)
    if [[ "$FAILURES" == "0" ]]; then
      REINDEX_OK=true
    fi
  else
    # Fallback: grep-based parsing
    if echo "$RESPONSE" | grep -q '"failures":\[\]'; then
      REINDEX_OK=true
      TOTAL=$(echo "$RESPONSE" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
      CREATED=$(echo "$RESPONSE" | grep -o '"created":[0-9]*' | head -1 | cut -d: -f2)
    fi
  fi

  if $REINDEX_OK; then
    echo "  PASS: Reindex succeeded (total: ${TOTAL:-?}, created: ${CREATED:-?})"
    ((PASS++))

    if $CLEANUP; then
      echo "  Cleaning up test index '$LOCAL_INDEX' ..."
      DEL_RESP=$(curl -sk -u "$ES_USER:$ES_PASS" -X DELETE "$ES_HOST/$LOCAL_INDEX" 2>/dev/null)
      if echo "$DEL_RESP" | grep -q '"acknowledged":true'; then
        echo "  Cleanup: deleted '$LOCAL_INDEX'"
      else
        echo "  Cleanup: failed to delete '$LOCAL_INDEX' (manual cleanup needed)"
      fi
    fi
  else
    echo "  FAIL: Reindex response:"
    if command -v jq &>/dev/null; then
      echo "$RESPONSE" | jq -C '.' 2>/dev/null | head -10 || echo "  $RESPONSE" | head -5
    else
      echo "  $RESPONSE" | head -5
    fi
    ((FAIL++))
  fi
else
  echo "  SKIPPED (provide --es-host, --es-pass, --remote-index, --local-index to test)"
  ((SKIP++))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="
if [[ $FAIL -gt 0 ]]; then
  echo "Some tests FAILED — see output above for troubleshooting hints."
  exit 1
else
  echo "All executed tests passed."
  exit 0
fi
