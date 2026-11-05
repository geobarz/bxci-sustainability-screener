# =============================================================================
# tests/test_dashboard.R
# -----------------------------------------------------------------------------
# Checks that the RENDERED dashboard (docs/index.html) shows the same numbers
# as the CSVs in data/processed/. It reads the chart data embedded in the HTML
# (plotly / reactable widgets) and the value-box text, and compares them.
#
# HOW TO RUN   (after rendering)  Rscript tests/test_dashboard.R
# =============================================================================

suppressPackageStartupMessages({ library(readr); library(dplyr); library(jsonlite) })

html     <- paste(readLines("docs/index.html", warn = FALSE), collapse = "\n")
metrics  <- read_csv("data/processed/portfolio_metrics.csv", show_col_types = FALSE)
summ     <- read_csv("data/processed/sector_summary.csv", show_col_types = FALSE)
holdings <- read_csv("data/processed/bcred_holdings_clean.csv", show_col_types = FALSE)
latest   <- max(metrics$period)
m        <- metrics[metrics$period == latest, ]
s_latest <- summ[summ$period == latest, ]

failures <- 0
check <- function(name, ok) {
  cat(if (isTRUE(ok)) "PASS" else "FAIL", "-", name, "\n")
  if (!isTRUE(ok)) failures <<- failures + 1
}

# ---- Pull every htmlwidget's JSON out of the page ------------------------------
blocks  <- regmatches(html, gregexpr('<script type="application/json" data-for="htmlwidget-[^"]+">.*?</script>', html))[[1]]
widgets <- lapply(blocks, function(b) fromJSON(sub("^<script[^>]*>", "", sub("</script>$", "", b)), simplifyVector = FALSE))
traces  <- unlist(lapply(widgets, function(w) w$x$data), recursive = FALSE)
trace_of <- function(type) Filter(function(t) identical(t$type, type), traces)

# ---- 1. Value boxes -------------------------------------------------------------
values <- trimws(regmatches(html, gregexpr('(?s)class="value-box-value">\\s*[^<]+', html, perl = TRUE))[[1]])
values <- trimws(sub('class="value-box-value">', "", values))
expected <- c(paste0("$", formatC(m$total_fair_value / 1e9, format = "f", digits = 2), "bn"),
              format(nrow(holdings), big.mark = ","),
              as.character(sum(s_latest$industry != "Not assigned to an industry by BCRED")),
              as.character(round(m$indicator_t_per_usd_m)),
              paste0(formatC(m$pct_fv_high_tier, format = "f", digits = 1), "%"))
cat("       Value boxes on page:", paste(values, collapse = " | "), "\n")
check("Value boxes match portfolio_metrics.csv / holdings / sector_summary", identical(values, expected))

# ---- 2. Tier bar chart -------------------------------------------------------------
bar <- trace_of("bar")[[1]]
tier_expected <- s_latest |> group_by(tier) |> summarise(pct = sum(pct_of_portfolio))
tier_page <- tibble(tier = unlist(bar$y), pct = unlist(bar$x))
cmp <- inner_join(tier_expected, tier_page, by = "tier", suffix = c("_csv", "_page"))
check("Tier chart: one bar per tier, values equal sector_summary.csv",
      nrow(cmp) == nrow(tier_expected) && all(abs(cmp$pct_csv - cmp$pct_page) < 1e-9))

# ---- 3. Heatmap ---------------------------------------------------------------------
hm <- trace_of("heatmap")[[1]]
rows <- sub(" · .*$", "", unlist(hm$y))
cols <- unlist(hm$x)
z    <- hm$z
bad <- 0
for (i in seq_along(rows)) for (j in seq_along(cols)) {
  v <- z[[i]][[j]]
  csv <- summ$pct_of_portfolio[summ$industry == rows[i] & format(summ$period, "%b %Y") == cols[j]]
  if (is.null(v) || is.na(v)) { if (length(csv) > 0) bad <- bad + 1 }
  else if (length(csv) != 1 || abs(csv - v) > 1e-9) bad <- bad + 1
}
check(paste0("Heatmap: all ", length(rows) * length(cols), " cells equal sector_summary.csv"), bad == 0)
check("Heatmap rows = industries held at the latest period", setequal(rows, s_latest$industry))

# ---- 4. Holdings scatter -------------------------------------------------------------
sc <- trace_of("scatter")
x_page <- sort(unlist(lapply(sc, function(t) unlist(t$x))))
# Zero-cost holdings (e.g. warrants) have no "% of cost", so they are not plotted.
x_csv  <- sort(holdings$cost[holdings$cost > 0] / 1e6)
n_zero <- sum(holdings$cost == 0)
check("Holdings chart: one point per holding with cost > 0, x = cost from bcred_holdings_clean.csv",
      length(x_page) == length(x_csv) && all(abs(x_page - x_csv) < 1e-9))
check(paste0("Holdings chart subtitle states the ", n_zero, " zero-cost holdings not plotted"),
      grepl(paste0(n_zero, " zero-cost holdings not plotted"), html, fixed = TRUE))

# ---- 5. Sector table (reactable) ------------------------------------------------------
rt <- Filter(function(w) !is.null(w$x$tag$attribs$data), widgets)
sector_tbl <- Filter(function(w) "Industry" %in% names(w$x$tag$attribs$data), rt)[[1]]$x$tag$attribs$data
tbl <- tibble(industry = unlist(sector_tbl$Industry), fv = unlist(sector_tbl$`Fair value ($bn)`))
cmp <- inner_join(tbl, s_latest, by = "industry")
check("Sector table: fair values equal sector_summary.csv",
      nrow(cmp) == nrow(s_latest) && all(abs(cmp$fv - cmp$fair_value / 1e9) < 1e-9))

# ---- 6. Required labels ---------------------------------------------------------------
check("Page says 'Sector-level proxy, not financed emissions'",
      grepl("Sector-level proxy, not financed emissions", html, fixed = TRUE))
check("Page names the exposure-weighted sector emissions-intensity indicator",
      grepl("exposure-weighted sector emissions-intensity indicator", html, fixed = TRUE))

cat("\n", if (failures == 0) "ALL DASHBOARD CHECKS PASSED" else paste(failures, "CHECK(S) FAILED"), "\n")
if (failures > 0) quit(status = 1)
