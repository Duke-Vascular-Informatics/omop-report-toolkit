% Hand-written, not roxygen2-generated - see NAMESPACE's header comment for
% why (no roxygen2/devtools in the authoring dev container). If you change
% theme_manuscript()'s signature in R/figure_style.R, update this file to
% match by hand.
\name{theme_manuscript}
\alias{theme_manuscript}
\title{Shared ggplot2 theme for manuscript figures}
\usage{
theme_manuscript(base_size = 9)
}
\arguments{
\item{base_size}{Base font size in points. Defaults to 9, sized for a single
journal column at final print scale (ggplot2's own default is tuned for
on-screen viewing, not print).}
}
\value{
A ggplot2 theme object, meant to be added to a plot with \code{+}.
}
\description{
A thin wrapper over \code{ggplot2::theme_minimal()} with the legend pinned
to the bottom, since every greyscale overlay figure in this package carries
a legend (shape + linetype key) rather than relying on colour alone.
}
\seealso{
\code{\link{save_figure}}, and \code{.gs_scales()} in
\code{R/figure_style.R} for the palette this theme is meant to be paired
with.
}
