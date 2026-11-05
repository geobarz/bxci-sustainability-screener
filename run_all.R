# =============================================================================
# run_all.R
# -----------------------------------------------------------------------------
# Re-runs the whole data pipeline in order, from the project root:
#   01  download SEC data           (skips files already downloaded)
#   02  clean latest holdings       (+ reconciliation to the filing)
#   03  sector exposure, all filings (+ reconciliation)   ~2 min
#   04  download EPA factors        (skips files already downloaded)
#   05  metrics
#   then: the metrics tests, and 06 (copies inputs the dashboard needs)
#
# Each script runs in its own fresh R session, exactly as if you typed
# `Rscript R/0x_....R`. If any step fails, everything stops there.
#
# HOW TO RUN   Rscript run_all.R        (or open in RStudio and click Source)
# AFTERWARDS   render the dashboard:  cd dashboard && quarto render
#              then check it:         Rscript tests/test_dashboard.R
# =============================================================================

if (!file.exists("bxci-sustainability-screener.Rproj")) {
  stop("Run this from the project root (the folder with the .Rproj file).")
}
if (!nzchar(Sys.getenv("SEC_USER_AGENT"))) {
  stop("SEC_USER_AGENT is not set. Add it to ~/.Renviron (see README) and restart R.")
}

steps <- c(
  "R/01_fetch_sec.R",
  "R/02_clean_soi.R",
  "R/03_clean_sector_subtotals.R",
  "R/04_fetch_epa_factors.R",
  "R/05_metrics.R",
  "tests/test_metrics.R",
  "R/06_dashboard_inputs.R"
)

rscript <- file.path(R.home("bin"), "Rscript")

for (step in steps) {
  cat("\n==================== ", step, " ====================\n", sep = "")
  started <- Sys.time()
  status  <- system2(rscript, step)
  if (status != 0) stop(step, " failed (exit code ", status, "). Fix it, then re-run run_all.R.")
  cat(sprintf("-- %s finished in %.0f seconds\n", step, as.numeric(Sys.time() - started, units = "secs")))
}

cat("\nAll steps finished. Next: cd dashboard && quarto render, then Rscript tests/test_dashboard.R\n")
