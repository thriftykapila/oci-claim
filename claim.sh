#!/bin/bash
# claim.sh — OCI A1 Ampere auto-claim using bash + curl + openssl only.
# No Python. No extra packages. Runs inside GitHub Actions ubuntu-latest.
#
# All config comes from environment variables (GitHub Secrets).

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── Validate required env vars ────────────────────────────────────────────────
fail=0
for var in OCI_TENANCY_OCID OCI_USER_OCID OCI_FINGERPRINT OCI_PRIVATE_KEY \
           OCI_REGION OCI_COMPARTMENT_ID OCI_SUBNET_ID OCI_IMAGE_ID OCI_SSH_PUBLIC_KEY; do
    if [[ -z "${!var:-}" ]]; then
        log "ERROR: $var is not set"
        fail=1
    fi
done
[[ "$fail" -eq 1 ]] && exit 1

INSTANCE_NAME="${OCI_INSTANCE_NAME:-xeli-a1-staging}"
SHAPE="VM.Standard.A1.Flex"
OCPUS="${OCI_OCPUS:-4}"
MEMORY_GB="${OCI_MEMORY_GB:-24}"
NOTIFY_URL="${NTFY_URL:-}"

# Write private key to temp file
KEY_FILE=$(mktemp)
echo "$OCI_PRIVATE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"
trap "rm -f $KEY_FILE" EXIT

# ── OCI HTTP Signature helper ─────────────────────────────────────────────────
oci_get() {
    local host="$1" path="$2"
    local date_str; date_str=$(date -u '+%a, %d %b %Y %H:%M:%S GMT')
    local key_id="${OCI_TENANCY_OCID}/${OCI_USER_OCID}/${OCI_FINGERPRINT}"
    local signing_string="(request-target): get ${path}
host: ${host}
date: ${date_str}"

    local sig; sig=$(printf '%s' "$signing_string" | openssl dgst -sha256 -sign "$KEY_FILE" | base64 | tr -d '\n')
    local auth="Signature version=\"1\",keyId=\"${key_id}\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date\",signature=\"${sig}\""

    curl -sf "https://${host}${path}" \
        -H "Date: ${date_str}" -H "Host: ${host}" -H "Authorization: ${auth}" \
        --max-time 15
}

oci_post() {
    local host="$1" path="$2" body="$3"
    local date_str; date_str=$(date -u '+%a, %d %b %Y %H:%M:%S GMT')
    local key_id="${OCI_TENANCY_OCID}/${OCI_USER_OCID}/${OCI_FINGERPRINT}"
    local body_sha256; body_sha256=$(printf '%s' "$body" | openssl dgst -sha256 -binary | base64)
    local body_len=${#body}
    local signing_string="(request-target): post ${path}
host: ${host}
date: ${date_str}
content-type: application/json
x-content-sha256: ${body_sha256}
content-length: ${body_len}"

    local sig; sig=$(printf '%s' "$signing_string" | openssl dgst -sha256 -sign "$KEY_FILE" | base64 | tr -d '\n')
    local auth="Signature version=\"1\",keyId=\"${key_id}\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date content-type x-content-sha256 content-length\",signature=\"${sig}\""

    curl -s -w "\n__HTTP_CODE__:%{http_code}" \
        -X POST "https://${host}${path}" \
        -H "Date: ${date_str}" -H "Host: ${host}" \
        -H "Content-Type: application/json" \
        -H "x-content-sha256: ${body_sha256}" \
        -H "Content-Length: ${body_len}" \
        -H "Authorization: ${auth}" \
        -d "$body" --max-time 30
}

notify() {
    [[ -z "$NOTIFY_URL" ]] && return
    curl -s -X POST "$NOTIFY_URL" \
        -H "Title: OCI A1 Claimed!" -H "Priority: urgent" -H "Tags: rocket" \
        -d "$1" --max-time 10 || true
}

# ── Get availability domains ──────────────────────────────────────────────────
IDENTITY_HOST="identity.${OCI_REGION}.oraclecloud.com"
log "Fetching availability domains..."
ADS=$(oci_get "$IDENTITY_HOST" "/20160918/availabilityDomains?compartmentId=${OCI_COMPARTMENT_ID}" \
    | grep -o '"name":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$ADS" ]]; then
    log "ERROR: Could not fetch ADs — check credentials/region"
    exit 1
fi
log "ADs: $(echo "$ADS" | tr '\n' ' ')"

# ── Try each AD in a continuous loop for 260s (fits in 5-min workflow window) ─
IAAS_HOST="iaas.${OCI_REGION}.oraclecloud.com"
SSH_ESCAPED=$(echo "$OCI_SSH_PUBLIC_KEY" | sed 's/"/\\"/g')
CLAIMED=0
START_TIME=$(date +%s)
DURATION="${OCI_DURATION:-260}"
INTERVAL="${OCI_RETRY_INTERVAL:-10}"

log "Starting claim loop (retrying every ${INTERVAL}s for up to ${DURATION}s)..."

attempt=0
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [[ "$ELAPSED" -ge "$DURATION" ]]; then
        log "Reached duration limit of ${DURATION}s (${ELAPSED}s elapsed). Exiting run."
        exit 0
    fi

    attempt=$((attempt + 1))
    while IFS= read -r AD; do
        [[ -z "$AD" ]] && continue
        log "Attempt #${attempt} — Trying AD: $AD"

        BODY=$(cat <<EOF
{
  "availabilityDomain":"${AD}",
  "compartmentId":"${OCI_COMPARTMENT_ID}",
  "displayName":"${INSTANCE_NAME}",
  "shape":"${SHAPE}",
  "shapeConfig":{"ocpus":${OCPUS},"memoryInGBs":${MEMORY_GB}},
  "createVnicDetails":{"subnetId":"${OCI_SUBNET_ID}","assignPublicIp":true},
  "sourceDetails":{"sourceType":"image","imageId":"${OCI_IMAGE_ID}"},
  "metadata":{"ssh_authorized_keys":"${SSH_ESCAPED}"},
  "freeformTags":{"managed-by":"oci-claim-actions"}
}
EOF
)

        RESULT=$(oci_post "$IAAS_HOST" "/20160918/instances" "$BODY")
        HTTP_CODE=$(echo "$RESULT" | grep -o '__HTTP_CODE__:[0-9]*' | cut -d: -f2)
        BODY_OUT=$(echo "$RESULT" | sed 's/__HTTP_CODE__:[0-9]*$//')

        if [[ "$HTTP_CODE" == "200" ]]; then
            INSTANCE_ID=$(echo "$BODY_OUT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
            log "=================================================="
            log "✅  INSTANCE CLAIMED SUCCESSFULLY!"
            log "   Instance ID : ${INSTANCE_ID}"
            log "   AD          : ${AD}"
            log "   Name        : ${INSTANCE_NAME}"
            log "=================================================="
            notify "OCI A1 '${INSTANCE_NAME}' claimed in ${AD}! Instance ID: ${INSTANCE_ID}"
            exit 0
        elif echo "$BODY_OUT" | grep -qi "Out of host capacity"; then
            log "  Out of capacity in ${AD}"
        elif [[ "$HTTP_CODE" == "429" ]]; then
            log "  Rate limited — sleeping 30s extra"
            sleep 30
            break
        else
            log "  Unexpected HTTP ${HTTP_CODE}: ${BODY_OUT:0:200}"
        fi
    done <<< "$ADS"

    NEXT_ELAPSED=$(( $(date +%s) - START_TIME + INTERVAL ))
    if [[ "$NEXT_ELAPSED" -gt "$DURATION" ]]; then
        log "Next retry would exceed duration limit (${DURATION}s). Exiting run."
        exit 0
    fi

    log "Sleeping ${INTERVAL}s before next attempt..."
    sleep "$INTERVAL"
done
