#!/usr/bin/env bash
# build.sh — runs at Cloudflare Pages build time.
#
# Substitutes SUPABASE_URL and SUPABASE_ANON_KEY environment variables into
# index.html, replacing the __SUPABASE_URL__ and __SUPABASE_ANON_KEY__
# placeholders that ship in the source.
#
# Cloudflare Pages exposes env vars (set in the Pages dashboard under
# Settings → Environment variables) to this script via the standard
# environment. After this script runs, the deployed HTML has the real
# values inlined.
#
# This script is portable across GNU sed (Linux/Cloudflare) and BSD sed
# (macOS) by using the read-then-write pattern instead of `sed -i`.

set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ]; then
  echo "WARNING: SUPABASE_URL not set; placeholders will remain in HTML."
  echo "Set it in Cloudflare Pages → Settings → Environment variables."
fi
if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "WARNING: SUPABASE_ANON_KEY not set; placeholders will remain in HTML."
fi

SUPABASE_URL_VALUE="${SUPABASE_URL:-}"
SUPABASE_ANON_KEY_VALUE="${SUPABASE_ANON_KEY:-}"

# Substitute placeholders in index.html (and any other HTML files we add later)
for f in index.html; do
  if [ -f "$f" ]; then
    sed -e "s|__SUPABASE_URL__|${SUPABASE_URL_VALUE}|g" \
        -e "s|__SUPABASE_ANON_KEY__|${SUPABASE_ANON_KEY_VALUE}|g" \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "Substituted env vars into $f"
  fi
done

echo "Build complete."
