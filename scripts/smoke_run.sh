#!/usr/bin/env bash
#SBATCH --job-name=rnaseq_smoke
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1         # Nextflow driver only; pipeline steps run as their own SLURM jobs
#SBATCH --mem=8GB                 # driver memory
#SBATCH --time=08:00:00           # driver must outlast the smoke test
#SBATCH -p batch                  # default Phoenix partition for the driver job
# #SBATCH --account=<account>          # uncomment/set if Phoenix requires an account
set -euo pipefail

ALLOW_FIXES="${ALLOW_FIXES:-false}"
CONFIG="${CONFIG:-configs/configure.yaml}"
REPORT="reports/smoke_test_report.md"
mkdir -p reports logs work

# --- Phoenix HPC environment (adjust module versions if Phoenix changes them) ---
# The smoke test downloads tiny test data, so it needs internet access.
module purge 2>/dev/null || true
module load Nextflow/25.10.2 2>/dev/null || true
module load Apptainer/1.2.5-GCCcore-12.3.0 2>/dev/null || true
export NXF_OPTS='-Xms1g -Xmx4g'
export NXF_APPTAINER_CACHEDIR="${NXF_APPTAINER_CACHEDIR:-$PWD/apptainer_cache}"
mkdir -p "$NXF_APPTAINER_CACHEDIR"

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

# Use the configured profile (e.g. singularity, docker) with the built-in test data.
PROFILE="${PROFILE:-$(get_config profile)}"
PROFILE="${PROFILE:-apptainer}"
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
