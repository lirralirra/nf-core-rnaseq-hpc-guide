#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
mkdir -p configs logs

if [[ ! -f "$CONFIG" ]]; then
  cp templates/configure.yaml "$CONFIG" 2>/dev/null || cat > "$CONFIG" <<'YAML'
local_project_dir: /local/path/to/project
hpc_user: your_user
hpc_host: hpc.example.edu
hpc_project_dir: /hpc/path/to/project
fastq_dir: input/fastq
samplesheet: input/samplesheet.csv
reference: input/reference/genome.fa
annotation: input/annotation/annotation.gtf
aligner: star_salmon
profile: singularity
memory: 32.GB
cpu: 8
walltime: 24.h
workdir: work
outdir: results
cache_dir: /scratch/$USER/happy_rnaseq_project/cache
YAML
fi

echo "Edit $CONFIG"
echo "Required choice: aligner = star_salmon or salmon"
