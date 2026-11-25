
#!/usr/bin/env bash

set -Eeuo pipefail

# ==========================================
# APISIX mTLS Certificate Generator
# Environment: Localhost / Docker
# ==========================================

CERT_DIR="./certs"
VALIDITY_DAYS=365
CA_VALIDITY_DAYS=3650

echo "======================================"
echo " APISIX mTLS Certificate Generator"
echo "======================================"

# Check OpenSSL
if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: OpenSSL is not installed."
    exit 1
fi

# Prevent accidental overwrite
if [[ -d "$CERT_DIR" ]] && \
   [[ -n "$(find "$CERT_DIR" -maxdepth 1 -type f -print -quit)" ]]; then
    if [[ "${FORCE:-0}" != "1" ]]; then
        echo "ERROR: $CERT_DIR already contains files."
        echo "Use FORCE=1 to regenerate certificates."
        exit 1
    fi
fi

mkdir -p "$CERT_DIR"

# ==========================================
# 1. Generate Root CA
# ==========================================

echo "[1/3] Generating Root CA..."

openssl genrsa -out "$CERT_DIR/ca.key" 4096

openssl req -x509 -new -nodes \
    -key "$CERT_DIR/ca.key" \
    -sha256 \
    -days "$CA_VALIDITY_DAYS" \
    -out "$CERT_DIR/ca.crt" \
    -subj "/CN=APISIX-mTLS-Root-CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"

# ==========================================
# 2. Generate APISIX Server Certificate
# ==========================================

echo "[2/3] Generating APISIX Server Certificate..."

openssl genrsa -out "$CERT_DIR/server.key" 2048

openssl req -new \
    -key "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.csr" \
    -subj "/CN=localhost"

cat > "$CERT_DIR/server.ext" <<EOF
basicConstraints=critical,CA:FALSE
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF

openssl x509 -req \
    -in "$CERT_DIR/server.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/server.crt" \
    -days "$VALIDITY_DAYS" \
    -sha256 \
    -extfile "$CERT_DIR/server.ext"

# ==========================================
# 3. Generate Client Certificate
# ==========================================

echo "[3/3] Generating Client Certificate..."

openssl genrsa -out "$CERT_DIR/client.key" 2048

openssl req -new \
    -key "$CERT_DIR/client.key" \
    -out "$CERT_DIR/client.csr" \
    -subj "/CN=apisix-client-1"

cat > "$CERT_DIR/client.ext" <<EOF
basicConstraints=critical,CA:FALSE
extendedKeyUsage=clientAuth
keyUsage=digitalSignature
EOF

openssl x509 -req \
    -in "$CERT_DIR/client.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/client.crt" \
    -days "$VALIDITY_DAYS" \
    -sha256 \
    -extfile "$CERT_DIR/client.ext"

# ==========================================
# 4. Set Permissions
# ==========================================

chmod 600 "$CERT_DIR"/*.key
chmod 644 "$CERT_DIR"/*.crt

# ==========================================
# 5. Verify Certificates
# ==========================================

echo ""
echo "Verifying certificates..."

openssl verify \
    -CAfile "$CERT_DIR/ca.crt" \
    "$CERT_DIR/server.crt" \
    "$CERT_DIR/client.crt"

# Check certificate purposes
openssl x509 -in "$CERT_DIR/server.crt" -noout -ext subjectAltName
openssl x509 -in "$CERT_DIR/server.crt" -noout -ext extendedKeyUsage
openssl x509 -in "$CERT_DIR/client.crt" -noout -ext extendedKeyUsage

echo ""
echo "======================================"
echo " mTLS Certificates Generated!"
echo "======================================"

echo ""
echo "Generated files:"

ls -lh "$CERT_DIR"

echo ""
echo "Server certificate: $CERT_DIR/server.crt"
echo "Server private key: $CERT_DIR/server.key"
echo "Client certificate: $CERT_DIR/client.crt"
echo "Client private key: $CERT_DIR/client.key"
echo "Root CA:            $CERT_DIR/ca.crt"

echo ""
echo "IMPORTANT:"
echo "Never share ca.key, server.key or client.key."
echo "======================================"
