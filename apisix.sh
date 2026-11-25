
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# APISIX CONFIGURATION + mTLS SETUP
# Control Plane: 9180
# Data Plane HTTP: 9080
# Data Plane HTTPS/mTLS: 9443
# ==========================================

ADMIN_URL="http://127.0.0.1:9180/apisix/admin"
CERT_DIR="./certs"

echo "======================================"
echo " APISIX mTLS + ROUTE CONFIGURATION"
echo "======================================"

# ==========================================
# 1. CHECK DEPENDENCIES
# ==========================================

for cmd in curl python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: $cmd is required."
        exit 1
    }
done

echo "Dependencies verified."

# ==========================================
# 2. CHECK CERTIFICATES
# ==========================================

for file in ca.crt server.crt server.key client.crt client.key; do
    [[ -f "$CERT_DIR/$file" ]] || {
        echo "ERROR: Missing $CERT_DIR/$file"
        exit 1
    }
done

echo "Certificates verified."

# ==========================================
# 3. ADMIN API KEY
# ==========================================

read -r -s -p "Admin API Key: " ADMIN_KEY
echo

if [[ -z "$ADMIN_KEY" ]]; then
    echo "ERROR: Admin API key cannot be empty."
    exit 1
fi

# ==========================================
# HELPER FUNCTION
# CREATE / UPDATE APISIX RESOURCES
# ==========================================

put_json() {
    local endpoint="$1"

    echo
    echo "Registering: $endpoint"

    curl --fail-with-body -sS \
        -X PUT "$ADMIN_URL/$endpoint" \
        -H "X-API-KEY: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        --data-binary @-

    echo
}

# ==========================================
# 4. REGISTER mTLS SSL RESOURCE
# ==========================================

echo
echo "[1/8] Registering mTLS SSL resource..."

python3 - "$CERT_DIR" <<'PY' |
import json
import pathlib
import sys

cert_dir = pathlib.Path(sys.argv[1])

payload = {
    "cert": (cert_dir / "server.crt").read_text(),
    "key": (cert_dir / "server.key").read_text(),
    "snis": ["localhost"],
    "ssl_protocols": ["TLSv1.2", "TLSv1.3"],
    "client": {
        "ca": (cert_dir / "ca.crt").read_text(),
        "depth": 1
    }
}

print(json.dumps(payload))
PY
curl --fail-with-body -sS \
    -X PUT "$ADMIN_URL/ssls/1" \
    -H "X-API-KEY: $ADMIN_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @-

echo
echo "mTLS SSL resource registered."

# ==========================================
# 5. USER UPSTREAM
# ==========================================

echo
echo "[2/8] Creating User Upstream..."

put_json "upstreams/user-upstream" <<'EOF'
{
  "id": "user-upstream",
  "type": "roundrobin",
  "scheme": "http",
  "nodes": {
    "user-service:3000": 1
  },
  "timeout": {
    "connect": 6,
    "send": 6,
    "read": 6
  },
  "retries": 2
}
EOF

# ==========================================
# 6. USER SERVICE
# ==========================================

echo
echo "[3/8] Creating User Service..."

put_json "services/user-service" <<'EOF'
{
  "id": "user-service",
  "name": "user-service",
  "upstream_id": "user-upstream",
  "plugins": {
    "cors": {
      "allow_origins": "*",
      "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
      "allow_headers": "*",
      "expose_headers": "*",
      "max_age": 3600
    },
    "gzip": {
      "types": ["application/json", "text/plain"],
      "min_length": 1024
    },
    "request-id": {
      "header_name": "X-Request-Id",
      "include_in_response": true
    },
    "limit-count": {
      "count": 100,
      "time_window": 60,
      "rejected_code": 429,
      "key_type": "var",
      "key": "remote_addr"
    }
  }
}
EOF

# ==========================================
# 7. USER ROUTE
# ==========================================

echo
echo "[4/8] Creating User Route..."

put_json "routes/user-route" <<'EOF'
{
  "id": "user-route",
  "uri": "/auth/*",
  "service_id": "user-service",
  "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}
EOF

# ==========================================
# 8. PRODUCT UPSTREAM
# ==========================================

echo
echo "[5/8] Creating Product Upstream..."

put_json "upstreams/product-upstream" <<'EOF'
{
  "id": "product-upstream",
  "type": "roundrobin",
  "scheme": "http",
  "nodes": {
    "product-service:3001": 1
  },
  "timeout": {
    "connect": 6,
    "send": 6,
    "read": 6
  },
  "retries": 2
}
EOF

# ==========================================
# 9. PRODUCT SERVICE
# ==========================================

echo
echo "[6/8] Creating Product Service..."

put_json "services/product-service" <<'EOF'
{
  "id": "product-service",
  "name": "product-service",
  "upstream_id": "product-upstream",
  "plugins": {
    "cors": {
      "allow_origins": "*",
      "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
      "allow_headers": "*",
      "expose_headers": "*",
      "max_age": 3600
    }
  }
}
EOF

# ==========================================
# 10. PRODUCT PUBLIC GET ROUTE
# ==========================================

echo
echo "[7/8] Creating Product Public GET Route..."

put_json "routes/product-public-route" <<'EOF'
{
  "id": "product-public-route",
  "uri": "/products",
  "methods": ["GET"],
  "priority": 10,
  "service_id": "product-service"
}
EOF

# ==========================================
# 11. PRODUCT PROTECTED POST ROUTE
# ==========================================

echo
echo "[8/8] Creating Product Protected POST Route..."

put_json "routes/product-protected-post-route" <<'EOF'
{
  "id": "product-protected-post-route",
  "uri": "/products",
  "methods": ["POST"],
  "priority": 20,
  "service_id": "product-service",
  "plugins": {
    "forward-auth": {
      "uri": "http://user-service:3000/auth/verify",
      "request_headers": ["Authorization"],
      "upstream_headers": [
        "X-User-Id",
        "X-User-Email",
        "X-User-Role",
        "X-User-Name"
      ],
      "client_headers": [
        "X-User-Id",
        "X-User-Email"
      ],
      "keep_context": false,
      "timeout": 5000,
      "allow_missing_headers": false
    }
  }
}
EOF

# ==========================================
# CLEANUP
# ==========================================

unset ADMIN_KEY

echo
echo "======================================"
echo " APISIX CONFIGURATION COMPLETED"
echo "======================================"
echo " mTLS SSL Resource: Registered"
echo " User Upstream:     Registered"
echo " User Service:      Registered"
echo " User Route:        Registered"
echo " Product Upstream:  Registered"
echo " Product Service:   Registered"
echo " Product GET:       Registered"
echo " Product POST:      Registered"
echo "======================================"











# # ================= ssl setup =================
# # curl http://127.0.0.1:9180/apisix/admin/ssls/1 \
# #   -H "X-API-KEY: YOUR_ADMIN_KEY" \
# #   -X PUT \
# #   -d '{
# #     "cert": "'"$(cat certs/fullchain.pem)"'",
# #     "key": "'"$(cat certs/privkey.pem)"'",
# #     "snis": [
# #       "api.example.com"
# #     ]
# #   }'
# # ================= ১. USER UPSTREAM =================
# curl http://127.0.0.1:9180/apisix/admin/upstreams/user-upstream \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "user-upstream",
#   "type": "roundrobin",
#   "scheme": "http",
#   "nodes": {
#     "user-service:3000": 1
#   },
#   "timeout": {
#     "connect": 6,
#     "send": 6,
#     "read": 6
#   },
#   "retries": 2
# }'

# # ================= ২. USER SERVICE =================
# curl http://127.0.0.1:9180/apisix/admin/services/user-service \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "user-service",
#   "name": "user-service",
#   "upstream_id": "user-upstream",
#   "plugins": {
#     "cors": {
#       "allow_origins": "*",
#       "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
#       "allow_headers": "*",
#       "expose_headers": "*",
#       "max_age": 3600
#     },
#     "gzip": {
#       "types": ["application/json", "text/plain"],
#       "min_length": 1024
#     },
#     "request-id": {
#       "header_name": "X-Request-Id",
#       "include_in_response": true
#     },
#     "limit-count": {
#       "count": 100,
#       "time_window": 60,
#       "rejected_code": 429,
#       "key_type": "var",
#       "key": "remote_addr"
#     }
#   }
# }'

# # ================= ৩. USER ROUTE =================
# curl http://127.0.0.1:9180/apisix/admin/routes/user-route \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "user-route",
#   "uri": "/auth/*",
#   "service_id": "user-service",
#   "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
# }'

# # ================= ৪. PRODUCT UPSTREAM =================
# curl http://127.0.0.1:9180/apisix/admin/upstreams/product-upstream \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "product-upstream",
#   "type": "roundrobin",
#   "scheme": "http",
#   "nodes": {
#     "product-service:3001": 1
#   },
#   "timeout": {
#     "connect": 6,
#     "send": 6,
#     "read": 6
#   },
#   "retries": 2
# }'

# # ================= ৫. PRODUCT SERVICE =================
# curl http://127.0.0.1:9180/apisix/admin/services/product-service \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "product-service",
#   "name": "product-service",
#   "upstream_id": "product-upstream",
#   "plugins": {
#     "cors": {
#       "allow_origins": "*",
#       "allow_methods": "GET,POST,PUT,DELETE,OPTIONS",
#       "allow_headers": "*",
#       "expose_headers": "*",
#       "max_age": 3600
#     }
#   }
# }'

# # ================= ৬. PRODUCT PUBLIC GET ROUTE =================
# curl http://127.0.0.1:9180/apisix/admin/routes/product-public-route \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "product-public-route",
#   "uri": "/products",
#   "methods": ["GET"],
#   "priority": 10,
#   "service_id": "product-service"
# }'


# # ================= ৮. PRODUCT PROTECTED CREATE ROUTE (POST) =================
# curl http://127.0.0.1:9180/apisix/admin/routes/product-protected-post-route \
# -X PUT \
# -H "X-API-KEY: 13579@mokchhedul" \
# -H "Content-Type: application/json" \
# -d '
# {
#   "id": "product-protected-post-route",
#   "uri": "/products",
#   "methods": ["POST"],
#   "priority": 20,
#   "service_id": "product-service",
#   "plugins": {
#     "forward-auth": {
#       "uri": "http://user-service:3000/auth/verify",
#       "request_headers": ["Authorization"],
#       "upstream_headers": [
#         "X-User-Id",
#         "X-User-Email",
#         "X-User-Role",
#         "X-User-Name"
#       ],
#       "client_headers": [
#         "X-User-Id",
#         "X-User-Email"
#       ],
#       "keep_context": false,
#       "timeout": 5000,
#       "allow_missing_headers": false
#     }
#   }
# }'










