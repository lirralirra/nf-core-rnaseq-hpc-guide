#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
mkdir -p logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

PROFILE="$(get_config profile)"
PIPELINE_VERSION="$(get_config pipeline_version)"; PIPELINE_VERSION="${PIPELINE_VERSION:-3.26.0}"
SAMPLESHEET="$(get_config samplesheet)"
OUTDIR="$(get_config outdir)"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ANNOTATION_TYPE="$(get_config annotation_type)"
ALIGNER="$(get_config aligner)"
PSEUDO_ALIGNER="$(get_config pseudo_aligner)"
SKIP_ALIGNMENT="$(get_config skip_alignment)"
GC_BIAS="$(get_config gc_bias)"; GC_BIAS="${GC_BIAS:-true}"
WORKDIR="$(get_config workdir)"
MEMORY="$(get_config memory)"
CPU="$(get_config cpu)"
WALLTIME="$(get_config walltime)"

# Write resource limits as a Nextflow config. nf-core/rnaseq removed the
# --max_cpus/--max_memory/--max_time params (template v3+), so we set
# process.resourceLimits instead (Nextflow 24.04+; ignored on older versions).
write_resource_config() {
  local res=() mem_gb conf="configs/resource_limits.config"
  mem_gb="$(printf '%s' "$MEMORY" | grep -oE '^[0-9]+(\.[0-9]+)?' || true)"
  [[ -n "$CPU" && "$CPU" != "auto" && "$CPU" != "unknown" ]] && res+=("cpus: ${CPU}")
  [[ -n "$mem_gb" ]] && res+=("memory: ${mem_gb}.GB")
  [[ -n "$WALLTIME" && "$WALLTIME" != "auto" && "$WALLTIME" != "unknown" ]] && res+=("time: ${WALLTIME}")
  if [[ ${#res[@]} -gt 0 ]]; then
    mkdir -p configs
    printf 'process {\n  resourceLimits = [ %s ]\n}\n' "$(IFS=,; echo "${res[*]}")" > "$conf"
    printf '%s' "$conf"
  fi
}

if [[ -z "$ANNOTATION_TYPE" || "$ANNOTATION_TYPE" == "auto" ]]; then
  shopt -s nocasematch
  case "$ANNOTATION" in
    *.gff|*.gff3|*.gff.gz|*.gff3.gz) ANNOTATION_TYPE="gff" ;;
    *) ANNOTATION_TYPE="gtf" ;;
  esac
  shopt -u nocasematch
fi

if ! command -v nextflow >/dev/null 2>&1; then
  echo "ERROR: nextflow not found in PATH. Load/install Nextflow first (e.g. 'module load Nextflow')." >&2
  exit 1
fi
echo "Using nf-core/rnaseq version: $PIPELINE_VERSION"

cmd=(nextflow run nf-core/rnaseq
  -r "$PIPELINE_VERSION"
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
# DESeq2 authors recommend Salmon GC bias correction; off by default in the pipeline.
if [[ "$GC_BIAS" == "true" ]]; then
  cmd+=("--extra_salmon_quant_args=--gcBias")
fi
RES_CONF="$(write_resource_config)"
if [[ -n "$RES_CONF" ]]; then
  cmd+=(-c "$RES_CONF")
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
