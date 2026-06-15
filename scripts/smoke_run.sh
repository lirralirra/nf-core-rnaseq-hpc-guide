#!/usr/bin/env bash
set -euo pipefail

ALLOW_FIXES="${ALLOW_FIXES:-false}"
CONFIG="${CONFIG:-configs/configure.yaml}"
REPORT="reports/smoke_test_report.md"
mkdir -p reports logs work

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

# Use the configured profile (e.g. singularity, docker) with the built-in test data.
PROFILE="${PROFILE:-$(get_config profile)}"
PROFILE="${PROFILE:-singularity}"
PIPELINE_VERSION="${PIPELINE_VERSION:-$(get_config pipeline_version)}"
PIPELINE_VERSION="${PIPELINE_VERSION:-3.26.0}"

if ! command -v nextflow >/dev/null 2>&1; then
  echo "ERROR: nextflow not found in PATH. Load/install Nextflow first (e.g. 'module load Nextflow')." >&2
  exit 1
fi
echo "Using nf-core/rnaseq version: $PIPELINE_VERSION"

{
  echo "# Smoke Test Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Purpose"
  echo "Validate nf-core / Nextflow / HPC environment using tiny built-in test data."
  echo
  echo "## Profile"
  echo "test,${PROFILE}"
  echo
  echo "## Automatic fixes allowed"
  echo "${ALLOW_FIXES}"
} > "$REPORT"

if [[ "$ALLOW_FIXES" == "true" ]]; then
  export NXF_SINGULARITY_CACHEDIR="${NXF_SINGULARITY_CACHEDIR:-$PWD/work/container_cache}"
  export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$NXF_SINGULARITY_CACHEDIR}"
  export TMPDIR="${TMPDIR:-$PWD/work/tmp}"
  mkdir -p "$NXF_SINGULARITY_CACHEDIR" "$APPTAINER_CACHEDIR" "$TMPDIR"
fi

run_smoke_test() {
  nextflow run nf-core/rnaseq \
    -r "${PIPELINE_VERSION}" \
    -profile "test,${PROFILE}" \
    -resume 2>&1 | tee logs/smoke_run.log
}

if ! run_smoke_test; then
  if [[ "$ALLOW_FIXES" == "true" ]]; then
    {
      echo
      echo "Initial smoke test failed."
      echo "Applied safe infrastructure fixes: cache directories, Apptainer cache, TMPDIR, and resume retry."
    } >> "$REPORT"
    export NXF_SINGULARITY_CACHEDIR="${NXF_SINGULARITY_CACHEDIR:-$PWD/work/container_cache}"
    export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$NXF_SINGULARITY_CACHEDIR}"
    export TMPDIR="${TMPDIR:-$PWD/work/tmp}"
    mkdir -p "$NXF_SINGULARITY_CACHEDIR" "$APPTAINER_CACHEDIR" "$TMPDIR" work logs reports
    run_smoke_test || {
      echo "Smoke test failed after safe fixes. Review logs/smoke_run.log" | tee -a "$REPORT"
      exit 1
    }
  else
    echo "Smoke test failed. Review logs/smoke_run.log" | tee -a "$REPORT"
    exit 1
  fi
fi

echo "Smoke test passed." >> "$REPORT"
