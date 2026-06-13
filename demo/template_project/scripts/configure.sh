#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
ALIGNER="${ALIGNER:-star_salmon}"
SPECIES="${SPECIES:-unknown}"
GENOME_SIZE_GB="${GENOME_SIZE_GB:-}"
SAMPLE_COUNT="${SAMPLE_COUNT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --star-salmon)
      ALIGNER="star_salmon"
      shift
      ;;
    --salmon)
      ALIGNER="salmon"
      shift
      ;;
    *)
      echo "Usage: bash scripts/configure.sh [--star-salmon|--salmon]" >&2
      exit 2
      ;;
  esac
done

LOCAL_PROJECT_DIR="${LOCAL_PROJECT_DIR:-$(pwd)}"
HPC_USER="${HPC_USER:-your_username}"
HPC_HOST="${HPC_HOST:-your.cluster.edu}"
HPC_PROJECT_DIR="${HPC_PROJECT_DIR:-/path/on/hpc/happy_rnaseq_project}"
FASTQ_DIR="${FASTQ_DIR:-input/fastq}"
SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
REFERENCE="${REFERENCE:-input/reference/genome.fa}"
ANNOTATION="${ANNOTATION:-input/annotation/genes.gtf}"
PROFILE="${PROFILE:-singularity}"
WORKDIR="${WORKDIR:-work}"
OUTDIR="${OUTDIR:-results}"
CACHE_DIR="${CACHE_DIR:-/scratch/${HPC_USER}/apptainer_cache}"

metadata_value() {
  local key="$1"
  local file="${PROJECT_METADATA:-configs/project_metadata.tsv}"
  [[ -f "$file" ]] || return 0
  awk -F'\t' -v key="$key" '$1 == key {print $2; exit}' "$file"
}

infer_species() {
  local value
  value="$(metadata_value species)"
  if [[ -n "$value" ]]; then
    echo "$value"
    return
  fi
  basename "$(pwd)" | sed 's/[_-]/ /g'
}

infer_sample_count() {
  local value
  value="$(metadata_value sample_count)"
  if [[ -n "$value" ]]; then
    echo "$value"
    return
  fi
  if [[ -f "$SAMPLESHEET" ]]; then
    awk 'END {print (NR > 0 ? NR - 1 : 0)}' "$SAMPLESHEET"
    return
  fi
  if [[ -d "$FASTQ_DIR" ]]; then
    find "$FASTQ_DIR" -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' -o -name '*.fastq' -o -name '*.fq' \) 2>/dev/null | sed -E 's/(_R?[12]|_1|_2)\.(fastq|fq)(\.gz)?$//' | sort -u | wc -l | tr -d ' '
  else
    echo 0
  fi
}

infer_genome_size_gb() {
  local value
  value="$(metadata_value genome_size_gb)"
  if [[ -n "$value" ]]; then
    echo "$value"
    return
  fi
  if [[ -f "$REFERENCE" ]]; then
    awk 'BEGIN {n=0} /^>/ {next} {gsub(/[[:space:]]/, ""); n += length($0)} END {printf "%.2f", n/1000000000}' "$REFERENCE"
    return
  fi
  echo 0
}

if [[ "$SPECIES" == "unknown" ]]; then
  SPECIES="$(infer_species)"
fi
if [[ -z "$GENOME_SIZE_GB" ]]; then
  GENOME_SIZE_GB="$(infer_genome_size_gb)"
fi
if [[ -z "$SAMPLE_COUNT" ]]; then
  SAMPLE_COUNT="$(infer_sample_count)"
fi

estimate_memory() {
  local aligner="$1"
  local genome_size="${2:-0}"
  awk -v aligner="$aligner" -v genome="$genome_size" 'BEGIN {
    if (aligner == "salmon") {
      mem = 32
    } else if (genome <= 2) {
      mem = 48
    } else if (genome <= 8) {
      mem = 64
    } else if (genome <= 16) {
      mem = 96
    } else {
      mem = 128
    }
    printf "%dG", mem
  }'
}

estimate_cpu() {
  local aligner="$1"
  local samples="${2:-0}"
  if [[ "$aligner" == "salmon" ]]; then
    if [[ "$samples" =~ ^[0-9]+$ && "$samples" -ge 48 ]]; then
      echo 12
    else
      echo 8
    fi
  else
    if [[ "$samples" =~ ^[0-9]+$ && "$samples" -ge 48 ]]; then
      echo 24
    else
      echo 16
    fi
  fi
}

estimate_walltime() {
  local aligner="$1"
  local samples="${2:-0}"
  if [[ "$aligner" == "salmon" ]]; then
    if [[ "$samples" =~ ^[0-9]+$ && "$samples" -ge 48 ]]; then
      echo "24:00:00"
    else
      echo "12:00:00"
    fi
  else
    if [[ "$samples" =~ ^[0-9]+$ && "$samples" -ge 48 ]]; then
      echo "48:00:00"
    else
      echo "24:00:00"
    fi
  fi
}

MEMORY="${MEMORY:-$(estimate_memory "$ALIGNER" "${GENOME_SIZE_GB:-0}")}"
CPU="${CPU:-$(estimate_cpu "$ALIGNER" "${SAMPLE_COUNT:-0}")}"
WALLTIME="${WALLTIME:-$(estimate_walltime "$ALIGNER" "${SAMPLE_COUNT:-0}")}"

mkdir -p configs logs

cat > "$CONFIG" <<YAML
local_project_dir: ${LOCAL_PROJECT_DIR}
hpc_user: ${HPC_USER}
hpc_host: ${HPC_HOST}
hpc_project_dir: ${HPC_PROJECT_DIR}
fastq_dir: ${FASTQ_DIR}
samplesheet: ${SAMPLESHEET}
reference: ${REFERENCE}
annotation: ${ANNOTATION}
species: ${SPECIES}
genome_size_gb: ${GENOME_SIZE_GB:-unknown}
sample_count: ${SAMPLE_COUNT:-unknown}
aligner: ${ALIGNER}
profile: ${PROFILE}
memory: ${MEMORY}
cpu: ${CPU}
walltime: ${WALLTIME}
workdir: ${WORKDIR}
outdir: ${OUTDIR}
cache_dir: ${CACHE_DIR}
YAML

echo "Wrote $CONFIG"
echo "Aligner: $ALIGNER"
echo "Estimated resources: memory=$MEMORY cpu=$CPU walltime=$WALLTIME"
echo "HPC target: ${HPC_USER}@${HPC_HOST}:${HPC_PROJECT_DIR}"
