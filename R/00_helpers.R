# =============================================================================
# 00_helpers.R
# -----------------------------------------------------------------------------
# Small functions shared by more than one script. Not run on its own.
# Load it at the top of a script with:  source("R/00_helpers.R")
# =============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(fs)
})

BCRED_CIK   <- "1803498"
RAW_BDC_DIR <- path("data", "raw", "bdc")


# ---- Read every BCRED row from one soi.tsv ----------------------------------
# All columns are read as text so nothing is rounded or converted silently.
# quote = "" because the SEC files are plain tab-separated with no quoting.
# Rows the SEC file got wrong (more fields than the header) are flagged in a
# `malformed` column, not dropped.
read_bcred_soi <- function(soi_file) {
  soi <- suppressWarnings(
    read_tsv(soi_file, col_types = cols(.default = col_character()),
             quote = "", na = "", progress = FALSE)
  )
  soi$malformed <- seq_len(nrow(soi)) %in% problems(soi)$row
  soi[soi$cik == BCRED_CIK, ]
}


# ---- Find BCRED's reported total investments at fair value ------------------
# Reads num.tsv inside the ZIP in chunks (it can be over 1 GB unzipped),
# keeping only this filing's lines. The total is the XBRL tag
# InvestmentOwnedAtFairValue for the period end with no dimensions
# (an empty "segments" field). Stops if it isn't exactly one value.
read_reported_total <- function(zip_file, adsh, period) {
  inside   <- unzip(zip_file, list = TRUE)$Name
  num_path <- inside[basename(inside) == "num.tsv"]
  if (length(num_path) != 1) stop("No num.tsv in ", zip_file)

  con <- unz(zip_file, num_path, open = "r")
  on.exit(close(con))
  header <- strsplit(readLines(con, n = 1), "\t", fixed = TRUE)[[1]]
  keep <- character()
  repeat {
    chunk <- readLines(con, n = 500000, warn = FALSE)
    if (length(chunk) == 0) break
    keep <- c(keep, chunk[startsWith(chunk, adsh)])
  }

  fields <- strsplit(keep, "\t", fixed = TRUE)
  facts  <- as_tibble(do.call(rbind, lapply(fields, `length<-`, length(header))),
                      .name_repair = ~header)
  total <- facts |>
    filter(tag == "InvestmentOwnedAtFairValue", qtrs == "0",
           ddate == format(as.Date(period), "%Y%m%d"),
           is.na(segments) | segments == "", uom == "USD")

  values <- unique(as.numeric(total$value))
  if (length(values) != 1) {
    stop(adsh, ": expected one reported total investments value, found ", length(values), ".")
  }
  values
}
