#!/usr/bin/env bash
# health-check.sh — smoke-test a deployed gizmo-sandbox-bridge worker.
#
# Usage:
#   bash script/health-check.sh <bridge-url> <api-token>
#
# Example:
#   bash script/health-check.sh https://gizmo-sandbox-bridge-abc.example.workers.dev sk_...
#
# Runs 6 sequential checks. Exits 0 on full pass, 1 on any failure.
# Each step prints a one-line result. Verbose mode: SET DEBUG=1.
#
# Tests:
#   1. Auth: GET /v1/openapi.json without token → 401
#   2. Auth: GET /v1/openapi.json with token   → 200 + JSON OpenAPI
#   3. Lifecycle: POST /v1/sandbox → returns {id}
#   4. Exec SSE: POST /v1/sandbox/{id}/exec running `python3 -c 'print("ok")'`
#                → SSE stream contains stdout `ok` and exit_code 0
#   5. File round-trip: PUT/GET /v1/sandbox/{id}/file/workspace/test.txt
#   6. Lifecycle teardown: DELETE /v1/sandbox/{id} → 204
#
# Requires: bash, curl, jq, base64. (jq + base64 ship with macOS.)
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <bridge-url> <api-token>" >&2
  exit 64
fi

URL="${1%/}" # strip trailing slash
TOKEN="$2"
DEBUG="${DEBUG:-0}"

PASS=0
FAIL=0
SANDBOX_ID=""

run() {
  local label="$1"
  shift
  if [[ "$DEBUG" == "1" ]]; then
    echo "  → $*" >&2
  fi
  if "$@"; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    FAIL=$((FAIL + 1))
    return 1
  fi
}

# 1. Auth: no token rejected
test_auth_rejected() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$URL/v1/openapi.json")
  [[ "$code" == "401" ]]
}

# 2. Auth: with token accepted, returns OpenAPI JSON
test_auth_accepted() {
  local body
  body=$(curl -s -H "Authorization: Bearer $TOKEN" "$URL/v1/openapi.json")
  echo "$body" | jq -e '.openapi' > /dev/null
}

# 3. Create sandbox
test_create_sandbox() {
  local resp
  resp=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" "$URL/v1/sandbox")
  SANDBOX_ID=$(echo "$resp" | jq -re '.id')
  [[ -n "$SANDBOX_ID" ]]
}

# 4. Exec SSE — `python3 -c 'print("ok")'` should yield stdout "ok\n" + exit 0
test_exec_sse() {
  local body stdout exit_code
  body=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream" \
    -d '{"argv":["python3","-c","print(\"ok\")"],"timeout_ms":15000}' \
    "$URL/v1/sandbox/$SANDBOX_ID/exec")
  # SSE event lines look like:  event: stdout\n  data: <base64>\n
  stdout=$(echo "$body" | awk '/^event: stdout/{flag=1;next} /^data:/&&flag{print substr($0,7); flag=0}' | base64 -d 2>/dev/null | tr -d '\n')
  exit_code=$(echo "$body" | awk '/^event: exit/{flag=1;next} /^data:/&&flag{print; flag=0}' | sed 's/^data: //' | jq -re '.exit_code' 2>/dev/null || echo "")
  [[ "$stdout" == "ok" ]] && [[ "$exit_code" == "0" ]]
}

# 5. File PUT then GET round-trip
test_file_roundtrip() {
  local content="hello $(date +%s)"
  local got
  curl -s -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "$content" \
    "$URL/v1/sandbox/$SANDBOX_ID/file/workspace/test.txt" > /dev/null
  got=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$URL/v1/sandbox/$SANDBOX_ID/file/workspace/test.txt")
  [[ "$got" == "$content" ]]
}

# 6. Destroy sandbox
test_destroy_sandbox() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer $TOKEN" "$URL/v1/sandbox/$SANDBOX_ID")
  [[ "$code" == "204" ]]
}

echo "gizmo-sandbox-bridge health check"
echo "  url:    $URL"
echo "  token:  ${TOKEN:0:8}…"
echo

run "01  auth: missing token rejected (401)"     test_auth_rejected     || true
run "02  auth: token accepted, OpenAPI returned" test_auth_accepted     || true
run "03  lifecycle: POST /v1/sandbox"            test_create_sandbox    || true
run "04  exec: SSE stdout + exit_code"           test_exec_sse          || true
run "05  file: PUT + GET round-trip"             test_file_roundtrip    || true
run "06  lifecycle: DELETE /v1/sandbox/{id}"     test_destroy_sandbox   || true

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]]
