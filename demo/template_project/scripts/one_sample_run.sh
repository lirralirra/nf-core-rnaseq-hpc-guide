#!/usr/bin/env bash
set -euo pipefail

ALLOW_FIXES="${ALLOW_FIXES:-false}"
SAMPLE_MODE="${SAMPLE_MODE:-smallest}"
REPORT="reports/one_sample_validation_report.md"
mkdir -p reports logs work

{
  echo "# One Sample Validation Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "Sample mode: ${SAMPLE_MODE}"
  echo "Automatic fixes allowed: ${ALLOW_FIXES}"
} > "$REPORT"

CONFIG="${CONFIG:-configs/configure.yaml}"
get_config() {
  awk -F': *' -v key="$1" '$1 == key {print $2; exit}' "$CONFIG" | sed 's/^["'\\'']//; s/["'\\'']$//'
}
SAMPLESHEET="$(get_config samplesheet)"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ALIGNER="$(get_config aligner)"
PROFILE="$(get_config profile)"

ONE_SAMPLE_SHEET="input/one_sample.samplesheet.csv"
head -n 1 "$SAMPLESHEET" > "$ONE_SAMPLE_SHEET"
tail -n +2 "$SAMPLESHEET" | head -n 1 >> "$ONE_SAMPLE_SHEET"

nextflow run nf-core/rnaseq \
  -profile "$PROFILE" \
  --input "$ONE_SAMPLE_SHEET" \
  --fasta "$REFERENCE" \
  --gtf "$ANNOTATION" \
  --aligner "$ALIGNER" \
  -resume 2>&1 | tee logs/one_sample_run.log || {
    echo "One sample validation failed. Review logs/one_sample_run.log" | tee -a "$REPORT"
    exit 1
  }

echo "One sample validation passed." >> "$REPORT"
