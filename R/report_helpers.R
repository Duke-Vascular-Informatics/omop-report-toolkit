# =============================================================================
# R/report_helpers.R
#
# Generic manuscript report helpers shared across studies: bibliography
# formatting, calibration statistics, ROC/calibration figures, a styled
# Table 1 flextable, and Word docx post-processing.
#
# WHAT THIS FILE IS NOT
#   Nothing study-specific lives here - no cohort definitions, no score names,
#   no clinical narrative, no fetch_*_from_omop() queries, no database access
#   of any kind. Per-study report composition (which tables, which figures, in
#   what order, with what narrative) belongs in that study's own
#   <study>-report repo (scaffolded from omop-report-template), calling into
#   this package. If a function here starts growing a study-specific branch,
#   that is a sign it should not be here - split it, and keep the generic
#   core.
#
# EXTRACTED FROM
#   pad-amp-nhd-val's R/report_helpers.R (2026-08-10), the first repo where
#   these functions reached their current, greyscale-safe form (#42/#43,
#   docs/MIGRATION_PLAN_REPO_SPLIT.md Phase 1). Function bodies are
#   byte-identical to that source - only PACKAGE-REQUIRED changes were made:
#   library() calls removed (dependencies declared in DESCRIPTION instead) and
#   bare calls to non-base functions given `::` prefixes or NAMESPACE imports,
#   since a package has no implicit access to whatever the CALLER happened to
#   library() first. No behavior was changed. If you find a difference from
#   the source repo beyond that, it is a bug - file it.
#
# DEPENDS ON R/figure_style.R (same package): theme_manuscript(), save_figure(),
#   .gs_scales(), .calibration_axis_limits(), .calibration_reference_line().
# =============================================================================

.append_references_section <- function(doc, citations) {
  if (is.null(citations) || length(citations) == 0L) return(doc)

  doc <- body_add_par(doc, "", style = "Normal")
  doc <- body_add_par(doc, "References", style = "heading 1")

  for (i in seq_along(citations)) {
    ref  <- citations[[i]]
    # Vancouver format: Authors. Title. Journal. Year;Vol(Issue):Pages. doi:DOI
    line <- sprintf(
      "%d. %s. %s. %s. %s;%s(%s):%s. doi:%s",
      i,
      ref$authors,
      ref$title,
      ref$journal,
      ref$year,
      ref$volume,
      ref$issue,
      ref$pages,
      ref$doi
    )
    doc <- body_add_par(doc, line, style = "Normal")
  }
  doc
}

.compute_ece <- function(y, p, n_bins = 10) {
  p <- pmin(pmax(p, 0.0001), 0.9999)
  breaks <- quantile(p, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)

  # FIXED 2026-08-14 - found by the new unit tests (tests/testthat/test-report-helpers.R,
  # ".compute_ece() clamps probabilities away from 0 and 1").
  #
  # De-duplicate BEFORE the < 3 guard. Quantile breaks collapse whenever the
  # prediction distribution is concentrated, and the old code only handled the
  # fully-degenerate case: with a bimodal set (e.g. every prediction near 0 or
  # near 1, clamped to 0.0001 / 0.9999) the breaks come back as
  # c(0.0001, 0.0001, 0.5, 0.9999, 0.9999) - five values but only THREE unique.
  # `length(unique(breaks)) < 3` is therefore FALSE, so no fallback fired, and
  # cut() aborted the whole report with "'breaks' are not unique".
  #
  # unique() preserves order, and quantile() returns sorted values, so the
  # deduplicated vector is still a valid ascending breaks spec - just with fewer
  # bins than requested, which is the correct behaviour for a concentrated
  # distribution.
  breaks <- unique(breaks)
  if (length(breaks) < 3) breaks <- c(0, 1)

  p_binned <- cut(p, breaks = breaks, include.lowest = TRUE)

  ece_data <- aggregate(
    cbind(predicted = p, observed = y) ~ p_binned,
    data = data.frame(p = p, y = y, p_binned = p_binned),
    FUN = function(x) c(n = length(x), mean = mean(x, na.rm = TRUE))
  )

  # FIXED 2026-08-10 - this function computed nothing usable before this fix,
  # in a way that had never been caught: it is reachable only from
  # .report_word_simple(), a legacy entry point neither study's real pipeline
  # calls (both call .report_prognostic() via generate_manuscript_report()).
  #
  # Two independent bugs, found together while packaging this function for
  # reuse and testing it in isolation for the first time:
  #
  #   1. aggregate() with a multi-column response (cbind(predicted, observed))
  #      and a vector-valued FUN returns EACH response column as its own
  #      [n_bins x 2] matrix (columns "n", "mean") - not a list of vectors.
  #      do.call(rbind, <matrix>) errors ("second argument must be a list");
  #      the original code assumed a list-column shape that never occurs here.
  #   2. Even past that, only ece_data[, 2] ("predicted") was ever passed to
  #      cbind() - "observed" was silently dropped - while colnames()
  #      immediately after assigned FIVE names to what was structurally a
  #      THREE-column object (bin + 2 predicted stats). mean_obs and n_obs
  #      were never computed at all; ece_value's formula referencing them
  #      would have used whatever cbind's column-count mismatch left behind.
  #
  # Rebuilt explicitly rather than patched in place, so both response columns
  # are handled identically and the result columns are unambiguous.
  as_stat_matrix <- function(col) if (is.matrix(col)) col else do.call(rbind, col)
  pred_stats <- as_stat_matrix(ece_data[["predicted"]])
  obs_stats  <- as_stat_matrix(ece_data[["observed"]])

  ece_data <- data.frame(
    bin       = ece_data[["p_binned"]],
    n_pred    = pred_stats[, "n"],
    mean_pred = pred_stats[, "mean"],
    n_obs     = obs_stats[, "n"],
    mean_obs  = obs_stats[, "mean"]
  )

  ece_value <- sum(ece_data$n_pred * abs(ece_data$mean_pred - ece_data$mean_obs)) / length(y)

  list(ece = ece_value, bin_data = ece_data)
}

.save_roc_plot <- function(y, p, output_folder, auc_override = NA_real_) {
  if (length(unique(y)) < 2) return(NULL)

  p <- pmin(pmax(p, 0.0001), 0.9999)

  if (!is.na(auc_override)) {
    roc_lt <- pROC::roc(response = y, predictor = p, quiet = TRUE, direction = "<")
    roc_gt <- pROC::roc(response = y, predictor = p, quiet = TRUE, direction = ">")
    auc_lt <- as.numeric(pROC::auc(roc_lt))
    auc_gt <- as.numeric(pROC::auc(roc_gt))

    if (abs(auc_lt - as.numeric(auc_override)) <= abs(auc_gt - as.numeric(auc_override))) {
      roc_obj <- roc_lt
      auc_val <- auc_lt
    } else {
      roc_obj <- roc_gt
      auc_val <- auc_gt
    }
    auc_label <- as.numeric(auc_override)
  } else {
    roc_obj <- pROC::roc(response = y, predictor = p, quiet = TRUE)
    auc_val <- as.numeric(pROC::auc(roc_obj))
    auc_label <- auc_val
  }

  # Create ROC curve data
  roc_data <- data.frame(
    fpr = 1 - roc_obj$specificities,
    tpr = roc_obj$sensitivities
  )

  p <- ggplot2::ggplot(roc_data, ggplot2::aes(x = fpr, y = tpr)) +
    ggplot2::geom_path(linewidth = 1) +
    ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "gray") +
    ggplot2::labs(
      title = "Receiver Operating Characteristic Curve",
      subtitle = paste0("AUROC = ", round(auc_label, 3)),
      x = "False Positive Rate",
      y = "True Positive Rate"
    ) +
    ggplot2::xlim(0, 1) +
    ggplot2::ylim(0, 1) +
    ggplot2::coord_equal() +
    theme_manuscript()

  # Single black series - already greyscale-safe with no colour/linetype
  # mapping needed. Still routed through save_figure() for the 600 dpi
  # TIFF + vector PDF that journal submission requires.
  save_figure(p, output_folder, "roc_curve.png", width = 7, height = 5)
}

.save_dual_roc_plot <- function(y1, p1, y2, p2, y3 = NULL, p3 = NULL,
                                label1 = "Iannuzzi 2020",
                                label2 = "mFI-5",
                                label3 = "sVQI-FS",
                                auc1   = NA_real_,
                                auc2   = NA_real_,
                                auc3   = NA_real_,
                                output_folder) {
  has_third <- !is.null(y3) && !is.null(p3)

  if (length(unique(y1)) < 2 && length(unique(y2)) < 2 &&
      (!has_third || length(unique(y3)) < 2)) return(NULL)

  build_roc_df <- function(y, p, label) {
    if (length(unique(y)) < 2) return(NULL)
    p <- pmin(pmax(p, 0.0001), 0.9999)
    roc_obj <- pROC::roc(response = y, predictor = p, quiet = TRUE)
    data.frame(
      fpr   = 1 - roc_obj$specificities,
      tpr   = roc_obj$sensitivities,
      model = label,
      stringsAsFactors = FALSE
    )
  }

  df1 <- build_roc_df(y1, p1, label1)
  df2 <- build_roc_df(y2, p2, label2)
  df3 <- if (has_third) build_roc_df(y3, p3, label3) else NULL
  roc_df <- do.call(rbind, Filter(Negate(is.null), list(df1, df2, df3)))
  if (is.null(roc_df) || nrow(roc_df) == 0) return(NULL)

  # Compute AUCs for subtitle
  fmt_auc <- function(y, p, override) {
    if (!is.na(override)) return(round(as.numeric(override), 3))
    if (length(unique(y)) < 2) return(NA_real_)
    p <- pmin(pmax(p, 0.0001), 0.9999)
    round(as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE))), 3)
  }
  auc1_val <- fmt_auc(y1, p1, auc1)
  auc2_val <- fmt_auc(y2, p2, auc2)

  subtitle <- paste0(
    label1, " AUROC = ", ifelse(is.na(auc1_val), "N/A", auc1_val),
    "   |   ",
    label2, " AUROC = ", ifelse(is.na(auc2_val), "N/A", auc2_val)
  )

  # Greyscale encoding: slots 1-2 (black solid/longdash, filled circle/
  # triangle) are the same two Iannuzzi slots used on the calibration
  # overlay, so a reader sees the same visual grammar in both figures.
  curve_levels <- c(label1, label2)
  if (has_third && !is.null(df3)) {
    auc3_val <- fmt_auc(y3, p3, auc3)
    subtitle <- paste0(subtitle, "   |   ",
                       label3, " AUROC = ", ifelse(is.na(auc3_val), "N/A", auc3_val))
    curve_levels <- c(curve_levels, label3)
  }

  roc_df$model <- factor(roc_df$model, levels = curve_levels)
  gs <- .gs_scales(curve_levels)

  plt <- ggplot2::ggplot(roc_df, ggplot2::aes(x = fpr, y = tpr,
                                               colour = model, linetype = model)) +
    ggplot2::geom_path(linewidth = 1) +
    # geom_line() is too dense along a smooth ROC curve for point shapes to
    # read cleanly, so points are subsampled onto every 8th row per model -
    # the shape channel is still present without cluttering the curve.
    ggplot2::geom_point(
      data = do.call(rbind, lapply(split(roc_df, roc_df$model), function(d) {
        d[seq(1, nrow(d), by = max(1, floor(nrow(d) / 12))), , drop = FALSE]
      })),
      ggplot2::aes(shape = model), size = 1.6
    ) +
    # Chance line: thin grey, dashed. No model curve above uses "dashed" -
    # slots 1-3 are solid/longdash/dotdash - so this can never be mistaken
    # for a model curve, unlike the old dotted reference line that collided
    # with a dotted model curve on the calibration overlay.
    ggplot2::geom_abline(intercept = 0, slope = 1,
                         linetype = "dashed", colour = "grey70", linewidth = 0.5) +
    gs$colour + gs$linetype + gs$shape +
    ggplot2::labs(
      title    = "Receiver Operating Characteristic Curves",
      subtitle = subtitle,
      x        = "False Positive Rate (1 - Specificity)",
      y        = "True Positive Rate (Sensitivity)"
    ) +
    ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
    ggplot2::coord_equal() +
    theme_manuscript()

  save_figure(plt, output_folder, "roc_curve_dual.png", width = 7, height = 5.5)
}

.save_calibration_plot_from_table <- function(calibration_table_path,
                                              output_folder,
                                              file_name = "calibration_lookup.png",
                                              plot_title = "Calibration Plot") {
  if (!file.exists(calibration_table_path)) {
    return(NULL)
  }

  cal <- read.csv(calibration_table_path, stringsAsFactors = FALSE)
  if (!all(c("predicted", "observed") %in% names(cal))) {
    return(NULL)
  }

  # Single black series - no colour/linetype mapping needed. The reference
  # diagonal is solid grey80 (not dashed) so it never risks being confused
  # with a data series linetype if this helper's output is ever compared
  # side-by-side with the multi-curve .save_dual_calibration_plot() below.
  p <- ggplot2::ggplot(cal, ggplot2::aes(x = predicted, y = observed)) +
    ggplot2::geom_point(size = 2) +
    ggplot2::geom_line() +
    ggplot2::geom_abline(intercept = 0, slope = 1, colour = "grey80") +
    ggplot2::labs(
      title = plot_title,
      x = "Mean predicted risk",
      y = "Observed event rate"
    ) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::coord_equal() +
    theme_manuscript()

  save_figure(p, output_folder, file_name, width = 5, height = 5)
}

.save_calibration_plot_from_vectors <- function(y,
                                                p,
                                                output_folder,
                                                file_name,
                                                plot_title,
                                                n_bins = 10) {
  ok <- !(is.na(y) | is.na(p))
  y <- as.numeric(y[ok])
  p <- as.numeric(p[ok])

  if (length(y) < 10 || length(unique(y)) < 2) {
    return(NULL)
  }

  p <- pmin(pmax(p, 0.0001), 0.9999)
  qbreaks <- unique(stats::quantile(p, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE))
  if (length(qbreaks) < 3) {
    qbreaks <- c(0, 1)
  }

  bins <- cut(p, breaks = qbreaks, include.lowest = TRUE)
  cal <- aggregate(
    cbind(predicted = p, observed = y) ~ bins,
    data = data.frame(p = p, y = y, bins = bins),
    FUN = mean
  )

  p_cal <- ggplot2::ggplot(cal, ggplot2::aes(x = predicted, y = observed)) +
    ggplot2::geom_point(size = 2) +
    ggplot2::geom_line() +
    ggplot2::geom_abline(intercept = 0, slope = 1, colour = "grey80") +
    ggplot2::labs(
      title = plot_title,
      x = "Mean predicted risk",
      y = "Observed event rate"
    ) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::coord_equal() +
    theme_manuscript()

  save_figure(p_cal, output_folder, file_name, width = 5, height = 5)
}

.save_dual_calibration_plot <- function(lookup_source  = NULL,
                                        recal_source   = NULL,
                                        mfi5_source    = NULL,
                                        vqifs_source   = NULL,
                                        dist_sources   = NULL,
                                        output_folder,
                                        file_name = "calibration_dual.png") {

  # Helper: coerce a source to a data frame or return NULL.
  .read_cal <- function(src) {
    if (is.null(src)) return(NULL)
    if (is.data.frame(src)) {
      df <- src
    } else if (is.character(src) && file.exists(src)) {
      df <- read.csv(src, stringsAsFactors = FALSE)
    } else {
      return(NULL)
    }
    if (!all(c("predicted", "observed") %in% names(df))) return(NULL)
    df[, c("predicted", "observed")]
  }

  lookup_df <- .read_cal(lookup_source)
  recal_df  <- .read_cal(recal_source)
  mfi5_df   <- .read_cal(mfi5_source)
  vqifs_df  <- .read_cal(vqifs_source)

  if (is.null(lookup_df) && is.null(recal_df) && is.null(mfi5_df) && is.null(vqifs_df)) return(NULL)

  # Build a long-format data frame so ggplot colour/linetype/shape mapping is
  # simple. Slot order (lookup, recal, mfi5, vqifs) matches .gs_series_palette
  # rows 1-4, so "Iannuzzi (Lookup)" is always black/solid/circle whether this
  # is a 2-, 3-, or 4-curve figure.
  curve_levels <- c()
  parts        <- list()
  if (!is.null(lookup_df)) {
    lookup_df$model  <- "Iannuzzi (Lookup)"
    parts[["lookup"]] <- lookup_df
    curve_levels      <- c(curve_levels, "Iannuzzi (Lookup)")
  }
  if (!is.null(recal_df)) {
    recal_df$model   <- "Iannuzzi (Recal.)"
    parts[["recal"]]  <- recal_df
    curve_levels      <- c(curve_levels, "Iannuzzi (Recal.)")
  }
  if (!is.null(mfi5_df)) {
    mfi5_df$model    <- "mFI-5 (Recal.)"
    parts[["mfi5"]]   <- mfi5_df
    curve_levels      <- c(curve_levels, "mFI-5 (Recal.)")
  }
  if (!is.null(vqifs_df)) {
    vqifs_df$model   <- "sVQI-FS (Recal.)"
    parts[["vqifs"]]  <- vqifs_df
    curve_levels      <- c(curve_levels, "sVQI-FS (Recal.)")
  }
  cal_long       <- do.call(rbind, parts)
  cal_long$model <- factor(cal_long$model, levels = curve_levels)
  gs             <- .gs_scales(curve_levels)

  plot_title <- if (length(curve_levels) >= 4)
    "NHD Risk Score Calibration: four model specifications"
  else if (length(curve_levels) >= 3)
    "NHD Risk Score Calibration: three model specifications"
  else
    "Iannuzzi 2020: Calibration (lookup vs. recalibration)"

  # --- Optional marginal risk-distribution strip -----------------------------
  # Standard addition to a calibration figure (cf. rms::val.prob): shows how
  # much of the cohort actually sits at each predicted-risk value, since a
  # calibration curve computed from a handful of patients in a bin (as is the
  # case here - some bins hold under 10 patients, see calibration_table_*.csv)
  # can look deceptively smooth. Drawn as one row per model, sharing the
  # calibration panel's x-axis, and stacked underneath with patchwork.
  dist_df <- NULL
  if (!is.null(dist_sources)) {
    key_to_model <- c(lookup = "Iannuzzi (Lookup)", recal = "Iannuzzi (Recal.)",
                       mfi5 = "mFI-5 (Recal.)", vqifs = "sVQI-FS (Recal.)")
    dist_parts <- list()
    for (key in names(dist_sources)) {
      model_name <- key_to_model[[key]]
      if (is.null(model_name) || !(model_name %in% curve_levels)) next
      src <- dist_sources[[key]]
      risk_col <- if (key == "lookup") "predicted_risk_lookup" else "predicted_risk_recalibrated"
      risks <- if (is.numeric(src)) {
        src
      } else if (is.character(src) && file.exists(src)) {
        df <- read.csv(src, stringsAsFactors = FALSE)
        if (risk_col %in% names(df)) df[[risk_col]] else NULL
      } else NULL
      if (is.null(risks)) next
      risks <- risks[!is.na(risks)]
      if (length(risks) == 0) next
      dist_parts[[key]] <- data.frame(predicted_risk = risks, model = model_name,
                                      stringsAsFactors = FALSE)
    }
    if (length(dist_parts) > 0) {
      dist_df       <- do.call(rbind, dist_parts)
      dist_df$model <- factor(dist_df$model, levels = curve_levels)
    }
  }

  # Data-driven square axis limits (shared with every other calibration plot
  # in the repo - see .calibration_axis_limits() in R/figure_style.R for why
  # the old fixed [0, 1] panel was replaced).
  #
  # The per-patient risks in dist_df MUST be included, not just the calibration
  # table values. The table holds bin MEANS, so individual patients routinely
  # sit outside its range - in this cohort the lookup table spans 0.111-0.643
  # while individual predicted risks reach 0.745. Sizing the axis on the table
  # alone put those patients outside the scale limits, and because both panels
  # share these limits, ggplot silently DROPPED them from the distribution
  # strip ("Removed 2 rows containing missing values"). That is the one panel
  # whose entire job is showing where patients are, and the dropped ones were
  # the highest-risk patients in the cohort.
  ax          <- .calibration_axis_limits(c(cal_long$predicted, cal_long$observed,
                                            dist_df$predicted_risk))
  axis_lims   <- ax$limits
  axis_breaks <- ax$breaks
  pad         <- ax$pad

  # Layout quantities derived from the series count, so the figure adapts to a
  # 2-, 3- or 4-curve run instead of only looking right at 4 (see the legend
  # and figure-height comments below).
  n_series    <- length(curve_levels)
  legend_rows <- if (n_series <= 2L) 1L else 2L

  p <- ggplot2::ggplot(cal_long,
         ggplot2::aes(x = predicted, y = observed,
                      colour = model, linetype = model, shape = model)) +
    ggplot2::geom_line() +
    ggplot2::geom_point(size = 2) +
    .calibration_reference_line() +
    gs$colour + gs$linetype + gs$shape +
    ggplot2::labs(
      title    = plot_title,
      x        = "Mean predicted NHD risk",
      y        = "Observed NHD rate"
    ) +
    ggplot2::annotate("text",
                      x = axis_lims[2] - pad, y = axis_lims[1] + pad,
                      label    = "Overestimates risk",
                      hjust    = 1,
                      size     = 3,
                      colour   = "grey40",
                      fontface = "italic") +
    ggplot2::annotate("text",
                      x = axis_lims[1] + pad, y = axis_lims[2] - pad,
                      label    = "Underestimates risk",
                      hjust    = 0,
                      size     = 3,
                      colour   = "grey40",
                      fontface = "italic") +
    ggplot2::scale_x_continuous(limits = axis_lims, breaks = axis_breaks) +
    ggplot2::scale_y_continuous(limits = axis_lims, breaks = axis_breaks) +
    theme_manuscript() +
    # aspect.ratio = 1 makes the panel square BY CONSTRUCTION, for any number
    # of curves and any figure height. coord_equal() would do the same but
    # pins panel width to panel height, which stops patchwork stretching the
    # panel to match the distribution strip below and puts the two x-axes out
    # of register (see the combined branch below). aspect.ratio constrains
    # height from the layout-assigned width instead, so alignment survives.
    ggplot2::theme(aspect.ratio = 1) +
    # Legend rows scale with the series count. Three or four labels as long as
    # "sVQI-FS (Recal.)" overflow the 5.5in width on one row and the last is
    # clipped mid-word; one or two fit fine, and forcing them onto two rows
    # would leave a half-empty legend block padding out the figure.
    ggplot2::guides(
      colour   = ggplot2::guide_legend(nrow = legend_rows, byrow = TRUE),
      linetype = ggplot2::guide_legend(nrow = legend_rows, byrow = TRUE),
      shape    = ggplot2::guide_legend(nrow = legend_rows, byrow = TRUE)
    )


  if (is.null(dist_df)) {
    # Standalone panel: coord_equal() makes it exactly square, so the
    # perfect-calibration diagonal renders at a true 45 degrees. Safe here
    # because there is no second panel that needs its x-axis aligned to this
    # one (see the combined branch below for why that matters).
    save_figure(p + ggplot2::coord_equal(),
                output_folder, file_name, width = 5.5, height = 5.5)
  } else {
    # shape = "|" character glyph (ASCII 124): a rug tick per patient, one row
    # per model, sharing the calibration panel's x-axis and greyscale colour.
    dist_panel <- ggplot2::ggplot(dist_df,
                     ggplot2::aes(x = predicted_risk, y = model, colour = model)) +
      ggplot2::geom_point(shape = 124, size = 3, alpha = 0.5,
                         show.legend = FALSE) +
      gs$colour +
      ggplot2::scale_x_continuous(limits = axis_lims, breaks = axis_breaks) +
      ggplot2::scale_y_discrete(limits = rev(curve_levels)) +
      ggplot2::labs(x = "Predicted NHD risk (distribution)", y = NULL) +
      theme_manuscript() +
      ggplot2::theme(
        legend.position   = "none",
        panel.grid.minor  = ggplot2::element_blank(),
        axis.text.y       = ggplot2::element_text(size = 7)
      )

    # Figure height is DERIVED from the series count, not a fixed number
    # tuned against one dataset. The calibration panel is square by
    # construction (aspect.ratio = 1 above), so the only things that vary with
    # the number of curves are the legend block and the strip's row count -
    # both linear in n_series. A hardcoded height only produced a square panel
    # at exactly 4 curves; at 2 it left a band of dead whitespace.
    #
    # Constants are inches of vertical furniture at 5.5in width, measured from
    # rendered output: title ~0.40, x-axis + label ~0.55, one legend row ~0.26,
    # one strip row ~0.30, strip axis + label ~0.60. The square panel takes
    # whatever width remains after the y-axis furniture (~0.9in).
    panel_h  <- 5.5 - 0.9
    legend_h <- 0.26 * legend_rows
    strip_h  <- 0.30 * n_series + 0.60
    upper_h  <- 0.40 + panel_h + 0.55 + legend_h
    fig_h    <- upper_h + strip_h

    combined <- patchwork::wrap_plots(p, dist_panel, ncol = 1,
                                      heights = c(upper_h, strip_h))
    save_figure(combined, output_folder, file_name, width = 5.5, height = fig_h)
  }
}

.build_table1 <- function(df) {
  border_h  <- officer::fp_border(color = "#BFBFBF", width = 0.5)
  border_out <- officer::fp_border(color = "#1F3864", width = 1.5)

  ft <- flextable(df) |>
    set_header_labels(
      variable    = "Variable",
      points      = "Points",
      lookback    = "Lookback Window",
      omop_domain = "OMOP Domain",
      derivation  = "OMOP Derivation Method"
    ) |>
    bold(part = "header") |>
    fontsize(size = 10, part = "all") |>
    font(fontname = "Calibri", part = "all") |>
    width(j = "variable",    width = 1.5) |>
    width(j = "points",      width = 0.55) |>
    width(j = "lookback",    width = 0.85) |>
    width(j = "omop_domain", width = 1.1) |>
    width(j = "derivation",  width = 3.0) |>
    align(j = "points",   align = "center", part = "all") |>
    align(j = "lookback", align = "center", part = "all") |>
    bg(part = "header", bg = "#1F3864") |>
    color(part = "header", color = "white") |>
    hline(border = border_h, part = "body") |>
    border_outer(border = border_out, part = "all") |>
    set_table_properties(layout = "fixed") |>
    padding(padding = 4, part = "all")

  ft
}

.strip_heading_autonumbering <- function(docx_path) {
  if (!file.exists(docx_path)) return(invisible(docx_path))

  work_dir <- tempfile("docx_renumber_")
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)

  ok <- tryCatch({
    utils::unzip(docx_path, exdir = work_dir)
    styles_path <- file.path(work_dir, "word", "styles.xml")
    if (!file.exists(styles_path)) stop("word/styles.xml not found in archive")

    xml <- paste(readLines(styles_path, warn = FALSE, encoding = "UTF-8"),
                 collapse = "\n")

    # Heading style IDs differ by template locale: Titre* (officer's default
    # French template) and Heading* / heading* (English templates).
    heading_ids <- c("Titre1", "Titre2", "Titre3",
                     "Heading1", "Heading2", "Heading3",
                     "heading1", "heading2", "heading3")

    n_stripped <- 0L
    for (sid in heading_ids) {
      # Match the full <w:style ...styleId="sid"> ... </w:style> block, then
      # drop any <w:numPr>...</w:numPr> inside it. Non-greedy so adjacent style
      # definitions are not swallowed.
      pattern <- paste0("(<w:style[^>]*w:styleId=\"", sid, "\".*?</w:style>)")
      m <- regmatches(xml, regexpr(pattern, xml, perl = TRUE))
      if (length(m) == 0 || !grepl("<w:numPr>", m[1], fixed = TRUE)) next
      replacement <- gsub("<w:numPr>.*?</w:numPr>", "", m[1], perl = TRUE)
      xml <- sub(pattern, replacement, xml, perl = TRUE)
      n_stripped <- n_stripped + 1L
    }

    if (n_stripped == 0L) {
      message("[report] No heading auto-numbering found to strip.")
      return(TRUE)
    }

    writeLines(xml, styles_path, useBytes = TRUE)

    # Rezip. utils::zip() needs to run from the archive root so the stored
    # paths stay relative (word/..., _rels/..., [Content_Types].xml).
    old_wd <- setwd(work_dir)
    on.exit(setwd(old_wd), add = TRUE)
    entries <- list.files(".", recursive = TRUE, all.files = TRUE, no.. = TRUE)
    rc <- utils::zip(zipfile = "rebuilt.docx", files = entries, flags = "-q -X")
    setwd(old_wd)
    if (rc != 0) stop("zip returned status ", rc)

    file.copy(file.path(work_dir, "rebuilt.docx"), docx_path, overwrite = TRUE)
    message("[report] Stripped template heading auto-numbering from ",
            n_stripped, " heading style(s).")
    TRUE
  }, error = function(e) {
    message("[report] Could not strip heading auto-numbering (non-fatal): ",
            conditionMessage(e))
    FALSE
  })

  invisible(docx_path)
}
