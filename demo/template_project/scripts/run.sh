#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
mkdir -p logs

get_config() {
  awk -F': *' -v key="$1" '$1 == key {print $2; exit}' "$CONFIG" | sed 's/^["'\\'']//; s/["'\\'']$//'
}

PROFILE="$(get_config profile)"
SAMPLESHEET="$(get_config samplesheet)"
OUTDIR="$(get_config outdir)"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ALIGNER="$(get_config aligner)"
WORKDIR="$(get_config workdir)"

nextflow run nf-core/rnaseq \
  -profile "$PROFILE" \
  --input "$SAMPLESHEET" \
  --outdir "$OUTDIR" \
  --fasta "$REFERENCE" \
  --gtf "$ANNOTATION" \
  --aligner "$ALIGNER" \
  -work-dir "$WORKDIR" \
  -resume "$@" 2>&1 | tee logs/full_run.log
