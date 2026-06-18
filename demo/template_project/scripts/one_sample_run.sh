#!/usr/bin/env bash
#SBATCH --job-name=rnaseq_one_sample
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1         # Nextflow driver only; pipeline steps run as their own SLURM jobs
#SBATCH --mem=8GB                 # driver memory
#SBATCH --time=24:00:00           # driver must outlast the one-sample run
#SBATCH -p batch                  # default Phoenix partition for the driver job
# #SBATCH --account=<account>          # uncomment/set if Phoenix requires an account
set -euo pipefail

ALLOW_FIXES="${ALLOW_FIXES:-false}"
SAMPLE_MODE="${SAMPLE_MODE:-largest}"
SAMPLE_ID="${SAMPLE_ID:-}"
REPORT="reports/one_sample_validation_report.md"
RUN_ID="${SLURM_JOB_ID:-manual_$(date +%Y%m%d_%H%M%S)}"
TRACE="logs/one_sample_trace_${RUN_ID}.txt"
mkdir -p reports logs work

# --- Phoenix HPC environment (adjust module versions if Phoenix changes them) ---
# Compute nodes have no internet. Pre-pull the pipeline ONCE on a login node:
#   nextflow pull nf-core/rnaseq -r <version>
module purge 2>/dev/null || true
module load Nextflow/25.10.2 2>/dev/null || true
module load Apptainer/1.2.5-GCCcore-12.3.0 2>/dev/null || true
export NXF_OPTS='-Xms1g -Xmx4g'
export NXF_OFFLINE='true'
export NXF_APPTAINER_CACHEDIR="${NXF_APPTAINER_CACHEDIR:-$PWD/apptainer_cache}"
mkdir -p "$NXF_APPTAINER_CACHEDIR"

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
GC_BIAS="$(get_config gc_bias)"; GC_BIAS="${GC_BIAS:-true}"
PIPELINE_VERSION="$(get_config pipeline_version)"; PIPELINE_VERSION="${PIPELINE_VERSION:-3.26.0}"
PROFILE="$(get_config profile)"; PROFILE="${PROFILE:-apptainer}"
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

# nf-core/rnaseq removed --max_cpus/--max_memory/--max_time (template v3+);
# set process.resourceLimits via a generated config instead (Nextflow 24.04+).
add_resource_limits() {
  local res=() mem_gb conf="configs/resource_limits.config"
  mem_gb="$(printf '%s' "$MEMORY" | grep -oE '^[0-9]+(\.[0-9]+)?' || true)"
  [[ -n "$CPU" && "$CPU" != "auto" && "$CPU" != "unknown" ]] && res+=("cpus: ${CPU}")
  [[ -n "$mem_gb" ]] && res+=("memory: ${mem_gb}.GB")
  [[ -n "$WALLTIME" && "$WALLTIME" != "auto" && "$WALLTIME" != "unknown" ]] && res+=("time: ${WALLTIME}")
  if [[ ${#res[@]} -gt 0 ]]; then
    mkdir -p configs
    printf 'process {\n  resourceLimits = [ %s ]\n}\n' "$(IFS=,; echo "${res[*]}")" > "$conf"
    cmd+=(-c "$conf")
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

round_up_to_multiple() {
  local value="$1"
  local multiple="$2"
  echo $(( ((value + multiple - 1) / multiple) * multiple ))
}

recommend_resources_from_trace() {
  [[ -f "$TRACE" ]] || return 0

  local recommendation
  recommendation="$(awk -F'\t' '
    function mem_gb(value, n, unit) {
      n = value
      sub(/ .*/, "", n)
      unit = value
      sub(/^[0-9.]+ /, "", unit)
      if (unit == "TB") return n * 1024
      if (unit == "GB") return n
      if (unit == "MB") return n / 1024
      if (unit == "KB") return n / 1024 / 1024
      return n
    }
    function hours(value, total, i, part, n, unit) {
      total = 0
      gsub(/,/, "", value)
      split(value, part, " ")
      for (i in part) {
        n = part[i]
        unit = n
        sub(/^[0-9.]+/, "", unit)
        sub(/[a-zA-Z]+$/, "", n)
        if (unit == "d") total += n * 24
        else if (unit == "h") total += n
        else if (unit == "m") total += n / 60
        else if (unit == "s") total += n / 3600
      }
      return total
    }
    NR == 1 {
      for (i = 1; i <= NF; i++) col[$i] = i
      next
    }
    ($col["status"] == "COMPLETED" || $col["status"] == "CACHED") && $col["name"] ~ /STAR_ALIGN|STAR_GENOMEGENERATE/ {
      rss = mem_gb($col["peak_rss"])
      if (rss > max_rss) {
        max_rss = rss
        max_rss_task = $col["name"]
      }
      cpu = $col["%cpu"]
      gsub(/%/, "", cpu)
      if (cpu > max_cpu) max_cpu = cpu
      t = hours($col["realtime"])
      if (t == 0) t = hours($col["duration"])
      if (t > max_hours) {
        max_hours = t
        max_time_task = $col["name"]
      }
    }
    END {
      if (max_rss > 0 || max_cpu > 0 || max_hours > 0) {
        printf "%.2f\t%.0f\t%.2f\t%s\t%s\n", max_rss, max_cpu, max_hours, max_rss_task, max_time_task
      }
    }
  ' "$TRACE")"

  [[ -n "$recommendation" ]] || return 0

  local peak_rss_gb peak_cpu_pct max_hours peak_rss_task max_time_task
  IFS=$'\t' read -r peak_rss_gb peak_cpu_pct max_hours peak_rss_task max_time_task <<< "$recommendation"

  if [[ "$SKIP_ALIGNMENT" == "true" || -z "$ALIGNER" ]]; then
    {
      echo
      echo "## STAR resource recommendation"
      echo
      echo "Skipped: this run does not use genome alignment, so no STAR-specific resource override is needed."
    } >> "$REPORT"
    return 0
  fi

  local min_mem=64 min_cpu=4 min_walltime=12
  local rec_memory rec_memory_gb rec_cpu rec_walltime star_max_forks
  rec_memory="$(awk -v peak="$peak_rss_gb" -v min="$min_mem" 'BEGIN {
    rec = int((peak * 1.35) + 4 + 0.999)
    if (rec < min) rec = min
    printf "%d", rec
  }')"
  rec_memory_gb="$(round_up_to_multiple "$rec_memory" 8)"
  rec_memory="${rec_memory_gb}G"

  rec_cpu="$(awk -v peak="$peak_cpu_pct" -v min="$min_cpu" 'BEGIN {
    rec = int((peak / 100 * 1.25) + 0.999)
    if (rec < min) rec = min
    printf "%d", rec
  }')"

  rec_walltime="$(awk -v peak="$max_hours" -v min="$min_walltime" 'BEGIN {
    rec = int((peak * 2) + 0.999)
    if (rec < min) rec = min
    printf "%d.h", rec
  }')"
  star_max_forks=$((300 / rec_memory_gb))
  [[ "$star_max_forks" -lt 1 ]] && star_max_forks=1
  [[ "$star_max_forks" -gt 4 ]] && star_max_forks=4

  {
    echo
    echo "## STAR resource recommendation from one-sample trace"
    echo
    echo "Trace file: \`$TRACE\`"
    echo
    echo "- STAR peak RSS: ${peak_rss_gb} GB"
    echo "- STAR peak CPU: ${peak_cpu_pct}%"
    echo "- STAR longest task realtime: ${max_hours} h"
    echo "- STAR memory-driving task: ${peak_rss_task:-unknown}"
    echo "- STAR time-driving task: ${max_time_task:-unknown}"
    echo
    echo "Recommended STAR override for Step 6:"
    echo
    echo "- STAR memory: \`$rec_memory\`"
    echo "- STAR cpu: \`$rec_cpu\`"
    echo "- STAR walltime: \`$rec_walltime\`"
    echo "- STAR maxForks: \`$star_max_forks\`"
    echo
    echo "Only STAR-specific settings are recommended. Other nf-core/rnaseq process resources are left unchanged unless they fail or are manually tuned. STAR maxForks is calculated from a 300 GB total STAR memory budget and capped at 4."
  } >> "$REPORT"

  if [[ "$ALLOW_FIXES" == "true" ]]; then
    local star_conf="configs/star_resource_recommendation.config"
    cat > "$star_conf" <<CONF
process {
  withName: '.*:STAR_ALIGN' {
    cpus = ${rec_cpu}
    memory = '${rec_memory_gb} GB'
    time = '${rec_walltime}'
    maxForks = ${star_max_forks}
    errorStrategy = 'retry'
    maxRetries = 2
  }
}
CONF
    set_config_value star_resource_config "\"$star_conf\""
    echo "Applied STAR-only resource recommendation to $star_conf and recorded it in $CONFIG because ALLOW_FIXES=true." >> "$REPORT"
  else
    echo "Recommendation not applied. Re-run with ALLOW_FIXES=true to write configs/star_resource_recommendation.config and use it in Step 6 automatically." >> "$REPORT"
  fi
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
    -r "$PIPELINE_VERSION"
    -offline
    --igenomes_ignore
    --bam_csi_index
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
  if [[ "$GC_BIAS" == "true" ]]; then
    cmd+=("--extra_salmon_quant_args=--gcBias")
  fi
  add_resource_limits
  rm -f "$TRACE"
  "${cmd[@]}" -resume -with-trace "$TRACE" 2>&1 | tee logs/one_sample_run.log
}

if ! command -v nextflow >/dev/null 2>&1; then
  echo "ERROR: nextflow not found in PATH. Load/install Nextflow first (e.g. 'module load Nextflow')." | tee -a "$REPORT" >&2
  exit 1
fi
echo "Using nf-core/rnaseq version: $PIPELINE_VERSION"

if ! run_one_sample; then
  if [[ "$ALLOW_FIXES" == "true" ]]; then
    echo "Initial one sample run failed. Applying safe infrastructure/resource fixes and resuming." >> "$REPORT"
    prepare_runtime_dirs
    if grep -Eiq 'out.of.memory|oom|oom-kill|slurmstepd|killed|cannot allocate|memory|exit status 137|exit status 143' logs/one_sample_run.log; then
      bump_memory
    fi
    if grep -Eiq 'time limit|walltime|wall time|exceeded.*time|DUE TO TIME LIMIT|exit status 140' logs/one_sample_run.log; then
      bump_walltime
    fi
    if grep -Eiq 'no space left|quota|disk quota exceeded|disk|scratch|tmpdir|permission denied|read-only' logs/one_sample_run.log; then
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
recommend_resources_from_trace
