#!/usr/bin/env bash
set -euo pipefail

ALLOW_FIXES="${ALLOW_FIXES:-false}"
SAMPLE_MODE="${SAMPLE_MODE:-largest}"
SAMPLE_ID="${SAMPLE_ID:-}"
REPORT="reports/one_sample_validation_report.md"
mkdir -p reports logs work

{
  echo "# One Sample Validation Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "Sample mode: ${SAMPLE_MODE}"
  echo "Automatic fixes allowed: ${ALLOW_FIXES}"
} > "$REPORT"

CONFIG="${CONFIG:-configs/configure.yaml}"
get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}
SAMPLESHEET="$(get_config samplesheet)"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ANNOTATION_TYPE="$(get_config annotation_type)"
ALIGNER="$(get_config aligner)"
PSEUDO_ALIGNER="$(get_config pseudo_aligner)"
SKIP_ALIGNMENT="$(get_config skip_alignment)"
PROFILE="$(get_config profile)"
OUTDIR="$(get_config outdir)"
WORKDIR="$(get_config workdir)"
MEMORY="$(get_config memory)"
CPU="$(get_config cpu)"
WALLTIME="$(get_config walltime)"

ONE_SAMPLE_SHEET="input/one_sample.samplesheet.csv"
head -n 1 "$SAMPLESHEET" > "$ONE_SAMPLE_SHEET"

file_size() {
  local file="$1"
  if stat -c '%s' "$file" >/dev/null 2>&1; then
    stat -c '%s' "$file"
  elif stat -f '%z' "$file" >/dev/null 2>&1; then
    stat -f '%z' "$file"
  else
    echo 0
  fi
}

select_sample_line() {
  case "$SAMPLE_MODE" in
    user)
      if [[ -z "$SAMPLE_ID" ]]; then
        echo "SAMPLE_MODE=user requires SAMPLE_ID." >&2
        return 1
      fi
      awk -F, -v sample="$SAMPLE_ID" 'NR>1 && $1 == sample {print; found=1; exit} END {if (!found) exit 1}' "$SAMPLESHEET"
      ;;
    first)
      tail -n +2 "$SAMPLESHEET" | head -n 1
      ;;
    smallest|largest)
      local sort_flag="-nr"
      [[ "$SAMPLE_MODE" == "smallest" ]] && sort_flag="-n"
      tail -n +2 "$SAMPLESHEET" | while IFS=, read -r sample fastq_1 fastq_2 strandedness rest; do
        [[ -z "$sample" ]] && continue
        size=$(( $(file_size "$fastq_1") + $(file_size "$fastq_2") ))
        printf "%020d,%s,%s,%s,%s\n" "$size" "$sample" "$fastq_1" "$fastq_2" "$strandedness"
      done | sort "$sort_flag" | head -n 1 | cut -d, -f2-
      ;;
    *)
      echo "Unknown SAMPLE_MODE: $SAMPLE_MODE. Use largest, smallest, first, or user." >&2
      return 1
      ;;
  esac
}

selected_line="$(select_sample_line)"
if [[ -z "$selected_line" ]]; then
  echo "No sample selected. Check $SAMPLESHEET and SAMPLE_MODE." | tee -a "$REPORT"
  exit 1
fi
echo "$selected_line" >> "$ONE_SAMPLE_SHEET"
echo "Selected sample: $(printf '%s\n' "$selected_line" | cut -d, -f1)" >> "$REPORT"

if [[ -z "$ANNOTATION_TYPE" || "$ANNOTATION_TYPE" == "auto" ]]; then
  shopt -s nocasematch
  case "$ANNOTATION" in
    *.gff|*.gff3|*.gff.gz|*.gff3.gz) ANNOTATION_TYPE="gff" ;;
    *) ANNOTATION_TYPE="gtf" ;;
  esac
  shopt -u nocasematch
fi

add_resource_limits() {
  if [[ -n "$MEMORY" && "$MEMORY" != "auto" && "$MEMORY" != "unknown" ]]; then
    cmd+=(--max_memory "$MEMORY")
  fi
  if [[ -n "$CPU" && "$CPU" != "auto" && "$CPU" != "unknown" ]]; then
    cmd+=(--max_cpus "$CPU")
  fi
  if [[ -n "$WALLTIME" && "$WALLTIME" != "auto" && "$WALLTIME" != "unknown" ]]; then
    cmd+=(--max_time "$WALLTIME")
  fi
}

set_config_value() {
  local key="$1"
  local value="$2"
  awk -v key="$key" -v value="$value" '
    BEGIN {done=0}
    $1 == key ":" {$0 = key ": " value; done=1}
    {print}
    END {if (!done) print key ": " value}
  ' "$CONFIG" > "${CONFIG}.tmp"
  mv "${CONFIG}.tmp" "$CONFIG"
}

bump_memory() {
  local number="${MEMORY%G}"
  if [[ "$number" =~ ^[0-9]+$ ]]; then
    number=$((number * 2))
  else
    number=128
  fi
  MEMORY="${number}G"
  set_config_value memory "\"$MEMORY\""
  echo "Safe fix: increased max memory to $MEMORY." >> "$REPORT"
}

bump_walltime() {
  WALLTIME="48.h"
  set_config_value walltime "\"$WALLTIME\""
  echo "Safe fix: increased max walltime to $WALLTIME." >> "$REPORT"
}

move_workdir_to_retry_area() {
  WORKDIR="${WORKDIR%/}_retry"
  mkdir -p "$WORKDIR"
  set_config_value workdir "\"$WORKDIR\""
  echo "Safe fix: moved validation work directory to $WORKDIR." >> "$REPORT"
}

prepare_runtime_dirs() {
  export NXF_SINGULARITY_CACHEDIR="${NXF_SINGULARITY_CACHEDIR:-$PWD/work/container_cache}"
  export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$NXF_SINGULARITY_CACHEDIR}"
  export TMPDIR="${TMPDIR:-$PWD/work/tmp}"
  mkdir -p "$NXF_SINGULARITY_CACHEDIR" "$APPTAINER_CACHEDIR" "$TMPDIR" "$WORKDIR" logs reports
  echo "Safe fix: prepared cache, temporary, and work directories." >> "$REPORT"
}

run_one_sample() {
  local run_workdir="${WORKDIR%/}/one_sample_validation"
  cmd=(nextflow run nf-core/rnaseq
    -profile "$PROFILE"
    --input "$ONE_SAMPLE_SHEET"
    --outdir "${OUTDIR%/}/one_sample_validation"
    --fasta "$REFERENCE"
    -work-dir "$run_workdir")

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
  add_resource_limits
  "${cmd[@]}" -resume 2>&1 | tee logs/one_sample_run.log
}

if ! run_one_sample; then
  if [[ "$ALLOW_FIXES" == "true" ]]; then
    echo "Initial one sample run failed. Applying safe infrastructure/resource fixes and resuming." >> "$REPORT"
    prepare_runtime_dirs
    if grep -Eiq 'out.of.memory|oom|killed|cannot allocate|memory|exit status 137|exit status 143' logs/one_sample_run.log; then
      bump_memory
    fi
    if grep -Eiq 'time limit|walltime|wall time|exceeded.*time|exit status 140' logs/one_sample_run.log; then
      bump_walltime
    fi
    if grep -Eiq 'no space left|quota|disk|scratch|tmpdir|permission denied|read-only' logs/one_sample_run.log; then
      move_workdir_to_retry_area
    fi
    run_one_sample || {
      echo "One sample validation failed after safe fixes. Review logs/one_sample_run.log" | tee -a "$REPORT"
      exit 1
    }
  else
    echo "One sample validation failed. Review logs/one_sample_run.log" | tee -a "$REPORT"
    exit 1
  fi
fi

echo "One sample validation passed." >> "$REPORT"
