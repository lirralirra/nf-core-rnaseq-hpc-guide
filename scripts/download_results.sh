#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
LOCAL_DEST="${LOCAL_DEST:-./downloaded_results}"
INCLUDE_BAM="${INCLUDE_BAM:-false}"
LOG="logs/download_results.log"
mkdir -p logs "$LOCAL_DEST"

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

EXCLUDES=(--exclude 'work/' --exclude '.nextflow*')
if [[ "$INCLUDE_BAM" != "true" ]]; then
  EXCLUDES+=(--exclude '*.bam' --exclude '*.cram')
fi

# Bring back analysis outputs plus the reproducibility files shown on the page.
# --ignore-missing-args skips any source that does not exist on HPC.
rsync -avh --partial --progress --ignore-missing-args \
  "${EXCLUDES[@]}" \
  "${HPC_SOURCE%/}/results" \
  "${HPC_SOURCE%/}/reports" \
  "${HPC_SOURCE%/}/logs" \
  "${HPC_SOURCE%/}/configs" \
  "${HPC_SOURCE%/}/scripts" \
  "${HPC_SOURCE%/}/README.md" \
  "${HPC_SOURCE%/}/reference_metadata.txt" \
  "${HPC_SOURCE%/}/input/samplesheet.csv" \
  "$LOCAL_DEST/" 2>&1 | tee "$LOG"

echo "Downloaded into: $LOCAL_DEST"
echo "Files received:"
find "$LOCAL_DEST" -type f | wc -l | sed 's/^/  total files: /'
echo "Download log: $LOG"
