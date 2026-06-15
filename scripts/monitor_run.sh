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
echo "## Run history (nextflow log)"
nextflow log 2>/dev/null | tail -6 || echo "nextflow log unavailable (run from the project dir after a run starts)"

echo
echo "## Failed tasks"
grep -iE "failed|error|killed|oom-kill|slurmstepd|DUE TO TIME LIMIT|disk quota exceeded" .nextflow.log 2>/dev/null | tail -40 || true

echo
echo "## Slurm accounting (recent jobs)"
sacct -u "$USER" --format=JobID,JobName%20,State,ExitCode,Elapsed,ReqMem,MaxRSS 2>/dev/null | tail -15 || echo "sacct unavailable"

echo
echo "## Most recent failed-task log"
latest_err="$(ls -t work/*/*/.command.err 2>/dev/null | head -n 1 || true)"
if [[ -n "$latest_err" ]]; then
  echo "From: $latest_err"
  tail -20 "$latest_err" 2>/dev/null || true
else
  echo "No .command.err found under work/ yet."
fi

echo
echo "Tips:"
echo "- 'nextflow log <run_name>' lists each task's work directory."
echo "- In a task work dir, inspect .command.err, .command.log and .command.out."
echo "- After a safe fix, resume with: bash scripts/run.sh -resume"
