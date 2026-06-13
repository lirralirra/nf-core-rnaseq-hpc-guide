#!/usr/bin/env bash
set -euo pipefail

FASTQ_DIR="${FASTQ_DIR:-input/fastq}"
SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
FORCE="${FORCE:-false}"
REPORT="reports/input_validation_report.md"

mkdir -p "$(dirname "$SAMPLESHEET")" reports

if [[ -f "$SAMPLESHEET" && "$FORCE" != "true" ]]; then
  echo "Samplesheet exists: $SAMPLESHEET"
  echo "Set FORCE=true to overwrite."
  exit 0
fi

tmp="$(mktemp)"
echo "sample,fastq_1,fastq_2,strandedness" > "$tmp"

find "$FASTQ_DIR" -type f \( -name "*R1*.fastq.gz" -o -name "*_1.fastq.gz" \) | sort | while read -r r1; do
  r2="${r1/R1/R2}"
  [[ "$r2" == "$r1" ]] && r2="${r1/_1.fastq.gz/_2.fastq.gz}"
  sample="$(basename "$r1" | sed -E 's/(_R?1|_1).*//')"
  if [[ -f "$r2" ]]; then
    echo "$sample,$r1,$r2,auto" >> "$tmp"
  else
    echo "- Unmatched R1 FASTQ: $r1" >> "$REPORT"
  fi
done

mv "$tmp" "$SAMPLESHEET"
echo "Wrote $SAMPLESHEET"
