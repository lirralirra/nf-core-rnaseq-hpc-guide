#!/usr/bin/env bash
# Preflight checks for an nf-core/rnaseq run on Phoenix.
#
# Run this on a LOGIN NODE with bash (it is lightweight and submits no heavy
# jobs; the -preview dry run just builds the workflow and validates inputs):
#
#   bash scripts/preflight.sh
#
# It loads the HPC modules, checks the container cache, disk space, reference
# indexes, and that every FASTQ in the samplesheet exists, then runs a Nextflow
# -preview dry run. Review reports/preflight_report.md before submitting run.sh.
set -uo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
REPORT="reports/preflight_report.md"
mkdir -p reports logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

SAMPLESHEET="$(get_config samplesheet)"; SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
REFERENCE="$(get_config reference)"
ANNOTATION="$(get_config annotation)"
ANNOTATION_TYPE="$(get_config annotation_type)"
ALIGNER="$(get_config aligner)"; ALIGNER="${ALIGNER:-star_salmon}"
PROFILE="$(get_config profile)"; PROFILE="${PROFILE:-apptainer}"
PIPELINE_VERSION="$(get_config pipeline_version)"; PIPELINE_VERSION="${PIPELINE_VERSION:-3.26.0}"
WORKDIR="$(get_config workdir)"; WORKDIR="${WORKDIR:-work}"
OUTDIR="$(get_config outdir)"; OUTDIR="${OUTDIR:-results}"

# Phoenix HPC modules (no-op off the cluster).
module purge 2>/dev/null || true
module load Nextflow/25.10.2 2>/dev/null || true
module load Apptainer/1.2.5-GCCcore-12.3.0 2>/dev/null || true

warn=0
{
  echo "# Preflight Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Checks"
} > "$REPORT"
ok()  { echo "  [OK]   $1"; echo "- [OK] $1"   >> "$REPORT"; }
bad() { echo "  [WARN] $1"; echo "- [WARN] $1" >> "$REPORT"; warn=$((warn + 1)); }

# 1. Nextflow available
if command -v nextflow >/dev/null 2>&1; then
  ok "nextflow found: $(nextflow -version 2>/dev/null | head -n 1)"
else
  bad "nextflow not found in PATH (load it first, e.g. 'module load Nextflow')"
fi

# 2. Apptainer container cache
if [[ -n "${NXF_APPTAINER_CACHEDIR:-}" ]]; then
  ok "NXF_APPTAINER_CACHEDIR=$NXF_APPTAINER_CACHEDIR"
else
  bad "NXF_APPTAINER_CACHEDIR not set — containers may be pulled repeatedly"
fi

# 3. Samplesheet and FASTQ paths
if [[ -f "$SAMPLESHEET" ]]; then
  n=$(awk 'END {print (NR > 0 ? NR - 1 : 0)}' "$SAMPLESHEET")
  ok "samplesheet found: $SAMPLESHEET ($n samples)"
  missing=0
  while IFS=, read -r sample f1 f2 rest; do
    [[ "$sample" == "sample" || -z "$sample" ]] && continue
    for f in "$f1" "$f2"; do
      [[ -n "$f" && ! -f "$f" ]] && { bad "FASTQ path missing: $f"; missing=$((missing + 1)); }
    done
  done < "$SAMPLESHEET"
  [[ $missing -eq 0 ]] && ok "all FASTQ paths in the samplesheet exist"
else
  bad "samplesheet not found: $SAMPLESHEET (generate it with make_samplesheet.sh)"
fi

# 4. Reference and annotation
if [[ -n "$REFERENCE" && -f "$REFERENCE" ]]; then ok "reference: $REFERENCE"; else bad "reference missing: ${REFERENCE:-<unset>}"; fi
if [[ -n "$ANNOTATION" && -f "$ANNOTATION" ]]; then ok "annotation: $ANNOTATION"; else bad "annotation missing: ${ANNOTATION:-<unset>}"; fi

# 5. Prebuilt indexes (optional but save the big indexing step)
if [[ -d references/prebuilt_indexes ]]; then
  ok "prebuilt indexes present (reuse with --star_index / --salmon_index)"
else
  echo "  [note] no references/prebuilt_indexes/ — STAR/Salmon indexes will be built (large genomes need the high-memory queue)"
  echo "- [note] no prebuilt indexes; they will be built on first run" >> "$REPORT"
fi

# 6. Disk space
{
  echo
  echo "## Disk"
  df -h . 2>/dev/null
  du -sh "$WORKDIR" "$OUTDIR" 2>/dev/null
} | tee -a "$REPORT" >/dev/null

# 7. Nextflow -preview dry run (builds workflow, validates inputs, no heavy jobs)
echo
echo "## Nextflow -preview dry run" | tee -a "$REPORT"
ann_flag="--gtf"
case "${ANNOTATION_TYPE:-}" in
  gff*) ann_flag="--gff" ;;
  *) [[ "$ANNOTATION" == *.gff || "$ANNOTATION" == *.gff3 || "$ANNOTATION" == *.gff.gz || "$ANNOTATION" == *.gff3.gz ]] && ann_flag="--gff" ;;
esac
if command -v nextflow >/dev/null 2>&1; then
  if nextflow run nf-core/rnaseq -r "$PIPELINE_VERSION" -profile "$PROFILE" -preview \
       --input "$SAMPLESHEET" --outdir "${OUTDIR%/}/preview" \
       --fasta "$REFERENCE" "$ann_flag" "$ANNOTATION" --aligner "$ALIGNER" --igenomes_ignore \
       2>&1 | tee logs/preflight_preview.log; then
    ok "-preview completed: the workflow builds and inputs validate"
  else
    bad "-preview failed — review logs/preflight_preview.log"
  fi
else
  bad "skipped -preview (nextflow not available)"
fi

{
  echo
  if [[ $warn -eq 0 ]]; then
    echo "## Result"
    echo "Preflight PASSED — no warnings. You can submit: sbatch scripts/run.sh"
  else
    echo "## Result"
    echo "Preflight finished with $warn warning(s). Fix them before submitting run.sh."
  fi
} >> "$REPORT"

echo
echo "Wrote $REPORT"
[[ $warn -eq 0 ]] || echo "Preflight finished with $warn warning(s) — review $REPORT."
