#!/usr/bin/env bash
# Compare qpdf vs pdfcpu optimize on local PDFs (nothing is committed).
# Usage:
#   ./tools/benchmark_pdf_optimizers.sh /path/to/pdfs
# Requires: qpdf and pdfcpu on PATH (e.g. brew install qpdf pdfcpu).

set -euo pipefail

DIR="${1:-}"
if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  echo "Usage: $0 /path/to/folder/of/pdfs"
  exit 1
fi

command -v qpdf >/dev/null || { echo "qpdf not found on PATH"; exit 1; }
command -v pdfcpu >/dev/null || { echo "pdfcpu not found on PATH"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "folder=$DIR"
printf "%-50s %12s %12s %12s %12s %12s\n" "file" "orig_B" "qpdf_B" "qpdf_%" "pdfcpu_B" "pdfcpu_%"

shopt -s nullglob
for f in "$DIR"/*.pdf; do
  base="$(basename "$f")"
  orig=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
  qout="$TMP/qpdf_$base"
  pout="$TMP/pdfcpu_$base"

  qpdf "$f" "$qout" \
    --object-streams=generate \
    --compress-streams=y \
    --recompress-flate \
    --compression-level=9 \
    --optimize-images 2>/dev/null || { echo "qpdf failed: $base"; continue; }
  qsz=$(stat -f%z "$qout" 2>/dev/null || stat -c%s "$qout")
  qpct=$(awk -v o="$orig" -v q="$qsz" 'BEGIN { if (o>0) printf "%.1f", (o-q)/o*100; else print "0" }')

  pdfcpu optimize "$f" "$pout" 2>/dev/null || { echo "pdfcpu failed: $base"; continue; }
  psz=$(stat -f%z "$pout" 2>/dev/null || stat -c%s "$pout")
  ppct=$(awk -v o="$orig" -v p="$psz" 'BEGIN { if (o>0) printf "%.1f", (o-p)/o*100; else print "0" }')

  printf "%-50s %12s %12s %12s %12s %12s\n" "$base" "$orig" "$qsz" "$qpct" "$psz" "$ppct"
done
