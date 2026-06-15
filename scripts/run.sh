#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
mkdir -p logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

PROFILE="$(get_config profile)"
SAMPLESHEET="$(get_config samplesheet)"
OUTDIR="$(get_config outdir)"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ANNOTATION_TYPE="$(get_config annotation_type)"
ALIGNER="$(get_config aligner)"
PSEUDO_ALIGNER="$(get_config pseudo_aligner)"
SKIP_ALIGNMENT="$(get_config skip_alignment)"
WORKDIR="$(get_config workdir)"
MEMORY="$(get_config memory)"
CPU="$(get_config cpu)"
WALLTIME="$(get_config walltime)"

if [[ -z "$ANNOTATION_TYPE" || "$ANNOTATION_TYPE" == "auto" ]]; then
  shopt -s nocasematch
  case "$ANNOTATION" in
    *.gff|*.gff3|*.gff.gz|*.gff3.gz) ANNOTATION_TYPE="gff" ;;
    *) ANNOTATION_TYPE="gtf" ;;
  esac
  shopt -u nocasematch
fi

cmd=(nextflow run nf-core/rnaseq
  -profile "$PROFILE"
  --input "$SAMPLESHEET"
  --outdir "$OUTDIR"
  --fasta "$REFERENCE"
  -work-dir "$WORKDIR")

if [[ "$ANNOTATION_TYPE" == "gff" ]]; then
  cmd+=(--gff "$ANNOTATION")
else
  cmd+=(--gtf "$ANNOTATION")
fi

if [[ -n "$ALIGNER" && "$SKIP_ALIGNMENT" != "true" ]]; then
  cmd+=(--aligner "$ALIGNER")
fi
if [[ -n "$PSEUDO_ALIGNER" ]]; then
  cmd+=(--pseudo_aligner "$PSEUDO_ALIGNER")
fi
if [[ "$SKIP_ALIGNMENT" == "true" ]]; then
  cmd+=(--skip_alignment)
fi
if [[ -n "$MEMORY" && "$MEMORY" != "auto" && "$MEMORY" != "unknown" ]]; then
  cmd+=(--max_memory "$MEMORY")
fi
if [[ -n "$CPU" && "$CPU" != "auto" && "$CPU" != "unknown" ]]; then
  cmd+=(--max_cpus "$CPU")
fi
if [[ -n "$WALLTIME" && "$WALLTIME" != "auto" && "$WALLTIME" != "unknown" ]]; then
  cmd+=(--max_time "$WALLTIME")
fi

extra_args=("$@")
has_resume=false
for arg in "${extra_args[@]}"; do
  [[ "$arg" == "-resume" ]] && has_resume=true
done
if [[ "$has_resume" == "false" ]]; then
  extra_args=(-resume "${extra_args[@]}")
fi

"${cmd[@]}" "${extra_args[@]}" 2>&1 | tee logs/full_run.log
