#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
LOG="logs/upload_to_hpc.log"
mkdir -p logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

HPC_USER="$(get_config hpc_user)"
HPC_HOST="$(get_config hpc_host)"
HPC_PROJECT_DIR="$(get_config hpc_project_dir)"
HPC_TARGET="${HPC_USER}@${HPC_HOST}:${HPC_PROJECT_DIR%/}/"

rsync -avh --partial --progress \
  --exclude '.git/' \
  --exclude '.DS_Store' \
  --exclude '._*' \
  --exclude '.nextflow*' \
  --exclude '.nf-core/' \
  --exclude 'work/' \
  --exclude 'results/' \
  --exclude 'tmp/' \
  ./ "$HPC_TARGET" 2>&1 | tee "$LOG"

echo "Upload log: $LOG"
