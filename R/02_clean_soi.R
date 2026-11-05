# =============================================================================
# 02_clean_soi.R
# -----------------------------------------------------------------------------
# PURPOSE
#   Turn BCRED's raw schedule of investments (SOI) into ONE clean table of
#   holdings for the LATEST period end, and check that it adds up to the
#   "total investments at fair value" BCRED reports in that filing.
#
# RULES APPLIED (see docs-notes/DECISIONS.md)
#   #3   Fair value = SOI column "Initial fair value of Investment";
#        cost = "Adjusted cost basis" (verified against XBRL tags).
#   #10  JV loans dropped; BCRED's LP stakes in its JVs kept.
#   #11  Industry, investment type, maturity left blank: not tagged per holding.
#   #12  Cash and money market funds excluded.
#   #13  Rows with no fair value (placeholders, one misaligned SEC row) excluded
#        and listed on screen.
#
# UNITS
#   All money columns are in US DOLLARS (XBRL unit "USD"). The filing itself
#   presents them in thousands, so every value is a whole multiple of 1,000.
#   Rates and percentages are decimals: 0.0639 = 6.39%.
#
# INPUT   data/raw/bdc/manifest.csv, the latest soi.tsv, and num.tsv inside
#         the same ZIP (for the reported total).
# OUTPUT  data/processed/bcred_holdings_clean.csv
#
# HOW TO RUN
#   From the project root:  Rscript R/02_clean_soi.R   (about 30 seconds)
#   It STOPS if the table's total differs from the filing's total by 1% or more.
# =============================================================================

source("R/00_helpers.R")   # BCRED_CIK, RAW_BDC_DIR, read_bcred_soi(), read_reported_total()

OUTPUT_FILE   <- path("data", "processed", "bcred_holdings_clean.csv")
TOLERANCE_PCT <- 1            # max allowed gap vs the filing, in percent
LEGAL_ENTITY  <- "Blackstone Private Credit Fund (incl. consolidated subsidiaries)"

JV_HOLDERS   <- c("Emerald JV LP", "Verdelite JV LP")   # the JVs' own loan books
CASH_PATTERN <- "^Other Cash and Cash Equivalents$|Money Market"


# ---- Helper: pick the filing with the latest period end ---------------------
# Reads only the small sub.tsv files to find it, so we open one big soi.tsv.
find_latest_filing <- function(manifest) {
  subs <- bind_rows(lapply(seq_len(nrow(manifest)), function(i) {
    sub_file <- path(path_ext_remove(manifest$saved_as[i]), "sub.tsv")
    s <- read_tsv(sub_file, col_types = cols(.default = col_character()),
                  quote = "", na = "", progress = FALSE)
    s <- s[as.integer(s$cik) == as.integer(BCRED_CIK) & s$form %in% c("10-K", "10-Q"), ]
    if (nrow(s) == 0) return(NULL)
    tibble(adsh = s$adsh, period = as.Date(s$period, "%Y%m%d"),
           zip_file = manifest$saved_as[i], zip = manifest$zip[i])
  }))
  latest <- subs[subs$period == max(subs$period), ]
  if (nrow(latest) != 1) stop("Expected one BCRED filing for the latest period, found ", nrow(latest))
  latest
}


# ---- Helper: split "Issuer name 2 | Non-Affiliated Issuer" into two parts ----
# The text after the last "|" says who holds the investment. Some rows have no
# "|" at all (e.g. "BCRED Emerald JV LP - LP Interest"); their holder is NA.
split_identifier <- function(id) {
  has_bar <- grepl("\\|", id)
  tibble(
    investment = trimws(ifelse(has_bar, sub("\\|[^|]*$", "", id), id)),
    holder     = ifelse(has_bar, trimws(sub("^.*\\|", "", id)), NA_character_)
  )
}


# ---- Helper: classify each holding row --------------------------------------
classify_rows <- function(df) {
  df |> mutate(row_class = case_when(
    holder_as_reported %in% JV_HOLDERS          ~ "jv_loan",        # a JV's own loan
    grepl("(Emerald|Verdelite) JV LP$", investment) & is.na(fair_value) ~ "jv_loan",
    grepl(CASH_PATTERN, investment)             ~ "cash",
    is.na(fair_value)                           ~ "no_fair_value",
    TRUE                                        ~ "holding"
  ))
}


# ---- 1. Load the latest filing's holding rows -------------------------------
manifest <- read_csv(path(RAW_BDC_DIR, "manifest.csv"), show_col_types = FALSE)
latest   <- find_latest_filing(manifest)
soi_file <- path(path_ext_remove(latest$zip_file), "soi.tsv")
cat("Latest filing:", latest$adsh, "period end", format(latest$period), "from", latest$zip, "\n")

bcred <- read_bcred_soi(soi_file)
rows  <- bcred[bcred$adsh == latest$adsh &
               bcred$ddate == format(latest$period) &
               !is.na(bcred$`Investment, Identifier Axis`), ]
if (any(rows$malformed)) stop("Some holding rows are malformed in the SEC file. Check before continuing.")

# Optional SOI columns: use them if present, otherwise NA.
col_or_na <- function(name) if (name %in% names(rows)) rows[[name]] else NA_character_

parts <- split_identifier(rows$`Investment, Identifier Axis`)
holdings <- tibble(
  investment            = parts$investment,
  # Issuer = investment name without BCRED's trailing tranche number ("... Inc. 2").
  issuer                = sub("\\s+\\d+$", "", parts$investment),
  holder_as_reported    = parts$holder,
  affiliation           = parts$holder,
  legal_entity          = LEGAL_ENTITY,
  industry              = NA_character_,   # decision #11: not tagged per holding
  investment_type       = NA_character_,   # decision #11: not tagged per holding
  maturity_date         = as.Date(col_or_na("Investment Maturity Date")),
  principal             = as.numeric(col_or_na("Investment Owned, Balance, Principal Amount")),
  cost                  = as.numeric(rows$`Adjusted cost basis`),
  fair_value            = as.numeric(rows$`Initial fair value of Investment`),
  pct_net_assets        = as.numeric(rows$`Investment Owned, Net Assets, Percentage`),
  interest_rate         = as.numeric(col_or_na("Investment Interest Rate")),
  spread                = as.numeric(col_or_na("Investment, Basis Spread, Variable Rate")),
  pik_rate              = as.numeric(col_or_na("Investment, Interest Rate, Paid in Kind")),
  shares                = as.numeric(col_or_na("Investment shares")),
  period                = latest$period,
  form                  = rows$form,
  adsh                  = rows$adsh,
  filing_url            = rows$inlineurl,
  source_file           = as.character(soi_file),
  identifier_as_reported = rows$`Investment, Identifier Axis`
)
holdings <- classify_rows(holdings)

# The holder text is the affiliation only for BCRED's own rows.
holdings$affiliation[!holdings$holder_as_reported %in%
  c("Non-Affiliated Issuer", "Non-Controlled Affiliated Issuer", "Controlled Affiliated Issuer")] <- NA


# ---- 2. Show what was left out, and why --------------------------------------
cat("\nRows by class:\n")
print(as.data.frame(holdings |> group_by(row_class) |>
  summarise(rows = n(), fair_value_usd = sum(fair_value, na.rm = TRUE))), row.names = FALSE)

cat("\nExcluded: no fair value reported (", sum(holdings$row_class == "no_fair_value"), "rows):\n")
print(holdings$identifier_as_reported[holdings$row_class == "no_fair_value"])

cat("\nExcluded: cash and money market funds:\n")
print(as.data.frame(holdings[holdings$row_class == "cash", c("investment", "fair_value")]), row.names = FALSE)


# ---- 3. Units check ------------------------------------------------------------
clean <- holdings |> filter(row_class == "holding") |> select(-row_class)
money <- c(clean$fair_value, clean$cost, clean$principal)
money <- money[!is.na(money)]
cat("\nUnits: US dollars. Every amount a whole multiple of $1,000:", all(money %% 1000 == 0), "\n")


# ---- 4. Reconcile against the filing's reported total -------------------------
reported <- read_reported_total(latest$zip_file, latest$adsh, latest$period)
mine     <- sum(clean$fair_value)
diff_usd <- mine - reported
diff_pct <- 100 * diff_usd / reported

cat("\n===== Reconciliation =====\n")
cat(sprintf("  Total investments at fair value, per filing: $%s\n", format(reported, big.mark = ",")))
cat(sprintf("  Sum of clean holdings table:                 $%s\n", format(mine, big.mark = ",")))
cat(sprintf("  Difference:                                  $%s (%.3f%%)\n",
            format(diff_usd, big.mark = ","), diff_pct))

if (abs(diff_pct) >= TOLERANCE_PCT) {
  stop("The holdings table does not tie to the filing within ", TOLERANCE_PCT, "%. Not saving.")
}


# ---- 5. Save -------------------------------------------------------------------
write_csv(clean, OUTPUT_FILE)
cat("\nSaved", nrow(clean), "holdings to", OUTPUT_FILE, "\n")
