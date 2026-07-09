#!/bin/zsh
# Create a stable self-signed code-signing certificate named "GTime Self-Signed"
# in the login keychain. Signing GTime with it (instead of ad-hoc) gives a
# constant code signature, so the Accessibility permission you grant once keeps
# working across rebuilds. Idempotent: does nothing if the cert already exists.
set -e

NAME="GTime Self-Signed"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Signing certificate \"$NAME\" already exists. Nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = GTime Self-Signed
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -config "$TMP/cert.cnf" >/dev/null 2>&1

# -legacy: macOS `security` can't read OpenSSL 3's default PKCS12 MAC.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:gtime -name "$NAME" >/dev/null 2>&1

# -A lets codesign use the key without an ACL prompt on every build.
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
  -P gtime -T /usr/bin/codesign -A

echo "Created \"$NAME\". Rebuild with ./build.sh; grant Accessibility once and it will persist."
