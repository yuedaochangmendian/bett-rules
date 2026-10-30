#!/usr/bin/env bash
#
# Build ONE sing-box binary rule-set (.srs) out of the rule-set source JSONs
# published on the `sing` branch of appshubcc/bett-rules.
#
# Usage:
#   bash scripts/build-srs.sh
#
# Environment:
#   SING_BOX_BIN      path to an existing sing-box binary (skips download)
#   SING_BOX_VERSION  sing-box release to download when SING_BOX_BIN is unset (default 1.14.4)
#   SRC_REPO          upstream repo (default appshubcc/bett-rules)
#   SRC_REF           branch holding geo/geosite/*.json (default sing)
#   SETS              space separated rule-set names, no extension (default "geolocation-!cn")
#   OUT_DIR           output directory (default dist)
#   VERIFY_MATCH      domain expected to match   (default google.com, empty = skip)
#   VERIFY_NOMATCH    domain expected to NOT match (default baidu.com, empty = skip)
#
set -euo pipefail

SING_BOX_VERSION="${SING_BOX_VERSION:-1.14.4}"
SRC_REPO="${SRC_REPO:-appshubcc/bett-rules}"
SRC_REF="${SRC_REF:-sing}"
SETS="${SETS:-geolocation-!cn}"
OUT_DIR="${OUT_DIR:-dist}"
VERIFY_MATCH="${VERIFY_MATCH-google.com}"
VERIFY_NOMATCH="${VERIFY_NOMATCH-baidu.com}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '==> %s\n' "$*"; }

# ---------------------------------------------------------------- sing-box
if [ -z "${SING_BOX_BIN:-}" ]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)          ASSET="linux-amd64.tar.gz" ;;
    Linux-aarch64|Linux-arm64) ASSET="linux-arm64.tar.gz" ;;
    Darwin-arm64)          ASSET="darwin-arm64.tar.gz" ;;
    Darwin-x86_64)         ASSET="darwin-amd64.tar.gz" ;;
    MINGW*|MSYS*|CYGWIN*)  ASSET="windows-amd64.zip" ;;
    *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
  esac
  NAME="sing-box-${SING_BOX_VERSION}-${ASSET}"
  URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${NAME}"
  log "downloading ${URL}"
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -o "$WORK/$NAME" "$URL"
  case "$NAME" in
    *.zip) unzip -q "$WORK/$NAME" -d "$WORK" ;;
    *)     tar -xzf "$WORK/$NAME" -C "$WORK" ;;
  esac
  SING_BOX_BIN="$(find "$WORK" -type f \( -name sing-box -o -name sing-box.exe \) | head -1)"
fi

[ -x "$SING_BOX_BIN" ] || { echo "sing-box binary not executable: $SING_BOX_BIN" >&2; exit 1; }
log "sing-box: $("$SING_BOX_BIN" version | head -1)"

# ---------------------------------------------------------------- download sources
mkdir -p "$WORK/src" "$OUT_DIR"
MERGE_ARGS=()
for set in $SETS; do
  enc="${set//!/%21}"
  enc="${enc//@/%40}"
  enc="${enc// /%20}"
  url="https://raw.githubusercontent.com/${SRC_REPO}/${SRC_REF}/geo/geosite/${enc}.json"
  log "fetching ${set}"
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -o "$WORK/src/${set}.json" "$url"
  MERGE_ARGS+=("-c" "$WORK/src/${set}.json")
done

# ---------------------------------------------------------------- merge + compile
log "merging ${#MERGE_ARGS[@]} arg(s)"
"$SING_BOX_BIN" rule-set merge "$WORK/merged.json" "${MERGE_ARGS[@]}"
"$SING_BOX_BIN" rule-set compile "$WORK/merged.json" -o "$OUT_DIR/bett.srs"
cp "$WORK/merged.json" "$OUT_DIR/bett.json"

# ---------------------------------------------------------------- self-check
if [ -n "$VERIFY_MATCH" ]; then
  out="$("$SING_BOX_BIN" rule-set match -f binary "$OUT_DIR/bett.srs" "$VERIFY_MATCH" 2>&1 || true)"
  [ -n "$out" ] || { echo "SELF-CHECK FAILED: '$VERIFY_MATCH' did not match" >&2; exit 1; }
  log "self-check ok: $VERIFY_MATCH matched"
fi
if [ -n "$VERIFY_NOMATCH" ]; then
  out="$("$SING_BOX_BIN" rule-set match -f binary "$OUT_DIR/bett.srs" "$VERIFY_NOMATCH" 2>&1 || true)"
  [ -z "$out" ] || { echo "SELF-CHECK FAILED: '$VERIFY_NOMATCH' unexpectedly matched" >&2; exit 1; }
  log "self-check ok: $VERIFY_NOMATCH not matched"
fi

# ---------------------------------------------------------------- metadata
COMMIT="$(git ls-remote "https://github.com/${SRC_REPO}" "refs/heads/${SRC_REF}" 2>/dev/null | cut -f1 || true)"
SRS_SIZE="$(wc -c < "$OUT_DIR/bett.srs" | tr -d ' ')"
JSON_SIZE="$(wc -c < "$OUT_DIR/bett.json" | tr -d ' ')"
cat > "$OUT_DIR/meta.json" <<EOF
{
  "source_repo": "${SRC_REPO}",
  "source_ref": "${SRC_REF}",
  "source_commit": "${COMMIT:-unknown}",
  "sets": "$(echo $SETS | tr ' ' ',')",
  "sing_box_version": "${SING_BOX_VERSION}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "srs_bytes": ${SRS_SIZE},
  "json_bytes": ${JSON_SIZE}
}
EOF

log "done:"
ls -l "$OUT_DIR"
