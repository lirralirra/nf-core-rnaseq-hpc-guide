#!/usr/bin/env bash
set -euo pipefail

ALLOW_FIXES="${ALLOW_FIXES:-false}"
REPORT="reports/smoke_test_report.md"
mkdir -p reports logs work

{
  echo "# Smoke Test Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Purpose"
  echo "Validate nf-core / Nextflow / HPC environment using tiny built-in test data."
  echo
  echo "## Automatic fixes allowed"
  echo "${ALLOW_FIXES}"
} > "$REPORT"

if [[ "$ALLOW_FIXES" == "true" ]]; then
  mkdir -p "${NXF_SINGULARITY_CACHEDIR:-$PWD/work/container_cache}" "${TMPDIR:-$PWD/work/tmp}"
fi

nextflow run nf-core/rnaseq \
  -profile test,singularity \
  -resume 2>&1 | tee logs/smoke_run.log || {
    echo "Smoke test failed. Review logs/smoke_run.log" | tee -a "$REPORT"
    exit 1
  }

echo "Smoke test passed." >> "$REPORT"
