#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-configs/configure.yaml}"
REPORT="reports/input_validation_report.md"
mkdir -p reports logs

get_config() {
  [[ -f "$CONFIG" ]] || return 0
  awk -F': *' -v key="$1" '$1 == key { v=$2; gsub(/^[\042\047]+|[\042\047]+$/, "", v); print v; exit }' "$CONFIG"
}

SAMPLESHEET="${SAMPLESHEET:-$(get_config samplesheet)}"
REFERENCE="${REFERENCE:-$(get_config reference)}"
ANNOTATION="${ANNOTATION:-$(get_config annotation)}"
FASTQ_DIR="${FASTQ_DIR:-$(get_config fastq_dir)}"

SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
REFERENCE="${REFERENCE:-input/reference/genome.fa}"
ANNOTATION="${ANNOTATION:-input/annotation/genes.gtf}"
FASTQ_DIR="${FASTQ_DIR:-input/fastq}"
errors=0

check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "- OK: $path"
  else
    echo "- MISSING: $path"
    errors=$((errors + 1))
  fi
}

# Read a plain or gzipped text file.
read_text() {
  case "$1" in
    *.gz) zcat "$1" 2> /dev/null || gzip -dc "$1" ;;
    *) cat "$1" ;;
  esac
}

{
  echo "# Input Validation Report"
  echo
  echo "Generated: $(date)"
  echo
  echo "## Required paths"
  [[ -f "$CONFIG" ]] && echo "- OK: $CONFIG" || echo "- INFO: $CONFIG not found yet; Step 2 uses default input paths before Step 3 configuration."
  check_path "$SAMPLESHEET"
  check_path "$REFERENCE"
  check_path "$ANNOTATION"
  check_path "$FASTQ_DIR"
  echo
  echo "## Samplesheet checks"
  if [[ -f "$SAMPLESHEET" ]]; then
    if head -n 1 "$SAMPLESHEET" | tr -d '\r' | grep -q '^sample,fastq_1,fastq_2,strandedness$'; then
      echo "- OK: header"
    else
      echo "- ERROR: unexpected header"
      errors=$((errors + 1))
    fi
    data_rows="$(awk -F, 'NR > 1 && $1 !~ /^[[:space:]]*$/ {count++} END {print count + 0}' "$SAMPLESHEET")"
    if [[ "$data_rows" -lt 1 ]]; then
      echo "- ERROR: samplesheet has no sample rows. Run scripts/make_samplesheet.sh after adding FASTQ files."
      errors=$((errors + 1))
    else
      echo "- OK: $data_rows sample row(s)"
    fi
    duplicates="$(awk -F, 'NR>1 {print $1}' "$SAMPLESHEET" | tr -d '\r' | sort | uniq -d || true)"
    if [[ -n "$duplicates" ]]; then
      printf '%s\n' "$duplicates" | sed 's/^/- DUPLICATE SAMPLE ID: /'
      echo "- WARNING: Duplicate sample IDs detected. This is OK for multiple lanes of the same sample, but check carefully."
    fi

    # Per-row checks: sample-name charset, strandedness whitelist, FASTQ existence.
    # CR is stripped on the stream so CRLF samplesheets validate correctly.
    while IFS=, read -r sample fastq_1 fastq_2 strandedness _rest; do
      [[ -z "$sample" ]] && continue

      if [[ ! "$sample" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "- BAD SAMPLE NAME: '$sample' (use only letters, numbers, dot, underscore, hyphen; no spaces or commas)"
        errors=$((errors + 1))
      fi

      case "$strandedness" in
        auto | forward | reverse | unstranded) : ;;
        *)
          echo "- BAD STRANDEDNESS: '$strandedness' for sample '$sample' (allowed: auto, forward, reverse, unstranded)"
          errors=$((errors + 1))
          ;;
      esac

      for fq in "$fastq_1" "$fastq_2"; do
        [[ -z "$fq" ]] && continue
        if [[ -f "$fq" ]]; then
          echo "- OK FASTQ: $fq"
        else
          echo "- MISSING FASTQ: $fq"
          errors=$((errors + 1))
        fi
      done
    done < <(tail -n +2 "$SAMPLESHEET" | tr -d '\r')
  fi
  echo
  echo "## Annotation contig check"
  if [[ -f "$REFERENCE" && -f "$ANNOTATION" ]]; then
    fasta_ids="$(read_text "$REFERENCE" | awk '/^>/ {print substr($1, 2)}' | sort -u)"
    anno_ids="$(read_text "$ANNOTATION" | awk '$0 !~ /^#/ && NF > 0 {print $1}' | sort -u)"
    if [[ -z "$fasta_ids" || -z "$anno_ids" ]]; then
      echo "- INFO: could not read contig IDs; skipping contig match."
    else
      missing=0
      while IFS= read -r contig; do
        [[ -z "$contig" ]] && continue
        if ! grep -qxF "$contig" <<< "$fasta_ids"; then
          echo "- CONTIG NOT IN FASTA: $contig"
          missing=$((missing + 1))
        fi
      done <<< "$anno_ids"
      if [[ "$missing" -gt 0 ]]; then
        echo "- WARNING: $missing annotation contig ID(s) not found in FASTA headers; confirm the genome and annotation match (not a blocking error)."
      else
        echo "- OK: annotation contig IDs are present in the FASTA."
      fi
    fi
  else
    echo "- INFO: reference or annotation missing; skipping contig match."
  fi
  echo
  echo "## Upload size estimate"
  du -sh input configs scripts reports README.md 2> /dev/null || true
  echo
  if [[ "$errors" -eq 0 ]]; then
    echo "## Result"
    echo "PASS"
  else
    echo "## Result"
    echo "FAIL: $errors blocking issue(s). Fix these before upload."
  fi
} > "$REPORT"

echo "Wrote $REPORT"
if [[ "$errors" -ne 0 ]]; then
  exit 1
fi
