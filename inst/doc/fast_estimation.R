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

## ----benchmark_self, eval = FALSE---------------------------------------------
# set.seed(1)
# n <- 100
# Y <- matrix(rnorm(n * n), n, n)
# diag(Y) <- NA
# rownames(Y) <- colnames(Y) <- paste0("a", sprintf("%03d", 1:n))
# 
# t_als <- system.time(
# 	fit_als <- ame_als(Y, R = 2, family = "normal", verbose = FALSE)
# )
# stopifnot(fit_als$converged)
# t_mcmc <- system.time(
# 	fit_mcmc <- ame(
# 		Y,
# 		R = 2,
# 		family = "normal",
# 		burn = 500,
# 		nscan = 2000,
# 		odens = 1,
# 		seed = 1,
# 		verbose = FALSE,
# 		plot = FALSE
# 	)
# )
# packageVersion("lame")
# data.frame(
# 	method = c("ALS", "MCMC: 2500 iterations"),
# 	elapsed_seconds = c(t_als["elapsed"], t_mcmc["elapsed"])
# )

## -----------------------------------------------------------------------------
set.seed(1)
n <- 40
a <- rnorm(n, 0, 0.5); b <- rnorm(n, 0, 0.5)
u <- rnorm(n, 0, 0.8); v <- rnorm(n, 0, 0.8) # a rank-one latent term
Xd <- matrix(rnorm(n * n), n, n)
Y <- 0.5 + 0.8 * Xd + outer(a, b, "+") + tcrossprod(u, v) + matrix(rnorm(n * n), n, n)
diag(Y) <- NA

fit <- ame_als(Y, Xdyad = Xd, R = 1, family = "normal", verbose = FALSE)
fit

## ----normal-eb----------------------------------------------------------------
round(cbind(estimate = coef(fit), se = fit$eb$se), 3)
round(fit$VC, 3)

## -----------------------------------------------------------------------------
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

## ----poisson-eb---------------------------------------------------------------
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
round(c(coef(fc), ve = fc$VC[["ve"]]), 3)
round(c(sender = fc$a[2], receiver = fc$b[5]), 2)
fx <- tryCatch(
	ame_als(
		Yc,
		Xdyad = xc,
		R = 0,
		family = "poisson",
		bias_correct = "none",
		verbose = FALSE
	),
	lame_als_convergence = function(e) e
)
class(fx)[1]
fx$state$termination

## -----------------------------------------------------------------------------
set.seed(2)
nb <- 80
ab <- rnorm(nb, 0, 0.5); bb <- rnorm(nb, 0, 0.5)
Xb <- matrix(rnorm(nb * nb), nb, nb)
Yb <- 1 * (0.8 * Xb + outer(ab, bb, "+") + matrix(rnorm(nb * nb), nb, nb) > 0)
diag(Yb) <- NA
fb <- ame_als(Yb, Xdyad = Xb, R = 0, family = "binary", verbose = FALSE)
coef(fb)
fb$bias_correct$method
sqrt(diag(vcov(fb)))

## ----dynamic-eb---------------------------------------------------------------
set.seed(6)
nd <- 30; Td <- 6
nmd <- paste0("a", sprintf("%02d", 1:nd))
ad <- rnorm(nd, 0, 0.6); bd <- rnorm(nd, 0, 0.6)
Yd <- lapply(seq_len(Td), function(t) {
	eta <- -0.6 + outer(ad, bd, "+") + matrix(rnorm(nd * nd, 0, 0.3), nd)
	m <- 1 * (eta + matrix(rnorm(nd * nd), nd) > 0)
	diag(m) <- NA
	dimnames(m) <- list(nmd, nmd)
	m
})
fd <- lame(
	Yd,
	family = "binary",
	method = "als",
	dynamic_ab = TRUE,
	verbose = FALSE
)
fd$bias_correct$method
round(c(rho_ab = fd$rho_ab, sigma_ab = fd$sigma_ab), 2)
fd0 <- lame(
	Yd,
	family = "binary",
	method = "als",
	dynamic_ab = TRUE,
	bias_correct = "none",
	verbose = FALSE
)
round(c(rho_ab = fd0$rho_ab, sigma_ab = fd0$sigma_ab), 2)

## ----dynamic-eb-normal--------------------------------------------------------
set.seed(7)
nn <- 30; Tn <- 6
nmn <- paste0("a", sprintf("%02d", 1:nn))
an <- rnorm(nn, 0, 0.6); bn <- rnorm(nn, 0, 0.6)
xn <- lapply(
	seq_len(Tn),
	function(t)
		array(rnorm(nn * nn), c(nn, nn, 1), dimnames = list(nmn, nmn, "x"))
)
Yn <- lapply(seq_len(Tn), function(t) {
	m <- 0.3 + 0.7 * xn[[t]][, , 1] + outer(an, bn, "+") +
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
fn$bias_correct$method
round(cbind(estimate = coef(fn), se = fn$eb$se), 3)
round(c(fn$VC[c("ve", "rho")], rho_ab = fn$rho_ab, sigma_ab = fn$sigma_ab), 3)
fn0 <- lame(
	Yn,
	Xdyad = xn,
	family = "normal",
	method = "als",
	dynamic_ab = TRUE,
	bias_correct = "none",
	verbose = FALSE
)
round(c(rho_ab = fn0$rho_ab, sigma_ab = fn0$sigma_ab), 2)

## ----dynamic-eb-refused-------------------------------------------------------
err <- tryCatch(
	lame(
		Yn,
		Xdyad = xn,
		family = "normal",
		method = "als",
		dynamic_ab = TRUE,
		als_max_iter = 2,
		verbose = FALSE
	),
	lame_als_convergence = function(e) e
)
class(err)[1]
class(err$fit)[1]

## -----------------------------------------------------------------------------
bt <- ame_als_bootstrap(
	fb,
	R = 30,
	type = "parametric",
	seed = 1,
	verbose = FALSE
)
summary(bt)

## ----als-vs-mcmc, fig.width = 7, fig.height = 3.5, fig.alt="Side-by-side coefficient plot comparing the ALS bootstrap and MCMC posterior on the same binary network. Each coefficient (intercept and the single dyadic covariate) has two horizontal intervals: one for the ALS bootstrap, one for the MCMC posterior. A dashed vertical line at zero marks the no-effect reference; intervals on the same side of zero and with overlapping range indicate the two estimators agree."----
# a named covariate slice gives both engines the same coefficient names
Xd_arr <- array(
	Xb,
	dim = c(nrow(Xb), ncol(Xb), 1),
	dimnames = list(NULL, NULL, "Xd")
)

# binary ALS fit with 30 bootstrap replicates
fb_b <- ame_als(
	Yb,
	Xdyad = Xd_arr,
	R = 0,
	family = "binary",
	verbose = FALSE,
	bootstrap = 30,
	bootstrap_seed = 1
)

# MCMC fit on the same data with a short chain
fit_mcmc <- ame(
	Yb,
	Xdyad = Xd_arr,
	family = "binary",
	R = 0,
	burn = 30,
	nscan = 100,
	odens = 5,
	verbose = FALSE,
	plot = FALSE,
	gof = FALSE,
	seed = 1
)

# coefficient estimates and intervals as a data frame
coef_interval_table <- function(fit) {
	est <- coef(fit)
	ci <- confint(fit)
	terms <- intersect(names(est), rownames(ci))
	data.frame(
		term = terms,
		estimate = unname(est[terms]),
		conf.low = unname(ci[terms, 1]),
		conf.high = unname(ci[terms, 2]),
		row.names = NULL
	)
}

als_tdy <- coef_interval_table(fb_b)
mcmc_tdy <- coef_interval_table(fit_mcmc)
df <- rbind(
	cbind(
		estimator = "ALS bootstrap",
		als_tdy[, c("term", "estimate", "conf.low", "conf.high")]
	),
	cbind(
		estimator = "MCMC posterior",
		mcmc_tdy[, c("term", "estimate", "conf.low", "conf.high")]
	)
)

library(ggplot2)
ggplot(
	df,
	aes(
		x = estimate,
		y = term,
		colour = estimator,
		shape = estimator
	)
) +
	geom_vline(xintercept = 0, linetype = "dashed", colour = "grey60") +
	geom_pointrange(
		aes(xmin = conf.low, xmax = conf.high),
		position = position_dodge(width = 0.45),
		size = 0.5
	) +
	scale_colour_manual(
		values = c(
			"ALS bootstrap" = "#377EB8",
			"MCMC posterior" = "#E41A1C"
		)
	) +
	scale_shape_manual(
		values = c(
			"ALS bootstrap" = 16,
			"MCMC posterior" = 17
		)
	) +
	labs(
		x = "Coefficient (probit scale)", y = NULL,
		colour = NULL, shape = NULL
	) +
	theme_bw() +
	theme(
		panel.border = element_blank(),
		axis.line = element_blank(),
		axis.ticks = element_blank(),
		legend.position = "top",
		plot.title = element_text(hjust = 0),
		plot.subtitle = element_text(hjust = 0),
		plot.caption = element_text(hjust = 0)
	)

## -----------------------------------------------------------------------------
set.seed(3)
Yl <- replicate(5, {
	# intercept 0.4 plus sender and receiver effects and noise
	m <- 0.4 + outer(a, b, "+") + matrix(rnorm(n * n), n, n)
	diag(m) <- NA
	m
}, simplify = FALSE)
lf <- lame_als(Yl, R = 1, family = "normal", verbose = FALSE)
coef(lf)

