## ----setup, include = FALSE---------------------------------------------------
# the models run when the tarball is built; R CMD check re-knits only the text
run_vignette <- !nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))
if (!run_vignette) knitr::knit_hooks$set(evaluate.inline = function(code, envir) "")
knitr::opts_chunk$set(
	fig.retina = 1,
	dpi = 72,
	collapse = TRUE,
	comment = "#>",
	eval = run_vignette
)
library(lame)

## ----first-fit----------------------------------------------------------------
set.seed(1)
n <- 40
a <- rnorm(n, 0, 0.5); b <- rnorm(n, 0, 0.5)
u <- rnorm(n, 0, 0.8); v <- rnorm(n, 0, 0.8) # a rank-one latent term
Xd <- matrix(rnorm(n * n), n, n)
Y <- 0.5 + 0.8 * Xd + outer(a, b, "+") + tcrossprod(u, v) + matrix(rnorm(n * n), n, n)
diag(Y) <- NA

fit <- ame_als(Y, Xdyad = Xd, R = 1, family = "normal", verbose = FALSE)
fit

## ----first-fit-truth----------------------------------------------------------
round(cbind(truth = c(0.5, 0.8), estimate = coef(fit), confint(fit)), 3)
round(fit$VC, 3)

## ----rank---------------------------------------------------------------------
ev <- sapply(
	0:3,
	function(r)
		ame_als(
			Y,
			Xdyad = Xd,
			R = r,
			family = "normal",
			verbose = FALSE
		)$eb$log_marginal
)
data.frame(R = 0:3, log_marginal = round(ev - ev[1], 1))

## ----poisson------------------------------------------------------------------
set.seed(4)
nc <- 30
xc <- matrix(rnorm(nc * nc), nc, nc)
ac <- rnorm(nc, 0, 0.7); bc <- rnorm(nc, 0, 0.7)
Yc <- matrix(
	rpois(
		nc * nc,
		exp(
			-0.3 + 0.5 * xc + outer(ac, bc, "+") +
				rnorm(nc * nc, 0, 0.6)
		)
	),
	nc,
	nc
)
# one actor sends no counts and another receives none
Yc[2, ] <- 0; Yc[, 5] <- 0
diag(Yc) <- NA
fc <- ame_als(Yc, Xdyad = xc, R = 0, family = "poisson", verbose = FALSE)
round(cbind(estimate = coef(fc), confint(fc)), 3)
round(c(ve = fc$VC[["ve"]], sender_2 = fc$a[[2]], receiver_5 = fc$b[[5]]), 2)

## ----binary-------------------------------------------------------------------
set.seed(2)
nb <- 80
ab <- rnorm(nb, 0, 0.5); bb <- rnorm(nb, 0, 0.5)
Xb <- matrix(rnorm(nb * nb), nb, nb)
Yb <- 1 * (0.8 * Xb + outer(ab, bb, "+") + matrix(rnorm(nb * nb), nb, nb) > 0)
diag(Yb) <- NA
fb <- ame_als(Yb, Xdyad = Xb, R = 0, family = "binary", verbose = FALSE)
round(cbind(truth = c(0, 0.8), estimate = coef(fb), confint(fb)), 3)

## ----bootstrap----------------------------------------------------------------
bt <- ame_als_bootstrap(
	fb,
	R = 30,
	type = "parametric",
	seed = 1,
	verbose = FALSE
)
summary(bt)

## ----posterior----------------------------------------------------------------
fit_mcmc <- ame(
	Yb,
	Xdyad = Xb,
	family = "binary",
	R = 0,
	start_vals = als_start_vals(fb),
	burn = 200,
	nscan = 1000,
	odens = 5,
	verbose = FALSE,
	plot = FALSE,
	gof = FALSE,
	seed = 1
)

# estimates and 95 percent intervals from the three sources
terms <- names(coef(fb))
cmp <- rbind(
	data.frame(
		estimator = "Fast fit, Laplace",
		term = terms,
		estimate = unname(coef(fb)),
		lower = confint(fb)[terms, 1],
		upper = confint(fb)[terms, 2]
	),
	data.frame(
		estimator = "Fast fit, bootstrap",
		term = terms,
		estimate = unname(coef(fb)),
		lower = confint(bt)[terms, 1],
		upper = confint(bt)[terms, 2]
	),
	data.frame(
		estimator = "Sampler posterior",
		term = terms,
		estimate = unname(coef(fit_mcmc)[terms]),
		lower = confint(fit_mcmc)[terms, 1],
		upper = confint(fit_mcmc)[terms, 2]
	)
)
rownames(cmp) <- NULL
cbind(cmp[, 1:2], round(cmp[, 3:5], 3))

## ----posterior-plot, fig.width = 7, fig.height = 3, fig.alt = "Coefficient plot for the binary network. The intercept and the dyadic slope each have three horizontal intervals, one for the Laplace interval of the fast fit, one for its bootstrap interval and one for the posterior interval of the sampler. Within each coefficient the three intervals nearly coincide."----
library(ggplot2)
ggplot(
	cmp,
	aes(
		x = estimate,
		y = term,
		shape = estimator
	)
) +
	geom_pointrange(
		aes(xmin = lower, xmax = upper),
		position = position_dodge(width = 0.5),
		size = 0.5
	) +
	labs(
		x = "Coefficient (probit scale)",
		y = NULL,
		shape = NULL
	) +
	theme_bw() +
	theme(
		panel.border = element_blank(),
		axis.line = element_blank(),
		axis.ticks = element_blank(),
		legend.position = "top"
	)

## ----panel--------------------------------------------------------------------
data(YX_bin_list)
Yl <- lapply(YX_bin_list$Y, function(y) 1 * (y > 0))
lf <- lame_als(Yl, Xdyad = YX_bin_list$X, R = 2, family = "binary", verbose = FALSE)
round(cbind(estimate = coef(lf), confint(lf)), 3)

## ----dynamic------------------------------------------------------------------
set.seed(7)
nn <- 30; Tn <- 8
nmn <- paste0("a", sprintf("%02d", 1:nn))
# an actor level plus an AR(1) deviation in each period
ar1_paths <- function() {
	level <- rnorm(nn, 0, 0.6)
	dev <- matrix(0, nn, Tn)
	dev[, 1] <- rnorm(nn, 0, 0.3 / sqrt(1 - 0.7^2))
	for (t in 2:Tn) dev[, t] <- 0.7 * dev[, t - 1] + rnorm(nn, 0, 0.3)
	level + dev
}
an <- ar1_paths(); bn <- ar1_paths()
xn <- lapply(
	seq_len(Tn),
	function(t)
		array(rnorm(nn * nn), c(nn, nn, 1), dimnames = list(nmn, nmn, "x"))
)
Yn <- lapply(seq_len(Tn), function(t) {
	m <- 0.3 + 0.7 * xn[[t]][, , 1] + outer(an[, t], bn[, t], "+") +
		matrix(rnorm(nn * nn, 0, 0.8), nn)
	diag(m) <- NA
	dimnames(m) <- list(nmn, nmn)
	m
})
fn <- lame(
	Yn,
	Xdyad = xn,
	family = "normal",
	method = "als",
	dynamic_ab = TRUE,
	verbose = FALSE
)
round(confint(fn)["x_dyad", ], 3)
round(c(ve = fn$VC[["ve"]]), 2)
# estimated sender and receiver paths against the generating ones
round(c(sender = cor(c(fn$a_dynamic), c(an)), receiver = cor(c(fn$b_dynamic), c(bn))), 3)

