# Sourced by build.sh. macOS keeps the Accessibility permission for an app as
# long as a new version satisfies the code requirement recorded when it was
# granted. An ad-hoc signature's requirement is the binary's hash, which every
# build changes, so the permission had to be granted again. Signing with one
# fixed certificate makes the requirement "this bundle identifier, signed by
# this certificate", which later versions also satisfy.
#
# The self-signed identity is created on first use in .signing/ (ignored by
# git) inside its own keychain file. The login keychain, the keychain search
# list and the system's trust settings are left untouched.
SIGN_DIR="$PWD/.signing"
SIGN_KEYCHAIN="$SIGN_DIR/signing.keychain-db"
SIGN_NAME="DotaPing Local Signing"

ensure_signing_identity() {
    if [[ ! -f "$SIGN_KEYCHAIN" ]]; then
        mkdir -p "$SIGN_DIR"; chmod 700 "$SIGN_DIR"
        local work=$(mktemp -d) pass=$(/usr/bin/openssl rand -hex 16)
        print -r -- "$pass" > "$SIGN_DIR/password"; chmod 600 "$SIGN_DIR/password"
        cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
        # The system LibreSSL writes a PKCS#12 file that `security import` accepts.
        /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$work/cert.cnf" \
            -keyout "$work/key.pem" -out "$SIGN_DIR/certificate.pem" 2>/dev/null
        /usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$SIGN_DIR/certificate.pem" \
            -name "$SIGN_NAME" -passout "pass:$pass" -out "$work/identity.p12"
        local -a searchList=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
        security create-keychain -p "$pass" "$SIGN_KEYCHAIN"
        if [[ "$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')" != "${(F)searchList}" ]]; then
            security list-keychains -d user -s "${searchList[@]}"
        fi
        security import "$work/identity.p12" -k "$SIGN_KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$SIGN_KEYCHAIN" >/dev/null
        rm -rf "$work"
        print "Created signing identity \"$SIGN_NAME\" in $SIGN_DIR (keep this folder to keep permissions across versions)."
    fi
    security unlock-keychain -p "$(<"$SIGN_DIR/password")" "$SIGN_KEYCHAIN"
    SIGN_ID=$(security find-identity -p codesigning "$SIGN_KEYCHAIN" | awk -v name="\"$SIGN_NAME\"" '$0 ~ name { print $2; exit }')
    if [[ -z "$SIGN_ID" ]]; then print -u2 "No signing identity found in $SIGN_KEYCHAIN"; return 1; fi
}
