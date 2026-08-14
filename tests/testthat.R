# =============================================================================
# tests/testthat.R
#
# Standard testthat entry point, used by `R CMD check` and by the CI workflow.
#
# For running the suite WITHOUT installing the package first (the usual
# dev-container loop), use instead:
#
#   Rscript -e 'testthat::test_dir("tests/testthat")'
#
# which picks up tests/testthat/helper-setup.R and source()s R/ directly.
# See that file for why the helper has to attach officer and flextable itself.
# =============================================================================

library(testthat)
library(omopReportToolkit)

test_check("omopReportToolkit")
