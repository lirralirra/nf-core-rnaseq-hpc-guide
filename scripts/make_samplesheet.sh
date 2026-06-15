#!/usr/bin/env bash
set -euo pipefail

FASTQ_DIR="${FASTQ_DIR:-input/fastq}"
SAMPLESHEET="${SAMPLESHEET:-input/samplesheet.csv}"
FORCE="${FORCE:-false}"
REPORT="reports/input_validation_report.md"

mkdir -p "$(dirname "$SAMPLESHEET")" reports

if [[ ! -d "$FASTQ_DIR" ]]; then
  echo "FASTQ directory not found: $FASTQ_DIR" >&2
  exit 1
fi

if [[ -f "$SAMPLESHEET" && "$FORCE" != "true" ]]; then
  echo "Samplesheet exists: $SAMPLESHEET"
  echo "Set FORCE=true to overwrite."
  exit 0
fi

tmp="$(mktemp)"
echo "sample,fastq_1,fastq_2,strandedness" > "$tmp"

# Accept .fastq.gz, .fq.gz, .fastq and .fq, with R1/R2 or _1/_2 naming.
find "$FASTQ_DIR" -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' -o -name '*.fastq' -o -name '*.fq' \) \
  | sort | while IFS= read -r r1; do
  base="$(basename "$r1")"
  # Only start a pair from the read-1 file; derive its read-2 mate.
  if [[ "$base" == *_R1_* || "$base" == *_R1.* ]]; then
    r2="${r1/_R1/_R2}"
  elif [[ "$base" == *_1.fastq.gz || "$base" == *_1.fq.gz || "$base" == *_1.fastq || "$base" == *_1.fq ]]; then
    r2="${r1%_1.*}_2.${r1##*_1.}"
  else
    continue
  fi
  sample="$(printf '%s' "$base" | sed -E 's/_(R?1)([_.].*)?$//')"
  if [[ -f "$r2" ]]; then
    echo "$sample,$r1,$r2,auto" >> "$tmp"
  else
    echo "- Unmatched R1 FASTQ (no R2 mate found): $r1" >> "$REPORT"
  fi
done

data_rows=$(($(wc -l < "$tmp") - 1))
if [[ "$data_rows" -lt 1 ]]; then
  rm -f "$tmp"
  echo "ERROR: no paired FASTQ samples found in $FASTQ_DIR." >&2
  echo "Checked .fastq.gz/.fq.gz/.fastq/.fq with R1/R2 or _1/_2 naming." >&2
  echo "Confirm FASTQ files are present and paired, then re-run." >&2
  exit 1
fi

mv "$tmp" "$SAMPLESHEET"
echo "Wrote $SAMPLESHEET ($data_rows sample(s))."

# nf-core/rnaseq requires gzipped FASTQ; warn if any uncompressed files were used.
if grep -qE '\.(fastq|fq),' "$SAMPLESHEET"; then
  echo "WARNING: uncompressed FASTQ detected. nf-core/rnaseq expects gzipped FASTQ files (.fastq.gz / .fq.gz)." >&2
  echo "         gzip your FASTQ files before running the pipeline." >&2
  echo "- WARNING: uncompressed FASTQ in samplesheet; nf-core/rnaseq expects gzipped FASTQ (.fastq.gz / .fq.gz)." >> "$REPORT"
fi

echo "ACTION: open $SAMPLESHEET and check sample names, R1/R2 pairing, and strandedness before continuing."
