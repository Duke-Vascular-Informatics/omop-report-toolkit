# =============================================================================
# R/globals.R
#
# Registers column names referenced UNQUOTED inside ggplot2::aes() as
# intentional, not undefined globals.
#
# WHY THIS FILE EXISTS
#   ggplot2's aes() uses non-standard evaluation: `aes(x = fpr, y = tpr)` reads
#   `fpr`/`tpr` as column names of the data frame passed to ggplot(), not as R
#   variables. `R CMD check`'s static analysis cannot see that — it flags them
#   as "no visible binding for global variable", one per column, across every
#   plotting function in R/report_helpers.R.
#
#   utils::globalVariables() is the standard, documented way to tell the check
#   these are known and deliberate (see "Writing R Extensions" section on NSE).
#   It changes nothing at runtime; it only suppresses the check-time NOTE.
#
# MAINTENANCE
#   If a new plotting function introduces a new unquoted aes() column name, add
#   it to the vector below rather than letting the NOTE reappear silently.
# =============================================================================

utils::globalVariables(c(
  "fpr", "tpr",                  # .save_roc_plot(), .save_dual_roc_plot()
  "model",                       # .save_dual_roc_plot(), .save_dual_calibration_plot()
  "predicted", "observed",       # .save_calibration_plot_from_table/vectors()
  "predicted_risk"               # .save_dual_calibration_plot()
))
