# Code for stat_density_ridges based on stat_density_common in the "extending ggplot2" vignette

#' Stat for density ridgeline plots
#'
#' This stat is the default stat used by [`geom_density_ridges`]. It is very similar to [`stat_density`],
#' however there are a few differences. Most importantly, the density bandwidth is chosen across
#' the entire dataset.
#'
#' @param geom The geometric object to use to display the data.
#' @param bandwidth Bandwidth used for density calculation. If not provided, is estimated from the data.
#' @param from,to The left and right-most points of the grid at which the density is to be estimated,
#'   as in [`density()`]. If not provided, there are estimated from the data range and the bandwidth.
#' @param calc_ecdf If `TRUE`, `stat_density_ridges` calculates an empirical cumulative distribution function (ecdf)
#'   and returns a variable `ecdf` and a variable `quantile`. Both can be mapped onto aesthetics via
#'   `..ecdf..` and `..quantile..`, respectively.
#' @param quantiles Sets the number of quantiles the data should be broken into if `calc_ecdf = TRUE`.
#' If it is an integer then the data will be cut into that many equal quantiles.
#' If it is a vector of probabilities then the ecdf will cut by them.
#' @inheritParams geom_ridgeline
#' @importFrom ggplot2 layer
#' @examples
#' # Examples of coloring by ecdf or quantiles
#' library(viridis)
#' ggplot(iris, aes(x=Sepal.Length, y=Species, fill=factor(..quantile..))) +
#'   geom_density_ridges_gradient(calc_ecdf = TRUE, quantiles = 5) +
#'   scale_fill_viridis(discrete = TRUE, name = "Quintiles") + theme_ridges() +
#'   scale_y_discrete(expand = c(0.01, 0))
#'
#' ggplot(iris, aes(x=Sepal.Length, y=Species, fill=0.5 - abs(0.5-..ecdf..))) +
#'   geom_density_ridges_gradient(calc_ecdf = TRUE) +
#'   scale_fill_viridis(name = "Tail probability", direction = -1) + theme_ridges() +
#'   scale_y_discrete(expand = c(0.01, 0))
#'
#' ggplot(iris, aes(x=Sepal.Length, y=Species, fill=factor(..quantile..))) +
#'   geom_density_ridges_gradient(calc_ecdf = TRUE, quantiles = c(0.05, 0.95)) +
#'   scale_fill_manual(name = "Probability\nranges",
#'                     values = c("red", "grey80", "blue")) +
#'   theme_ridges() + scale_y_discrete(expand = c(0.01, 0))
#'
#' @export
stat_density_ridges <- function(mapping = NULL, data = NULL, geom = "density_ridges",
                     position = "identity", na.rm = FALSE, show.legend = NA,
                     inherit.aes = TRUE, bandwidth = NULL, from = NULL, to = NULL,
                     calc_ecdf = FALSE, quantiles = 4,...)
{
  layer(
    stat = StatDensityRidges,
    data = data,
    mapping = mapping,
    geom = geom,
    position = position,
    show.legend = show.legend,
    inherit.aes = inherit.aes,
    params = list(bandwidth = bandwidth,
                  from = from,
                  to = to,
                  calc_ecdf = calc_ecdf,
                  quantiles = quantiles,
                  na.rm = na.rm, ...)
  )
}


#' @rdname stat_density_ridges
#' @format NULL
#' @usage NULL
#' @importFrom ggplot2 ggproto Stat
#' @export
StatDensityRidgesOld <- ggproto("StatDensityRidgesOld", Stat,
  required_aes = "x",
  default_aes = aes(height = ..density..),

  calc_panel_params = function(data, params) {
    if (is.null(params$bandwidth)) {
      xdata <- na.omit(data.frame(x=data$x, group=data$group))
      xs <- split(xdata$x, xdata$group)
      xs_mask <- vapply(xs, length, numeric(1)) > 1
      bws <- vapply(xs[xs_mask], bw.nrd0, numeric(1))
      bw <- mean(bws, na.rm = TRUE)
      message("Picking joint bandwidth of ", signif(bw, 3))

      params$bandwidth <- bw
    }

    if (is.null(params$from)) {
      params$from <- min(data$x, na.rm=TRUE) - 3 * params$bandwidth
    }

    if (is.null(params$to)) {
      params$to <- max(data$x, na.rm=TRUE) + 3 * params$bandwidth
    }

    data.frame(
      bandwidth = params$bandwidth,
      from = params$from,
      to = params$to
    )
  },

  setup_params = function(self, data, params) {
    # calculate bandwidth, min, and max for each panel separately
    panels <- split(data, data$PANEL)
    pardata <- lapply(panels, self$calc_panel_params, params)
    pardata <- reduce(pardata, rbind)

    if (is.null(params$calc_ecdf)) {
      params$calc_ecdf <- FALSE
    }

    if (is.null(params$quantiles)) {
      params$quantiles <- 5
    }

    if (length(params$quantiles) > 1 &&
       (max(params$quantiles, na.rm = TRUE) > 1 || min(params$quantiles, na.rm = TRUE) < 0)) {
         stop('invalid quantiles used: c(', paste0(params$quantiles, collapse = ','), ') must be within [0, 1] range')
    }

    list(
      bandwidth = pardata$bandwidth,
      from = pardata$from,
      to = pardata$to,
      calc_ecdf = params$calc_ecdf,
      quantiles = params$quantiles,
      na.rm = params$na.rm
    )
  },

  compute_group = function(data, scales, from, to, bandwidth = 1,
                           calc_ecdf = FALSE, quantiles = 5) {
    # ignore too small groups
    if(nrow(data) < 3) return(data.frame())

    panel <- unique(data$PANEL)
    if (length(panel) > 1) {
      stop("Error: more than one panel in compute group; something's wrong.")
    }
    panel_id <- as.numeric(panel)

    d <- density(data$x, bw = bandwidth[panel_id], from = from[panel_id], to = to[panel_id], na.rm = TRUE)

    if(is.null(calc_ecdf)) calc_ecdf <- FALSE

    if (calc_ecdf) {
      n <- length(d$x)
      ecdf <- c(0, cumsum(d$y[1:(n-1)]*(d$x[2:n]-d$x[1:(n-1)])))

      if (length(quantiles)==1 && quantiles >= 1) {
        ntile <- 1 + floor(quantiles * ecdf)
        ntile[ntile>quantiles] <- quantiles
      }
      else {
        ntile <- cut(ecdf,
                     unique(c(min(ecdf, na.rm = TRUE), quantiles, max(ecdf, na.rm = TRUE))),
                     include.lowest = TRUE, right = TRUE)
      }

      data.frame(
        x = d$x,
        density = d$y,
        ecdf = ecdf,
        quantile = ntile
      )
    }
    else {
      data.frame(x = d$x, density = d$y)
    }
  }
)


# experimental version that calculates additional items
#' @rdname stat_density_ridges
#' @format NULL
#' @usage NULL
#' @importFrom ggplot2 ggproto Stat
#' @export
StatDensityRidges <- ggproto("StatDensityRidges", Stat,
  required_aes = "x",

  default_aes = aes(height = ..density..),

  calc_panel_params = function(data, params) {
    if (is.null(params$bandwidth)) {
      xdata <- na.omit(data.frame(x=data$x, group=data$group))
      xs <- split(xdata$x, xdata$group)
      xs_mask <- vapply(xs, length, numeric(1)) > 1
      bws <- vapply(xs[xs_mask], bw.nrd0, numeric(1))
      bw <- mean(bws, na.rm = TRUE)
      message("Picking joint bandwidth of ", signif(bw, 3))

      params$bandwidth <- bw
    }

    if (is.null(params$from)) {
      params$from <- min(data$x, na.rm=TRUE) - 3 * params$bandwidth
    }

    if (is.null(params$to)) {
      params$to <- max(data$x, na.rm=TRUE) + 3 * params$bandwidth
    }

    data.frame(
      bandwidth = params$bandwidth,
      from = params$from,
      to = params$to
    )
  },

  setup_params = function(self, data, params) {
    # calculate bandwidth, min, and max for each panel separately
    panels <- split(data, data$PANEL)
    pardata <- lapply(panels, self$calc_panel_params, params)
    pardata <- reduce(pardata, rbind)

    if (is.null(params$calc_ecdf)) {
      params$calc_ecdf <- FALSE
    }

    if (is.null(params$jittered_points)) {
      params$jittered_points <- FALSE
    }

    if (is.null(params$quantile_lines)) {
      params$quantile_lines <- FALSE
    }

    if (is.null(params$quantiles)) {
      params$quantiles <- 4
    }

    if (length(params$quantiles) > 1 &&
        (max(params$quantiles, na.rm = TRUE) > 1 || min(params$quantiles, na.rm = TRUE) < 0)) {
      stop('invalid quantiles used: c(', paste0(params$quantiles, collapse = ','), ') must be within [0, 1] range')
    }

    list(
      bandwidth = pardata$bandwidth,
      from = pardata$from,
      to = pardata$to,
      calc_ecdf = params$calc_ecdf,
      jittered_points = params$jittered_points,
      quantile_lines = params$quantile_lines,
      quantiles = params$quantiles,
      na.rm = params$na.rm
    )
  },

  compute_group = function(data, scales, from, to, bandwidth = 1,
                           calc_ecdf = FALSE, jittered_points = FALSE, quantile_lines = FALSE,
                           quantiles = 4, points_scaling_range = c(0.02, 0.98)) {
    # ignore too small groups
    if(nrow(data) < 3) return(data.frame())

    if (is.null(calc_ecdf)) calc_ecdf <- FALSE
    if (is.null(jittered_points)) jittered_points <- FALSE
    if (is.null(quantile_lines)) quantile_lines <- FALSE

    panel <- unique(data$PANEL)
    if (length(panel) > 1) {
      stop("Error: more than one panel in compute group; something's wrong.")
    }
    panel_id <- as.numeric(panel)

    d <- density(data$x, bw = bandwidth[panel_id], from = from[panel_id], to = to[panel_id], na.rm = TRUE)

    # make interpolating function for density line
    densf <- approxfun(d$x, d$y, rule = 2)

    # calculate jittered original points if requested
    if (jittered_points) {
      df_jittered <- data.frame(x = data$x,
        density = (points_scaling_range[1]+diff(points_scaling_range)*runif(length(data$x)))*densf(data$x),
        datatype = "point", stringsAsFactors = FALSE)

      # see if we need to carry over other point data
      # capture all data columns starting with "point", as those are relevant for point aesthetics
      df_points <- data[grepl("point_", names(data))]

      # uncomment following line to switch off carrying over data
      #df_points <- data.frame()

      if (ncol(df_points) == 0) {
        df_points <- NULL
        df_points_dummy <- NULL
      }
      else {
        # combine additional points data into results dataframe
        df_jittered <- cbind(df_jittered, df_points)
        # make a row of dummy data to merge with the other dataframes
        df_points_dummy <- na.omit(df_points)[1, , drop = FALSE]
      }
    } else {
      df_jittered <- NULL
      df_points_dummy <- NULL
    }

    # calculate quantiles for quantile lines if requested
    df_quantiles <- NULL
    if (quantile_lines) {
      if (length(quantiles)==1) {
        if (quantiles > 1) {
          probs <- seq(0, 1, length.out = quantiles + 1)[2:quantiles]
        }
        else {
          probs <- NA
        }
      } else {
        probs <- quantiles
        probs[probs < 0 | probs > 1] <- NA
      }

      qx <- na.omit(quantile(data$x, probs))
      if (length(qx) > 0) {
        qy <- densf(qx)
        df_quantiles <- data.frame(x = qx, density = qy, datatype = "stud",
                                   stringsAsFactors = FALSE)
        if (!is.null(df_points_dummy)){
          # add in dummy points data if necessary
          df_quantiles <- data.frame(df_quantiles, as.list(df_points_dummy))
        }
      }
    }

    # combine the quantiles and jittered points data frames into one, the non-density frame
    df_nondens <- rbind(df_quantiles, df_jittered)

    if (calc_ecdf) {
      n <- length(d$x)
      ecdf <- c(0, cumsum(d$y[1:(n-1)]*(d$x[2:n]-d$x[1:(n-1)])))

      if (length(quantiles)==1 && quantiles >= 1) {
        ntile <- 1 + floor(quantiles * ecdf)
        ntile[ntile>quantiles] <- quantiles
      }
      else {
        ntile <- cut(ecdf,
                     unique(c(min(ecdf, na.rm = TRUE), quantiles, max(ecdf, na.rm = TRUE))),
                     include.lowest = TRUE, right = TRUE)
      }

      if (!is.null(df_nondens)) {
        # we add dummy data for ecdf and quantile
        # if we don't do this, the autogenerated legend can be off
        df_nondens <- data.frame(df_nondens, ecdf = ecdf[1], quantile = ntile[1])
      }

      df_density <- data.frame(
        x = d$x,
        density = d$y,
        ecdf = ecdf,
        quantile = ntile,
        datatype = "ridgeline",
        stringsAsFactors = FALSE
      )
    }
    else {
      df_density <- data.frame(x = d$x, density = d$y, datatype = "ridgeline", stringsAsFactors = FALSE)
    }

    if (!is.null(df_points_dummy)){
      # add in dummy points data if necessary
      df_density <- data.frame(df_density, as.list(df_points_dummy))
    }

    # now combine everything and return
    rbind(df_density, df_nondens)
  }
)

#' Stat for histogram ridgeline plots
#'
#' Works like `stat_bin` except that the output is a ridgeline describing the histogram rather than
#' a set of counts.
#'
#' @param draw_baseline If `FALSE`, removes lines along 0 counts. Defaults to `TRUE`.
#' @param pad If `TRUE`, adds empty bins at either end of x. This ensures that the binline always goes
#'   back down to 0. Defaults to `TRUE`.
#' @inheritParams ggplot2::stat_bin
#'
#' @examples
#' ggplot(iris, aes(x = Sepal.Length, y = Species, group = Species, fill = Species)) +
#'   geom_density_ridges(stat = "binline", bins = 20, scale = 2.2) +
#'   scale_y_discrete(expand = c(0.01, 0)) +
#'   scale_x_continuous(expand = c(0.01, 0)) +
#'   theme_ridges()
#'
#' ggplot(iris, aes(x = Sepal.Length, y = Species, group = Species, fill = Species)) +
#'   stat_binline(bins = 20, scale = 2.2, draw_baseline = FALSE) +
#'   scale_y_discrete(expand = c(0.01, 0)) +
#'   scale_x_continuous(expand = c(0.01, 0)) +
#'   scale_fill_grey() +
#'   theme_ridges() + theme(legend.position = 'none')
#'
#' require(ggplot2movies)
#' require(viridis)
#' ggplot(movies[movies$year>1989,], aes(x = length, y = year, fill = factor(year))) +
#'    stat_binline(scale = 1.9, bins = 40) +
#'    theme_ridges() + theme(legend.position = "none") +
#'    scale_x_continuous(limits = c(1, 180), expand = c(0.01, 0)) +
#'    scale_y_reverse(expand = c(0.01, 0)) +
#'    scale_fill_viridis(begin = 0.3, discrete = TRUE, option = "B") +
#'    labs(title = "Movie lengths 1990 - 2005")
#'
#' count_data <- data.frame(group = rep(letters[1:5], each = 10),
#'                          mean = rep(1:5, each = 10))
#' count_data$group <- factor(count_data$group, levels = letters[5:1])
#' count_data$count <- rpois(nrow(count_data), count_data$mean)
#' ggplot(count_data, aes(x = count, y = group, group = group)) +
#'   geom_density_ridges2(stat = "binline", aes(fill = group), binwidth = 1, scale = 0.95) +
#'   geom_text(stat = "bin",
#'           aes(y = group+0.9*..count../max(..count..),
#'           label = ifelse(..count..>0, ..count.., "")),
#'           vjust = 1.2, size = 3, color = "white", binwidth = 1) +
#'   theme_ridges(grid = FALSE) +
#'   scale_x_continuous(breaks = c(0:12), limits = c(-.5, 13), expand = c(0, 0)) +
#'   scale_y_discrete(expand = c(0.01, 0)) +
#'   scale_fill_cyclical(values = c("#0000B0", "#7070D0")) +
#'   guides(y = "none")
#' @export
stat_binline <- function(mapping = NULL, data = NULL,
                     geom = "density_ridges", position = "identity",
                     ...,
                     binwidth = NULL,
                     bins = NULL,
                     center = NULL,
                     boundary = NULL,
                     breaks = NULL,
                     closed = c("right", "left"),
                     pad = TRUE,
                     draw_baseline = TRUE,
                     na.rm = FALSE,
                     show.legend = NA,
                     inherit.aes = TRUE) {

  layer(
    data = data,
    mapping = mapping,
    stat = StatBinline,
    geom = geom,
    position = position,
    show.legend = show.legend,
    inherit.aes = inherit.aes,
    params = list(
      binwidth = binwidth,
      bins = bins,
      center = center,
      boundary = boundary,
      breaks = breaks,
      closed = closed,
      pad = pad,
      draw_baseline = draw_baseline,
      na.rm = na.rm,
      ...
    )
  )
}


#' @rdname stat_binline
#' @format NULL
#' @usage NULL
#' @importFrom ggplot2 ggproto StatBin
#' @export
StatBinline <- ggproto("StatBinline", StatBin,
  required_aes = "x",

  default_aes = aes(height = ..density..),

  setup_params = function(data, params) {
    # provide default value if not given, happens when stat is called from a geom
    if (is.null(params$pad)) {
      params$pad <- TRUE
    }

    # provide default value if not given, happens when stat is called from a geom
    if (is.null(params$draw_baseline)) {
      params$draw_baseline <- TRUE
    }

    if (!is.null(params$boundary) && !is.null(params$center)) {
      stop("Only one of `boundary` and `center` may be specified.", call. = FALSE)
    }

    if (is.null(params$breaks) && is.null(params$binwidth) && is.null(params$bins)) {
      message("`stat_binline()` using `bins = 30`. Pick better value with `binwidth`.")
      params$bins <- 30
    }

    params
  },

  compute_group = function(self, data, scales, binwidth = NULL, bins = NULL,
                           center = NULL, boundary = NULL,
                           closed = c("right", "left"), pad = TRUE,
                           breaks = NULL, origin = NULL, right = NULL,
                           drop = NULL, width = NULL, draw_baseline = TRUE) {
    binned <- ggproto_parent(StatBin, self)$compute_group(data = data,
                  scales = scales, binwidth = binwidth,
                  bins = bins, center = center, boundary = boundary,
                  closed = closed, pad = pad, breaks = breaks)

    result <- rbind(transform(binned, x=xmin), transform(binned, x=xmax-0.00001*width))
    result <- result[order(result$x), ]

    # remove zero counts if requested
    if (!draw_baseline) {
      zeros <- result$count == 0
      protected <- (zeros & !c(zeros[2:length(zeros)], TRUE)) | (zeros & !c(TRUE, zeros[1:length(zeros)-1]))
      to_remove <- zeros & !protected
      result$count[to_remove] <- NA
      result$density[to_remove] <- NA
    }

    result
  }

)
