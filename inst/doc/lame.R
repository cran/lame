## ----include = FALSE----------------------------------------------------------
# the models run when the tarball is built; R CMD check re-knits only the text
run_vignette <- !nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))
if (!run_vignette) knitr::knit_hooks$set(evaluate.inline = function(code, envir) "")
knitr::opts_chunk$set(
	fig.retina = 1,
	collapse = TRUE,
	comment = "#>",
	fig.width = 6,
	fig.height = 4,
	dpi = 72,
	out.width = "100%",
	fig.align = "center",
	eval = run_vignette
)

## ----netify-bridge, eval = FALSE----------------------------------------------
# library(netify)
# library(lame)
# 
# netlet <- netify::netify(
# 	edges_long,
# 	actor1 = "from",
# 	actor2 = "to",
# 	time = "year",
# 	weight = "tie",
# 	dyad_vars = "distance",
# 	output_format = "longit_list",
# 	missing_to_zero = FALSE
# )
# 
# fit <- lame(netlet, family = "binary", R = 2, verbose = FALSE)

## ----quick-start, message=FALSE-----------------------------------------------
library(lame)
set.seed(6886)

# three periods of a 25-actor directed network driven by a dyadic covariate
n <- 25; T_periods <- 3
true_intercept <- -1.0
true_beta <- 0.7

# zero-padded names keep the input order under the alphabetical actor sort;
# matching dimnames on Y and every covariate array keep them aligned
actor_names <- sprintf("N%02d", seq_len(n))

X_list <- lapply(seq_len(T_periods), function(t) {
	# [actor x actor x covariate] array; the slice name labels the coefficient
	x <- matrix(rnorm(n * n), n, n)
	array(
		x,
		dim = c(n, n, 1),
		dimnames = list(actor_names, actor_names, "similarity")
	)
})
Y_list <- lapply(seq_len(T_periods), function(t) {
	# probit ties: tie probability pnorm(intercept + beta * x)
	eta <- true_intercept + true_beta * X_list[[t]][, , 1]
	Y <- matrix(rbinom(n * n, 1, pnorm(eta)), n, n)
	diag(Y) <- NA # self-ties are undefined in a unipartite network
	rownames(Y) <- colnames(Y) <- actor_names
	Y
})

# longitudinal AME model with the similarity covariate
fit <- lame(
	Y = Y_list,
	Xdyad = X_list, # one similarity matrix per period
	R = 2, # 2D latent space
	family = "binary", # probit for 0/1 networks
	burn = 20, # short burn-in for this example
	nscan = 100, # short run for this example
	odens = 5, # thinning
	verbose = FALSE, # no progress output
	plot = FALSE # no live diagnostic plots during sampling
)

summary(fit)

## ----s3-methods---------------------------------------------------------------
# regression coefficients (posterior means)
coef(fit)

# 95% credible intervals
confint(fit)

# one row per coefficient; works with or without broom loaded
tidy(fit)

# one-row model summary; elpd_loo is NA unless a loo result is cached on the fit
glance(fit)

# predicted tie probabilities: a list with one n x n matrix per period
Y_hat <- predict(fit, type = "response")
length(Y_hat) # 3, one matrix per period
dim(Y_hat[[1]]) # 25 x 25
cat(
	"Predicted probability range:",
	round(range(unlist(Y_hat), na.rm = TRUE), 3),
	"\n"
)

# residuals, observed minus predicted, in the same shape
resid_list <- residuals(fit)
cat("Residual SD:", round(sd(unlist(resid_list), na.rm = TRUE), 3), "\n")

## ----trace-plot, fig.height=5, fig.alt="MCMC trace and density plots for the regression coefficients (intercept and similarity_dyad); well-mixed traces and unimodal densities indicate adequate convergence."----
trace_plot(fit, params = "beta")

## ----gof-plot, fig.width=8, fig.height=5, fig.alt="Longitudinal goodness-of-fit panels: each facet plots one network statistic (sender/receiver degree heterogeneity, dyadic dependence, triadic dependence, transitivity) across time. The observed series is a solid black line with points; the posterior-predictive median is a dashed grey line; the 95 percent credible interval is a grey band."----
gof_plot(fit)

## ----uv-plot, fig.width=7, fig.height=6, fig.alt="Circular-layout latent-space plot: each actor's sender position is a triangle and receiver position a circle on concentric rings; actors placed near each other share similar tie patterns."----
uv_plot(fit)

## ----ab-plot, fig.height=4, fig.alt="Lollipop plot of sender effects, sorted by posterior mean; each actor is a stem from zero to its point estimate, with positive values marking unusually active senders. In this null example all stems are short and reflect sampling noise, not planted heterogeneity."----
ab_plot(fit, effect = "sender")

## ----cross-sectional, message=FALSE-------------------------------------------
fit_cs <- ame(
	Y = Y_list[[1]], # just one time period
	Xdyad = X_list[[1]], # n x n x 1 similarity array
	R = 2,
	family = "binary",
	burn = 20,
	nscan = 100,
	odens = 5,
	verbose = FALSE
)

coef(fit_cs)

## ----dynamic, message=FALSE---------------------------------------------------
fit_dyn <- lame(
	Y = Y_list,
	Xdyad = X_list,
	R = 2,
	dynamic_ab = TRUE, # time-varying sociality/popularity
	dynamic_uv = TRUE, # time-varying latent positions
	family = "binary",
	burn = 20,
	nscan = 100,
	odens = 5,
	verbose = FALSE,
	plot = FALSE
)

summary(fit_dyn)

## ----bipartite, message=FALSE-------------------------------------------------
set.seed(42) # reproducible simulation
nA <- 15; nB <- 10
row_names <- sprintf("R%02d", seq_len(nA))
col_names <- sprintf("C%02d", seq_len(nB))
X_bip <- lapply(1:3, function(t) {
	x <- matrix(rnorm(nA * nB), nA, nB)
	array(
		x,
		dim = c(nA, nB, 1),
		dimnames = list(row_names, col_names, "similarity")
	)
})
Y_bip <- lapply(1:3, function(t) {
	eta <- -0.8 + 0.6 * X_bip[[t]][, , 1]
	Y <- matrix(rbinom(nA * nB, 1, pnorm(eta)), nA, nB)
	rownames(Y) <- row_names; colnames(Y) <- col_names
	Y
})

fit_bip <- lame(
	Y = Y_bip,
	Xdyad = X_bip,
	mode = "bipartite",
	R = 2,
	family = "binary",
	burn = 20,
	nscan = 100,
	odens = 5,
	verbose = FALSE,
	plot = FALSE
)

summary(fit_bip)

## ----checkpoint-demo, eval = FALSE--------------------------------------------
# ck <- tempfile(fileext = ".rds")
# fit1 <- lame(
# 	Y = Y_list,
# 	Xdyad = X_list,
# 	R = 2,
# 	family = "binary",
# 	nscan = 5000,
# 	burn = 200,
# 	odens = 25,
# 	chains = 1, # a checkpoint is one chain
# 	max_seconds = 30, # stop after 30 s wall clock
# 	checkpoint_path = ck, # write state here
# 	verbose = FALSE
# )
# if (isTRUE(fit1$terminated_early)) {
# 	# 2,000 more sweeps, keeping every 25th
# 	fit2 <- lame(resume_from = ck, nscan = 2000)
# }

