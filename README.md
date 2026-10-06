# omopReportToolkit

Render-only manuscript report toolkit for OMOP CDM studies in the
[charon](https://github.com/Duke-Vascular-Informatics/charon)-based workspaces. Bucket 3 of the
[Multi-Repo Analysis Pipeline](https://github.com/Duke-Vascular-Informatics/charon#multi-repo-analysis-pipeline)
convention.

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
narrative — belongs in that study's own `<study>-report` repo (bucket 3b of the
[Multi-Repo Analysis Pipeline](https://github.com/Duke-Vascular-Informatics/charon#multi-repo-analysis-pipeline),
scaffolded from
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

## Dependencies and acknowledgements

This package is a thin layer over several open-source R packages, and the work is theirs. We gratefully acknowledge their authors and maintainers. Each remains under its own license; none is redistributed in this repository, they are installed separately from CRAN.

| Package | Used for | License | Maintainer |
|---|---|---|---|
| [ggplot2](https://ggplot2.tidyverse.org) | Constructing every figure | MIT + file LICENSE | Thomas Lin Pedersen |
| [officer](https://davidgohel.github.io/officer/) | Building and editing the Word document, embedding figures | MIT + file LICENSE | David Gohel |
| [flextable](https://davidgohel.github.io/flextable/) | Styled tables (e.g. Table 1) | GPL-3 | David Gohel |
| [patchwork](https://patchwork.data-imaginist.com) | Composing multi-panel figures | MIT + file LICENSE | Thomas Lin Pedersen |
| [pROC](https://xrobin.github.io/pROC/) | ROC curves and AUC | GPL (>= 3) | Xavier Robin |
| [devEMF](https://github.com/plfjohnson/devEMF) | Vector EMF output for Word embedding | GPL-3 | Philip Johnson |
| grid (part of base R) | Graphical units for figure annotations | Part of R (GPL-2 or GPL-3) | R Core Team |
| [ragg](https://ragg.r-lib.org) *(suggested)* | High-resolution TIFF output when available | MIT + file LICENSE | Thomas Lin Pedersen |
| [testthat](https://testthat.r-lib.org) *(suggested)* | Unit tests | MIT + file LICENSE | Hadley Wickham |

Licenses above are as declared by the installed package versions at the time of writing (ggplot2 4.0.3, officer 0.7.6, flextable 0.10.0, patchwork 1.3.2, pROC 1.19.0.1, devEMF 4.6, ragg 1.5.2, testthat 3.3.2); check each package's own `DESCRIPTION` for the current terms. This package's own code is licensed under GPL v2 only (see below); that applies to this repository's code, not to the packages listed here.

## License

Copyright 2026 Duke University. All Rights Reserved. The software is hereby licensed under the GNU GPL License v2 (see [LICENSE](LICENSE)); `DESCRIPTION` declares `License: GPL-2`.
