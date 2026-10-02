# omopReportToolkit

Render-only manuscript report toolkit for OMOP CDM studies in the
Duke-Vascular-Informatics workspace. Bucket 3 of
[`docs/MIGRATION_PLAN_REPO_SPLIT.md`](https://github.com/Duke-Vascular-Informatics/omop-dev-workspace/blob/main/docs/MIGRATION_PLAN_REPO_SPLIT.md)
in the `omop-dev-workspace` repo.

## What this is

Greyscale-safe manuscript figure styling (`R/figure_style.R`) and generic
Word-report helpers (`R/report_helpers.R`) — bibliography formatting,
calibration statistics, ROC/calibration figures, a styled Table 1 flextable,
docx post-processing — shared across studies that produce a manuscript-format
report on top of their analysis.

**Consumes only result artifacts already on disk** — CSVs, person-level score
tables, calibration tables. There is no `DatabaseConnector` dependency
anywhere in this package, and there must never be one. A colleague with a
clone of this package and a `results/` directory can produce a report with no
VPN, no credentials, and no database driver.

## What this is not

Nothing study-specific lives here: no cohort definitions, no score names, no
clinical narrative, no `fetch_*_from_omop()` queries. Per-study report
composition — which tables, which figures, in what order, with what
narrative — belongs in that study's own `<study>-report` repo (bucket 3b of
`docs/MIGRATION_PLAN_REPO_SPLIT.md` in `omop-dev-workspace`, scaffolded from
[`omop-report-template`](https://github.com/Duke-Vascular-Informatics/omop-report-template)),
which calls into this package. **Not** a `report_spec.R` file inside the
analysis-core repo — that was this plan's original design and was reversed
2026-08-11 specifically because a report repo needs to be shareable and
report-toolkit-consuming independent of the analysis-core repo's own
sharing profile; see the migration plan's "What NOT to do" section.

If you find yourself adding a study-specific branch to a function here, that
is a sign the function should not be here. Split it: the generic core stays,
the study-specific part moves to that study's `<study>-report` repo (its
`R/report_dispatch.R` / `R/report_helpers.R`).

## Installation

```r
renv::install("Duke-Vascular-Informatics/omop-report-toolkit@<commit-sha>")
renv::snapshot()
```

Pin to a commit SHA, not a branch — the same convention this workspace
already uses for other GitHub-sourced packages (e.g. `PhenotypeLibrary`).
**Do not run a blind `renv::snapshot()`** afterward in a consuming study repo
without checking the diff first: it has been observed to silently strip
unrelated packages (Strategus, CirceR, CohortDiagnostics, and others) from a
study's lockfile in this workspace. Prefer a targeted, hand-verified
`renv.lock` edit, or inspect `renv::snapshot()`'s dry-run output before
accepting it.

## Usage

```r
library(omopReportToolkit)

# Figures
p <- ggplot2::ggplot(df, ggplot2::aes(x, y)) + ggplot2::geom_line()
save_figure(p + theme_manuscript(), output_folder, "my_figure.png",
            width = 5, height = 5)

# Multi-series overlays use the shared greyscale encoding
scales <- .gs_scales(levels = c("Model A", "Model B"))
p <- p + scales$colour + scales$linetype + scales$shape

# Table 1 styling
ft <- .build_table1(predictor_tbl)
```

See each function's header comment in `R/figure_style.R` and
`R/report_helpers.R` for full documentation — this package is small enough
that the source is the reference.

## NAMESPACE is hand-written

This package has no `roxygen2`/`devtools` build step. If you add an export or
a new bare (unqualified) call to a non-base package, update `NAMESPACE` by
hand to match. Do not run `devtools::document()` — there are no roxygen tags
to generate from, and it will silently delete the hand-written entries.

## Provenance

Extracted 2026-08-10 from `pad-amp-nhd-val`'s `R/figure_style.R` and
`R/report_helpers.R` (the first repo where these functions reached their
current, greyscale-safe form — see that repo's PRs #42/#43 for the
peer-review defect the greyscale work fixes). Function bodies are
byte-identical to that source; only package-boundary changes were made
(`library()` calls removed, bare calls resolved via `NAMESPACE` imports).
`pad-amp-nhd-prog` consumed the same functions via direct file copy before
this package existed; both studies are this package's first two consumers.

## License

Copyright 2026 Duke University. All Rights Reserved. The software is hereby licensed under the GNU GPL License v2 (see [LICENSE](LICENSE)); `DESCRIPTION` declares `License: GPL-2`.
