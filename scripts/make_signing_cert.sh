#!/usr/bin/env bash
# Generates the self-signed code signing certificate used for Recall releases.
#
# Run once. The certificate is the app's identity as far as macOS TCC is
# concerned: as long as every release is signed with this same cert, users'
# Accessibility grants survive upgrades. If the cert is lost and regenerated,
# every user gets re-prompted once — back up the output directory.
#
# Usage:
#   ./scripts/make_signing_cert.sh [output-dir]   # default: ~/.recall-signing
#
# Afterwards, upload to GitHub Actions secrets:
#   gh secret set SIGNING_CERT_P12      < <output-dir>/recall-signing.p12.base64
#   gh secret set SIGNING_CERT_PASSWORD < <output-dir>/p12-password.txt

set -euo pipefail

CERT_NAME="Recall Code Signing"
OUT_DIR="${1:-${HOME}/.recall-signing}"
DAYS=3650  # 10 years

if [[ -f "${OUT_DIR}/recall-signing.p12" ]]; then
  echo "✗ ${OUT_DIR}/recall-signing.p12 already exists." >&2
  echo "  Regenerating would change the signing identity and reset users' TCC grants." >&2
  echo "  Delete it manually first if you really mean to." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

P12_PASSWORD="$(openssl rand -hex 16)"

echo "▸ Generating self-signed code signing certificate (${DAYS} days)…"
openssl req -x509 -newkey rsa:2048 -nodes -days "${DAYS}" \
  -keyout "${OUT_DIR}/recall-signing.key" \
  -out "${OUT_DIR}/recall-signing.crt" \
  -config <(cat <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${CERT_NAME}
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF
)

echo "▸ Exporting PKCS#12 bundle…"
# SHA1-3DES PBE: OpenSSL 3 defaults to AES/PBKDF2, which `security import` rejects
openssl pkcs12 -export \
  -inkey "${OUT_DIR}/recall-signing.key" \
  -in "${OUT_DIR}/recall-signing.crt" \
  -name "${CERT_NAME}" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:${P12_PASSWORD}" \
  -out "${OUT_DIR}/recall-signing.p12"

printf '%s' "${P12_PASSWORD}" > "${OUT_DIR}/p12-password.txt"
base64 -i "${OUT_DIR}/recall-signing.p12" -o "${OUT_DIR}/recall-signing.p12.base64"
chmod 600 "${OUT_DIR}"/*

echo ""
echo "✓ Certificate written to ${OUT_DIR}/"
echo ""
echo "Next steps:"
echo "  1. Back up ${OUT_DIR} somewhere safe (password manager, encrypted backup)."
echo "  2. Upload to GitHub Actions secrets:"
echo "       gh secret set SIGNING_CERT_P12      < ${OUT_DIR}/recall-signing.p12.base64"
echo "       gh secret set SIGNING_CERT_PASSWORD < ${OUT_DIR}/p12-password.txt"
