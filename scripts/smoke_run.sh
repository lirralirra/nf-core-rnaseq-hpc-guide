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
SAMPLESHEET="$(get_config samplesheet)"; SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ANNOTATION_TYPE="$(get_config annotation_type)"
ALIGNER="$(get_config aligner)"; ALIGNER="${ALIGNER:-star_salmon}"
WORKDIR="$(get_config workdir)"; WORKDIR="${WORKDIR:-work}"
OUTDIR="$(get_config outdir)"; OUTDIR="${OUTDIR:-results}"

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
  echo "Preflight checks + a tiny built-in test run that validates the nf-core / Nextflow / HPC"
  echo "environment, warms the Apptainer container cache, and can auto-fix known issues."
  echo
  echo "## Profile"
  echo "test,${PROFILE}"
  echo
  echo "## Automatic fixes allowed"
  echo "${ALLOW_FIXES}"
} > "$REPORT"

# ---------------------------------------------------------------------------
# Preflight (runs first): environment, cache, disk, inputs, and a Nextflow
# -preview dry run on YOUR real inputs. Quick, submits no heavy jobs, and
# fails fast before the tiny test run below warms the container cache.
# ---------------------------------------------------------------------------
{
  echo
  echo "## Preflight"
  echo '```'
  echo "# modules"; module list 2>&1 || true
  echo "NXF_APPTAINER_CACHEDIR=$NXF_APPTAINER_CACHEDIR"; du -sh "$NXF_APPTAINER_CACHEDIR" 2>/dev/null || true
  echo "# disk"; df -h . 2>/dev/null || true
  du -sh "$WORKDIR" "$OUTDIR" references fastq 2>/dev/null || true
  du -sh references/prebuilt_indexes/* 2>/dev/null || true
  echo '```'
} >> "$REPORT"

if [[ -f "$SAMPLESHEET" && -n "$REFERENCE" ]]; then
  ann_flag="--gtf"
  case "${ANNOTATION_TYPE:-}" in
    gff*) ann_flag="--gff" ;;
    *) [[ "$ANNOTATION" == *.gff || "$ANNOTATION" == *.gff3 || "$ANNOTATION" == *.gff.gz || "$ANNOTATION" == *.gff3.gz ]] && ann_flag="--gff" ;;
  esac
  echo "Preflight: running a Nextflow -preview dry run on your inputs..."
  if nextflow run nf-core/rnaseq -r "$PIPELINE_VERSION" -profile "$PROFILE" -preview \
       --input "$SAMPLESHEET" --outdir "${OUTDIR%/}/preview" \
       --fasta "$REFERENCE" "$ann_flag" "$ANNOTATION" --aligner "$ALIGNER" --igenomes_ignore \
       2>&1 | tee logs/preflight_preview.log; then
    echo "Preflight -preview: OK (workflow builds, inputs validate)" >> "$REPORT"
  else
    echo "Preflight -preview: FAILED — review logs/preflight_preview.log" | tee -a "$REPORT"
    exit 1
  fi
else
  echo "Preflight -preview: skipped (samplesheet/reference not set in $CONFIG)" >> "$REPORT"
fi

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
