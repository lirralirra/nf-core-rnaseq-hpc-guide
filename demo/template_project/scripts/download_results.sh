#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
LOCAL_DEST="${LOCAL_DEST:-./downloaded_results}"
INCLUDE_BAM="${INCLUDE_BAM:-false}"
LOG="logs/download_results.log"
mkdir -p logs "$LOCAL_DEST"

get_config() {
  awk -F': *' -v key="$1" '$1 == key {print $2; exit}' "$CONFIG" | sed 's/^["'\\'']//; s/["'\\'']$//'
}

HPC_USER="$(get_config hpc_user)"
HPC_HOST="$(get_config hpc_host)"
HPC_PROJECT_DIR="$(get_config hpc_project_dir)"
HPC_SOURCE="${HPC_USER}@${HPC_HOST}:${HPC_PROJECT_DIR%/}"

EXCLUDES=(--exclude 'work/' --exclude '.nextflow*')
if [[ "$INCLUDE_BAM" != "true" ]]; then
  EXCLUDES+=(--exclude '*.bam' --exclude '*.cram')
fi

rsync -avh --partial --progress \
  "${EXCLUDES[@]}" \
  "${HPC_SOURCE%/}/results" \
  "${HPC_SOURCE%/}/reports" \
  "${HPC_SOURCE%/}/logs" \
  "$LOCAL_DEST/" 2>&1 | tee "$LOG"

echo "Download log: $LOG"
