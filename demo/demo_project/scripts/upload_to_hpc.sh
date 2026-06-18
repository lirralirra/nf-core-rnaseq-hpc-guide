#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
LOG="logs/upload_to_hpc.log"
mkdir -p logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

HPC_USER="${HPC_USER:-$(get_config hpc_user)}"
HPC_HOST="${HPC_HOST:-$(get_config hpc_host)}"
HPC_PROJECT_DIR="${HPC_PROJECT_DIR:-$(get_config hpc_project_dir)}"
HPC_TARGET="${HPC_USER}@${HPC_HOST}:${HPC_PROJECT_DIR%/}/"

if [[ -z "$HPC_USER" || "$HPC_USER" == "your_username" || "$HPC_USER" == "your_user" ||
  -z "$HPC_HOST" || "$HPC_HOST" == "your.cluster.edu" || "$HPC_HOST" == "hpc.example.edu" ||
  -z "$HPC_PROJECT_DIR" || "$HPC_PROJECT_DIR" == /path/on/hpc/* || "$HPC_PROJECT_DIR" == /hpc/path/to/project ]]; then
  echo "ERROR: Phoenix upload target is not configured." >&2
  echo "Set HPC_USER, HPC_HOST, and HPC_PROJECT_DIR, or run Step 3 configure with the correct values." >&2
  exit 2
fi

ssh "${HPC_USER}@${HPC_HOST}" mkdir -p -- "${HPC_PROJECT_DIR%/}"

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
