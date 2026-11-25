#!/bin/bash

set -e

# ============================================================
# AI CLIENT / TENANT
# ============================================================

APISIX_ADMIN_KEY="13579@mokchhedul"
AI_CLIENT_KEY="13579mokMOK@"

curl -i -X PUT \
  "http://127.0.0.1:9180/apisix/admin/consumers" \
  -H "X-API-KEY: ${APISIX_ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "ai-client",
    "plugins": {
      "key-auth": {
        "key": "'"${AI_CLIENT_KEY}"'"
      },
      "ai-rate-limiting": {
        "limit": 50000,
        "time_window": 60,
        "limit_strategy": "total_tokens",
        "rejected_code": 429,
        "show_limit_quota_header": true
      }
    }
  }'