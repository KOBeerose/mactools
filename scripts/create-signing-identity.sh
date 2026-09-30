#!/usr/bin/env bash
# Create a local, self-signed code-signing identity ("KobeTools Dev") in the login
# keychain. Build scripts use it when present, so macOS privacy grants
# (Accessibility, Screen Recording, Input Monitoring) survive rebuilds: they're
# tied to this certificate instead of each ad-hoc build's hash.
#
# Run once per Mac. macOS asks for your password to trust the certificate for
# code signing (and only for that). The private key never leaves the keychain.
set -euo pipefail

NAME="${1:-KobeTools Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # the system LibreSSL writes a PKCS#12 macOS can import

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists:"
  security find-identity -v -p codesigning | grep "\"$NAME\""
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Throwaway password for the temporary PKCS#12 file only. (Not `tr </dev/urandom
# | head`: under pipefail the SIGPIPE on tr aborts the script.)
pass="$("$OPENSSL" rand -hex 16)"

cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:3072 -nodes -days 3650 -sha256 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$NAME" -out "$tmp/identity.p12" -passout "pass:$pass"

# Only codesign may use the key without prompting.
security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

echo
security find-identity -v -p codesigning | grep "\"$NAME\""
echo "Done. Rebuild each app once, re-grant its permissions once, and they'll stick from then on."
