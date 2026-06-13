#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
REPORT="reports/input_validation_report.md"
mkdir -p reports logs

get_config() {
  awk -F': *' -v key="$1" '$1 == key {print $2; exit}' "$CONFIG" | sed 's/^["'\\'']//; s/["'\\'']$//'
}

SAMPLESHEET="$(get_config samplesheet)"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
FASTQ_DIR="$(get_config fastq_dir)"

{
  echo "# Input Validation Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Required paths"
  for path in "$CONFIG" "$SAMPLESHEET" "$REFERENCE" "$ANNOTATION" "$FASTQ_DIR"; do
    [[ -e "$path" ]] && echo "- OK: $path" || echo "- MISSING: $path"
  done
  echo
  echo "## Samplesheet checks"
  if [[ -f "$SAMPLESHEET" ]]; then
    head -n 1 "$SAMPLESHEET" | grep -q 'sample,fastq_1,fastq_2,strandedness' && echo "- OK: header" || echo "- CHECK: unexpected header"
    awk -F, 'NR>1 {print $1}' "$SAMPLESHEET" | sort | uniq -d | sed 's/^/- DUPLICATE SAMPLE: /' || true
    awk -F, 'NR>1 {print $2"\n"$3}' "$SAMPLESHEET" | while read -r fq; do
      [[ -z "$fq" ]] && continue
      [[ -f "$fq" ]] && echo "- OK FASTQ: $fq" || echo "- MISSING FASTQ: $fq"
    done
  fi
  echo
  echo "## Upload size estimate"
  du -sh input configs scripts reports README.md 2>/dev/null || true
} > "$REPORT"

echo "Wrote $REPORT"
