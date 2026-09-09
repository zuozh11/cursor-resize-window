#!/usr/bin/env bash
set -euo pipefail

# Creates the self-signed code-signing certificate the Homebrew formula uses so
# macOS keeps the Accessibility grant across rebuilds.

identity="cursor-resize-window-signing"
keychain="$HOME/Library/Keychains/login.keychain-db"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

if security find-identity -p codesigning "$keychain" 2>/dev/null | grep -q "$identity"; then
  echo "Signing identity '$identity' already exists in $keychain"
  exit 0
fi

cat > "$workdir/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $identity
[ext]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$workdir/key.pem" -out "$workdir/cert.pem" -config "$workdir/openssl.cnf" 2>/dev/null

# macOS rejects the default PKCS12 MAC and PBE algorithms, so export legacy parameters.
openssl pkcs12 -export -inkey "$workdir/key.pem" -in "$workdir/cert.pem" \
  -out "$workdir/identity.p12" -passout pass:cursor-resize-window \
  -name "$identity" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

security import "$workdir/identity.p12" -k "$keychain" -P cursor-resize-window \
  -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$workdir/cert.pem"

security find-identity -v -p codesigning "$keychain" | grep "$identity"
