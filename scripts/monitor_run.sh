#!/usr/bin/env bash
set -euo pipefail

echo "## Job status"
squeue -u "$USER" 2>/dev/null || true

echo
echo "## Disk usage"
du -sh results work logs reports 2>/dev/null || true

echo
echo "## Recent Nextflow log"
tail -80 .nextflow.log 2>/dev/null || echo "No .nextflow.log found"

echo
echo "## Failed tasks"
grep -i "failed\\|error\\|killed" .nextflow.log 2>/dev/null | tail -40 || true

echo
echo "Suggested actions: check memory, walltime, scratch space, container cache, and resume with -resume after safe fixes."
