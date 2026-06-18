#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
LOCAL_DEST="${LOCAL_DEST:-./downloaded_results}"
INCLUDE_BAM="${INCLUDE_BAM:-false}"
LOG="logs/download_results.log"
ANALYSIS_DIR="$LOCAL_DEST/analysis_data"
QC_DIR="$LOCAL_DEST/qc_report"
RUN_METADATA_DIR="$LOCAL_DEST/run_metadata"
REPRO_DIR="$LOCAL_DEST/reproducibility_docs"
mkdir -p logs "$ANALYSIS_DIR" "$QC_DIR" "$RUN_METADATA_DIR" "$REPRO_DIR"

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

HPC_USER="${HPC_USER:-$(get_config hpc_user)}"
HPC_HOST="${HPC_HOST:-$(get_config hpc_host)}"
HPC_PROJECT_DIR="${HPC_PROJECT_DIR:-$(get_config hpc_project_dir)}"
HPC_SOURCE="${HPC_USER}@${HPC_HOST}:${HPC_PROJECT_DIR%/}"

if [[ -z "$HPC_USER" || "$HPC_USER" == "your_username" || "$HPC_USER" == "your_user" ||
  -z "$HPC_HOST" || "$HPC_HOST" == "your.cluster.edu" || "$HPC_HOST" == "hpc.example.edu" ||
  -z "$HPC_PROJECT_DIR" || "$HPC_PROJECT_DIR" == /path/on/hpc/* || "$HPC_PROJECT_DIR" == /hpc/path/to/project ]]; then
  echo "ERROR: Phoenix download source is not configured." >&2
  echo "Set HPC_USER, HPC_HOST, and HPC_PROJECT_DIR, or run Step 3 configure with the correct values." >&2
  exit 2
fi

EXCLUDES=(--exclude 'work/' --exclude '.nextflow/')
if [[ "$INCLUDE_BAM" != "true" ]]; then
  EXCLUDES+=(--exclude '*.bam' --exclude '*.cram')
fi

rsync_from_hpc() {
  local dest="$1"
  shift
  mkdir -p "$dest"
  rsync -avh --partial --progress --ignore-missing-args \
    "${EXCLUDES[@]}" \
    "$@" \
    "$dest/" 2>&1 | tee -a "$LOG"
}

: > "$LOG"

# Analysis data: Salmon transcript quantification and nf-core merged summaries
# when the pipeline produced them. Derived gene summaries still need tx2gene
# verification before downstream DESeq2/edgeR use.
rsync_from_hpc "$ANALYSIS_DIR" \
  "${HPC_SOURCE%/}/results/star_salmon" \
  "${HPC_SOURCE%/}/results/salmon" \
  "${HPC_SOURCE%/}/results/rsem" \
  "${HPC_SOURCE%/}/results/kallisto" \
  "${HPC_SOURCE%/}/results/featurecounts" \
  "${HPC_SOURCE%/}/results/stringtie"

# QC report: MultiQC, read QC, and project validation reports.
rsync_from_hpc "$QC_DIR" \
  "${HPC_SOURCE%/}/results/multiqc" \
  "${HPC_SOURCE%/}/results/fastqc" \
  "${HPC_SOURCE%/}/results/trim_galore" \
  "${HPC_SOURCE%/}/results/fastp" \
  "${HPC_SOURCE%/}/reports"

# Run metadata: Nextflow/nf-core execution provenance and runtime logs.
rsync_from_hpc "$RUN_METADATA_DIR" \
  "${HPC_SOURCE%/}/results/pipeline_info" \
  "${HPC_SOURCE%/}/logs" \
  "${HPC_SOURCE%/}/.nextflow.log"

# Reproducibility docs: inputs and project files needed to understand/rerun.
rsync_from_hpc "$REPRO_DIR" \
  "${HPC_SOURCE%/}/configs" \
  "${HPC_SOURCE%/}/scripts" \
  "${HPC_SOURCE%/}/README.md" \
  "${HPC_SOURCE%/}/PROJECT_INFO.md" \
  "${HPC_SOURCE%/}/nextflow.config" \
  "${HPC_SOURCE%/}/reference_metadata.txt" \
  "${HPC_SOURCE%/}/input/samplesheet.csv"

echo "Downloaded into: $LOCAL_DEST"
echo "Files received:"
for category in "$ANALYSIS_DIR" "$QC_DIR" "$RUN_METADATA_DIR" "$REPRO_DIR"; do
  count="$(find "$category" -type f | wc -l | tr -d ' ')"
  echo "  $(basename "$category"): $count files"
done
find "$LOCAL_DEST" -type f | wc -l | sed 's/^/  total files: /'
echo "Download log: $LOG"
