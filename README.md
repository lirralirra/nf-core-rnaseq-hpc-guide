# RNA-seq Made Easy

A beginner-friendly 7-step guide and project template for running `nf-core/rnaseq` on the University of Adelaide Phoenix HPC, from local input preparation to results download.

## Files

- `index.html` - interactive seven-step workflow page
- `hands-on.html` - redirect kept for older links
- `documents.html` - detailed documentation, FAQ, and troubleshooting page
- `style.css` - page styling
- `scripts/` - editable local and HPC runner script templates
- `templates/` - reproducibility/config templates
- `demo/template_project_v1.0.0.zip` - empty reusable project template
- `demo/demo_project_v1.0.0.zip` - small demo project skeleton

## Visual Assets

The opening illustration is an AI-generated project image made for this guide. It should stay generic: do not replace it with third-party characters, logos, or copyrighted artwork unless you have permission to use them.

## Runner Principle

Keep the user journey simple with seven steps:

1. Initial Project - local
2. Prepare & Validate Inputs - local
3. Pipeline Configure - local
4. Upload to HPC - local
5. Preflight Validation - HPC
6. Run & Monitor - HPC
7. Download Results - local

The initialized project folder is uploaded to HPC with all scripts included from the start.

## Final Script List

- `make_samplesheet.sh` - local
- `input_validate.sh` - local
- `configure.sh` - local
- `upload_to_hpc.sh` - local
- `smoke_run.sh` - HPC
- `one_sample_run.sh` - HPC
- `run.sh` - HPC
- `monitor_run.sh` - HPC
- `download_results.sh` - local
- `make_report.R` - local (optional project report from MultiQC + project info)

## Use With GitHub Pages

Publish this folder as a GitHub Pages site, or copy these files to the root of a Pages branch.

All download links are relative, so no build step is required.

### Simple publish workflow

1. Create a GitHub repository.
2. Upload the contents of this folder so `index.html` is at the repository root.
3. In GitHub, open `Settings` -> `Pages`.
4. Set source to `Deploy from a branch`.
5. Choose the branch, usually `main`, and folder `/root`.
6. Save. GitHub will provide the Pages URL after the site is built.
