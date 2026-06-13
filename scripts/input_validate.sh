#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
REPORT="reports/input_validation_report.md"
mkdir -p reports logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key {print $2; exit}' "$CONFIG" | sed 's/^["'\\'']//; s/["'\\'']$//'
}

SAMPLESHEET="${SAMPLESHEET:-$(get_config samplesheet)}"
REFERENCE="${REFERENCE:-$(get_config reference)}"
ANNOTATION="${ANNOTATION:-$(get_config annotation)}"
FASTQ_DIR="${FASTQ_DIR:-$(get_config fastq_dir)}"

SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
REFERENCE="${REFERENCE:-input/reference/genome.fa}"
ANNOTATION="${ANNOTATION:-input/annotation/genes.gtf}"
FASTQ_DIR="${FASTQ_DIR:-input/fastq}"
errors=0

check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "- OK: $path"
  else
    echo "- MISSING: $path"
    errors=$((errors + 1))
  fi
}

{
  echo "# Input Validation Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Required paths"
  [[ -f "$CONFIG" ]] && echo "- OK: $CONFIG" || echo "- INFO: $CONFIG not found yet; Step 2 uses default input paths before Step 3 configuration."
  check_path "$SAMPLESHEET"
  check_path "$REFERENCE"
  check_path "$ANNOTATION"
  check_path "$FASTQ_DIR"
  echo
  echo "## Samplesheet checks"
  if [[ -f "$SAMPLESHEET" ]]; then
    if head -n 1 "$SAMPLESHEET" | grep -q 'sample,fastq_1,fastq_2,strandedness'; then
      echo "- OK: header"
    else
      echo "- ERROR: unexpected header"
      errors=$((errors + 1))
    fi
    duplicates="$(awk -F, 'NR>1 {print $1}' "$SAMPLESHEET" | sort | uniq -d || true)"
    if [[ -n "$duplicates" ]]; then
      printf '%s\n' "$duplicates" | sed 's/^/- DUPLICATE SAMPLE: /'
      errors=$((errors + 1))
    fi
    while read -r fq; do
      [[ -z "$fq" ]] && continue
      if [[ -f "$fq" ]]; then
        echo "- OK FASTQ: $fq"
      else
        echo "- MISSING FASTQ: $fq"
        errors=$((errors + 1))
      fi
    done < <(awk -F, 'NR>1 {print $2"\n"$3}' "$SAMPLESHEET")
  fi
  echo
  echo "## Upload size estimate"
  du -sh input configs scripts reports README.md 2>/dev/null || true
  echo
  if [[ "$errors" -eq 0 ]]; then
    echo "## Result"
    echo "PASS"
  else
    echo "## Result"
    echo "FAIL: $errors blocking issue(s). Fix these before upload."
  fi
} > "$REPORT"

echo "Wrote $REPORT"
if [[ "$errors" -ne 0 ]]; then
  exit 1
fi
