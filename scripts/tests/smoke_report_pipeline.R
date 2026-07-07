# Copyright (C) 2025 The University of Texas MD Anderson Cancer Center
#
# This file is part of xPEDITE.
#
# xPEDITE is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License Version 2 as published by the Free Software Foundation.
#
# xPEDITE is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with xPEDITE.
# If not, see <https://www.gnu.org/licenses/>.

## End-to-end smoke test for report generation.
##
## Runs the real data-processing stage of the pipeline (pipeline_processing.R)
## against representative datasets from test_data/ and asserts that the
## intermediate artifacts a report is assembled from are produced. This
## exercises the genuine analysis and normalization code end-to-end.
##
## It deliberately stops short of the final HTML render (generate_report.R),
## which requires the external ngchm and pathways containers. The steps that
## depend on those (NGCHM heatmaps, PCA embedding, the data-loader module) are
## each wrapped in tryCatch inside pipeline_processing.R, so their absence is
## logged but does not stop the core pipeline from producing its output.
##
## Must be run from the 'scripts' directory (pipeline_processing.R sources its
## dependencies with paths relative to that directory), e.g.:
##
##   cd scripts && Rscript tests/smoke_report_pipeline.R

if (!file.exists("pipeline_processing.R")) {
  stop("smoke_report_pipeline.R must be run from the 'scripts' directory")
}

scripts_dir <- normalizePath(getwd())
repo_root   <- normalizePath(file.path(scripts_dir, ".."))
test_data   <- file.path(repo_root, "test_data")

## Datasets chosen to cover the single- and multi-covariate process types the
## pipeline branches on (see get_process_type()).
datasets <- c("single_no_duplicates", "multi_no_duplicates")

## Artifacts pipeline_processing.R writes that a report is later built from.
expected_artifacts <- c(
  "metadata.json",
  "BatchData.tsv",
  "CovariateData.tsv",
  "Preprocessed_3_noNA_ISnormalized.tsv",
  "data_values.csv"
)

## Metadata the web app would normally generate from the study form. "Skyline"
## and "Standardized" are valid options offered in the UI (views/study.ejs).
metadata_json <- paste0(
  "{",
  '"title":"CI Smoke Test",',
  '"author":"CI",',
  '"PI":"CI Test",',
  '"studyNumber":"smoke",',
  '"institution":"CI",',
  '"samples":"tissue",',
  '"assayType":"Standardized",',
  '"toolUsed":"Skyline",',
  '"normalization":"totalarea"',
  "}"
)

failures <- character(0)

for (dataset in datasets) {
  cat(sprintf("\n=== Smoke test: %s ===\n", dataset))
  src <- file.path(test_data, dataset)
  if (!dir.exists(src)) {
    failures <- c(failures, sprintf("%s: dataset directory not found (%s)", dataset, src))
    next
  }

  work   <- tempfile(pattern = paste0("smoke_", dataset, "_"))
  input  <- file.path(work, "input")
  report <- file.path(work, "report")
  dir.create(input, recursive = TRUE)
  dir.create(report, recursive = TRUE)

  file.copy(file.path(src, "analyzed_data.csv"), file.path(input, "analyzed_data.csv"))
  file.copy(file.path(src, "pdata.csv"), file.path(input, "pdata.csv"))
  writeLines(metadata_json, file.path(input, "metadata.json"))

  ## Trailing slashes are required: pipeline_processing.R concatenates these
  ## folder paths directly with file names (e.g. paste(reportFolderPath, 'pvals...')).
  input_arg  <- paste0(input, "/")
  report_arg <- paste0(report, "/")

  args <- c(
    "pipeline_processing.R",
    "-f", "analyzed_data.csv",
    "-m", "metadata.json",
    "-p", "pdata.csv",
    "-d", input_arg,
    "-n", "totalarea",
    "-r", report_arg
  )

  out    <- system2("Rscript", args, stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")

  present <- file.exists(file.path(report, expected_artifacts))
  missing <- expected_artifacts[!present]
  empty   <- character(0)
  for (a in expected_artifacts[present]) {
    if (file.size(file.path(report, a)) == 0) empty <- c(empty, a)
  }

  ran_ok <- is.null(status) || status == 0
  if (length(missing) > 0 || length(empty) > 0 || !ran_ok) {
    cat("---- pipeline_processing.R output ----\n")
    cat(paste(out, collapse = "\n"), "\n")
    cat("--------------------------------------\n")
    if (!ran_ok) {
      failures <- c(failures, sprintf("%s: pipeline exited with status %s", dataset, status))
    }
    if (length(missing) > 0) {
      failures <- c(failures, sprintf("%s: missing artifacts: %s", dataset, paste(missing, collapse = ", ")))
    }
    if (length(empty) > 0) {
      failures <- c(failures, sprintf("%s: empty artifacts: %s", dataset, paste(empty, collapse = ", ")))
    }
  } else {
    cat(sprintf("OK: all %d expected artifacts produced\n", length(expected_artifacts)))
  }
}

if (length(failures) > 0) {
  cat("\nSMOKE TEST FAILED:\n")
  cat(paste0(" - ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("\nSMOKE TEST PASSED\n")
