#!/usr/bin/env Rscript
# Build a plain-text project report that combines project metadata
# (configs/configure.yaml + PROJECT_INFO.md) with the MultiQC general
# statistics produced by nf-core/rnaseq. Uses base R only (no packages).
#
# Usage:
#   Rscript scripts/make_report.R [results_dir] [out_file]
# Defaults:
#   results_dir = downloaded_results
#   out_file    = downloaded_results/qc_report/project_report.md

args <- commandArgs(trailingOnly = TRUE)
results_dir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "downloaded_results"
out_file    <- if (length(args) >= 2 && nzchar(args[2])) args[2] else file.path(results_dir, "qc_report", "project_report.md")
config_file <- Sys.getenv("CONFIG", "configs/configure.yaml")

dir.create(dirname(out_file), showWarnings = FALSE, recursive = TRUE)

# --- minimal YAML reader: "key: value" with optional quotes ---------------
read_yaml_flat <- function(path) {
  vals <- list()
  if (!file.exists(path)) return(vals)
  for (ln in readLines(path, warn = FALSE)) {
    if (!grepl(":", ln, fixed = TRUE)) next
    key <- trimws(sub(":.*$", "", ln))
    val <- trimws(sub("^[^:]*:", "", ln))
    val <- sub('^"(.*)"$', "\\1", val)
    val <- sub("^'(.*)'$", "\\1", val)
    if (nzchar(key)) vals[[key]] <- val
  }
  vals
}

cfg <- read_yaml_flat(config_file)
get <- function(k, default = "(not set)") {
  v <- cfg[[k]]
  if (is.null(v) || !nzchar(v)) default else v
}

mode_label <- if (identical(get("run_mode", ""), "salmon_only")) "Salmon only" else "STAR + Salmon"
gc_label   <- if (identical(get("gc_bias", ""), "true")) "enabled" else "disabled"

# --- locate the MultiQC general stats table -------------------------------
stats_file <- NA_character_
if (dir.exists(results_dir)) {
  search_dirs <- c(
    file.path(results_dir, "qc_report"),
    file.path(results_dir, "results", "multiqc"),
    file.path(results_dir, "multiqc"),
    results_dir
  )
  search_dirs <- unique(search_dirs[dir.exists(search_dirs)])
  hits <- unlist(lapply(search_dirs, function(path) {
    list.files(path, pattern = "multiqc_general_stats\\.txt$",
               recursive = TRUE, full.names = TRUE)
  }), use.names = FALSE)
  if (length(hits) > 0) stats_file <- hits[1]
}

con <- file(out_file, open = "wt")
w <- function(...) cat(..., "\n", sep = "", file = con)

w("# Project Report")
w("")
w("## Project")
w("")
w("- Project Name: ", get("project_name"))
w("- Project Description: ", get("project_description"))
w("- Project Owner: ", get("project_owner"))
w("- Created Date: ", get("created_date"))
w("")
w("## Versions")
w("")
w("- Guide Version: ", get("guide_version"))
w("- Template Version: ", get("template_version"))
w("- Pipeline Version: nf-core/rnaseq ", get("pipeline_version"))
w("")
w("## Workflow")
w("")
w("- Pipeline Mode: ", mode_label)
w("- Profile: ", get("profile"))
w("- GC Bias Correction: ", gc_label)
w("- Samples (configured): ", get("sample_count"))
w("- Reference: ", get("reference"))
w("- Annotation: ", get("annotation"), " (", get("annotation_type"), ")")
w("")
w("## MultiQC Summary")
w("")

if (is.na(stats_file)) {
  w("MultiQC general stats not found under '", results_dir,
    "'. Run the pipeline, then run scripts/download_results.sh before re-running this script.")
} else {
  w("Source: ", stats_file)
  w("")
  df <- tryCatch(
    read.delim(stats_file, header = TRUE, check.names = FALSE,
               stringsAsFactors = FALSE, na.strings = c("", "NA")),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) == 0) {
    w("Could not parse the MultiQC stats table.")
  } else {
    # Keep the sample column plus up to 7 metric columns for readability.
    keep <- seq_len(min(ncol(df), 8))
    df <- df[, keep, drop = FALSE]
    # round numeric columns
    for (j in seq_along(df)) {
      if (is.numeric(df[[j]])) df[[j]] <- round(df[[j]], 2)
    }
    hdr <- names(df)
    w("| ", paste(hdr, collapse = " | "), " |")
    w("|", paste(rep(" --- ", length(hdr)), collapse = "|"), "|")
    for (i in seq_len(nrow(df))) {
      row <- vapply(df[i, ], function(x) {
        x <- as.character(x); if (is.na(x)) "" else x
      }, character(1))
      w("| ", paste(row, collapse = " | "), " |")
    }
    w("")
    w("Rows: ", nrow(df), " sample(s). Open the full MultiQC HTML report for complete QC.")
  }
}

close(con)
cat("Wrote", out_file, "\n")
