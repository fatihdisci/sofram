#!/usr/bin/env bash
#
# check-brand-rename.sh — guards the Calorisor → Calp rebrand.
#
# Fails (non-zero exit) if any pre-rename brand token survives in a tracked
# file outside of an explicitly allowed context. Run it in CI and before a
# release:
#
#     ./scripts/check-brand-rename.sh
#
# Forbidden tokens:
#     Calorisor  calorisor  CALORISOR  com.fatih.calorisor  x-calorisor-
#     Sofra      sofra      SOFRA
#
# Allowed (never flagged):
#   • Any line containing the marker  brand-keep  — deliberate legacy-compat
#     code (immutable App Store Connect product IDs, transition request-header
#     and env-var fallbacks, dual-read Redis keys).
#   • The literal  sofram  — the Vercel deployment host (sofram-five.vercel.app)
#     and the GitHub repo / local folder name, intentionally left unchanged.
#   • This script itself.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

FORBIDDEN='Calorisor|calorisor|CALORISOR|Sofra|sofra|SOFRA'

# Collect matches from tracked files, excluding this script, then drop every
# allowed context: brand-keep lines, and the `sofram` host/repo name (stripped
# before re-testing so a stray `sofra` on the same line would still fail).
hits="$(
  git grep -nE "$FORBIDDEN" -- . ':(exclude)scripts/check-brand-rename.sh' 2>/dev/null \
    | grep -v 'brand-keep' \
    | perl -ne 'my $l = $_; $l =~ s/sofram//g; print if $l =~ /Calorisor|calorisor|CALORISOR|Sofra|sofra|SOFRA/;' \
    || true
)"

if [ -n "$hits" ]; then
  echo "✗ Brand-rename audit FAILED — pre-rename tokens still present:"
  echo ""
  echo "$hits"
  echo ""
  echo "Rename them to Calp, or (only for deliberate legacy compat) add a"
  echo "'brand-keep' marker comment on the same line."
  exit 1
fi

echo "✓ Brand-rename audit passed — no unexpected Calorisor/Sofra tokens."
