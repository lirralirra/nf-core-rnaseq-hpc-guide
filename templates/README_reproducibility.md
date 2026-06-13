# Reproducibility Notes

Project: `<project_name>`

Run date: `<YYYY-MM-DD>`

Pipeline: `nf-core/rnaseq`

Pipeline version: `<version>`

Nextflow version: `<version>`

Container engine: `Apptainer/Singularity`

HPC system: `<cluster_name>`

## Inputs

- Samplesheet: `input/samplesheet.csv`
- FASTQ directory: `input/fastq/`
- Genome FASTA: `input/reference/genome.fa`
- Annotation: `input/annotation/genes.gtf`

## Main Command

```bash
bash scripts/run.sh
```

## Resume Command

```bash
bash scripts/run.sh
```

## Outputs To Archive

- `results/`
- `logs/`
- `configs/`
- `input/samplesheet.csv`
- `docs/`
