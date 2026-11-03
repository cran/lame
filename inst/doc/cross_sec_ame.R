## ----setup, include = FALSE---------------------------------------------------
# the models run when the tarball is built; R CMD check re-knits only the text
run_vignette <- !nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))
if (!run_vignette) knitr::knit_hooks$set(evaluate.inline = function(code, envir) "")
knitr::opts_chunk$set(
	fig.retina = 1,
	dpi = 72,
	collapse = TRUE,
	comment = "#>",
	fig.align = "center",
	eval = run_vignette
)

## ----load-data----------------------------------------------------------------
library(lame)
library(ggplot2)
set.seed(6886)

# load the Add Health friendship network
data(addhealthc3)

# binary friendship: any nomination counts
Y <- (addhealthc3$Y > 0) * 1
X_nodes <- addhealthc3$X

n <- nrow(Y)
cat("Students:", n, "\n")
cat("Friendships:", sum(Y, na.rm = TRUE), "\n")
cat("Network density:", round(mean(Y, na.rm = TRUE), 3), "\n")

## ----viz-network, fig.width=10, fig.height=4, fig.alt="Two faceted histograms showing the distribution of nominations sent and nominations received per student in the Add Health friendship network, illustrating heterogeneity in sociality and popularity."----
out_degree <- rowSums(Y, na.rm = TRUE)
in_degree <- colSums(Y, na.rm = TRUE)

degree_df <- data.frame(
	Degree = c(out_degree, in_degree),
	Type = rep(c("Nominations sent", "Nominations received"), each = n)
)

ggplot(degree_df, aes(x = Degree)) +
	geom_histogram(binwidth = 1) +
	facet_wrap(~Type, ncol = 2) +
	labs(x = "Number of ties", y = "Count") +
	theme_bw() +
	theme(
		panel.border = element_blank(),
		axis.line = element_blank(),
		axis.ticks = element_blank(),
		legend.position = "top",
		plot.title = element_text(hjust = 0),
		plot.subtitle = element_text(hjust = 0),
		plot.caption = element_text(hjust = 0),
		strip.background = element_rect(fill = "black", color = "black"),
		strip.text = element_text(color = "white", hjust = 0)
	)

## ----create-covariates--------------------------------------------------------
# outer() compares every pair of students: 1 if they share the attribute, 0 if not
same_female <- outer(X_nodes[, "female"], X_nodes[, "female"], "==") * 1
same_race <- outer(X_nodes[, "race"], X_nodes[, "race"], "==") * 1
same_grade <- outer(X_nodes[, "grade"], X_nodes[, "grade"], "==") * 1
# absolute grade difference, a continuous covariate
grade_diff <- abs(outer(X_nodes[, "grade"], X_nodes[, "grade"], "-"))

# stack into an n x n x p array
Xdyad <- array(NA, dim = c(n, n, 4))
Xdyad[, , 1] <- same_female
Xdyad[, , 2] <- same_race
Xdyad[, , 3] <- same_grade
Xdyad[, , 4] <- grade_diff
dimnames(Xdyad)[[3]] <- c('same_female', 'same_race', 'same_grade', 'grade_diff')
for (k in 1:4) diag(Xdyad[, , k]) <- NA

# nodal covariates (sender and receiver characteristics)
Xrow <- X_nodes[, c("female", "grade")]
Xcol <- X_nodes[, c("female", "grade")]

## ----fit-model, message=FALSE, warning=FALSE----------------------------------
fit <- ame(
	Y,
	Xdyad = Xdyad,
	Xrow = Xrow,
	Xcol = Xcol,
	R = 2, # 2D latent space
	family = "binary", # probit model for 0/1 data
	rvar = TRUE, # sender random effects
	cvar = TRUE, # receiver random effects
	dcor = TRUE, # dyadic correlation (reciprocity)
	burn = 100, # short burn-in for this example
	nscan = 500, # short run for this example
	odens = 25, # thinning
	verbose = FALSE,
	posterior_opts = posterior_options(
		save_ab = TRUE, save_UV = TRUE,
		thin_ab = 1, thin_UV = 1
	),
	gof = TRUE
)

## ----print-summary------------------------------------------------------------
summary(fit)

## ----trace-plots, fig.width=8, fig.height=6.5, dpi=55, fig.alt="MCMC trace and density plots for each regression coefficient; stable traces fluctuate around a steady mean and the density plots are smooth and unimodal."----
trace_plot(fit, params = "beta", ncol = 3)

## ----trace-rho, fig.width=8, fig.height=5, fig.alt="MCMC trace and density plot for the dyadic correlation (rho); the trace should fluctuate around a stable mean."----
trace_plot(fit, params = "variance", include = "Dyadic correlation")

## ----as-draws-rhat-ess, eval = run_vignette && requireNamespace("posterior", quietly = TRUE), message = FALSE, warning = FALSE----
library(posterior)
draws <- posterior::as_draws(fit) # draws_array [iter, chain, var]
# mean, sd, quantiles, rhat and ESS for each parameter
posterior::summarise_draws(draws)

## ----ame-chains, eval = FALSE-------------------------------------------------
# # four longer chains for a convergence assessment
# fit_mc <- ame(
# 	Y,
# 	Xdyad = Xdyad,
# 	Xrow = Xrow,
# 	Xcol = Xcol,
# 	family = "binary",
# 	R = 2,
# 	burn = 1000,
# 	nscan = 5000,
# 	odens = 25,
# 	chains = 4,
# 	cores = 4, # forked on Unix; sequential on Windows
# 	verbose = FALSE
# )
# posterior::summarise_draws(posterior::as_draws(fit_mc))

## ----mh-counters--------------------------------------------------------------
str(fit$mh_counters)

## ----prior-summary-cross------------------------------------------------------
prior_summary(fit)

## ----loo-cross, eval = FALSE--------------------------------------------------
# # two candidates with independent residuals and saved log-likelihoods
# fit_ll <- ame(
# 	Y,
# 	Xdyad = Xdyad,
# 	Xrow = Xrow,
# 	Xcol = Xcol,
# 	family = "binary",
# 	R = 2,
# 	dcor = FALSE,
# 	burn = 1000,
# 	nscan = 5000,
# 	odens = 25,
# 	save_log_lik = TRUE,
# 	verbose = FALSE
# )
# 
# # alternative model without the dyadic covariates
# fit_ll_null <- ame(
# 	Y,
# 	Xrow = Xrow,
# 	Xcol = Xcol,
# 	family = "binary",
# 	R = 2,
# 	dcor = FALSE,
# 	burn = 1000,
# 	nscan = 5000,
# 	odens = 25,
# 	save_log_lik = TRUE,
# 	verbose = FALSE
# )
# 
# loo_dyad <- loo::loo(fit_ll)
# loo_null <- loo::loo(fit_ll_null)
# 
# loo_dyad # check the Pareto k table first
# 
# loo::loo_compare(list(with_dyad = loo_dyad, no_dyad = loo_null))

## ----gof-plot, fig.width=10, fig.height=6, fig.alt="Goodness-of-fit panels comparing observed network statistics (dashed black vertical line) against the posterior predictive histograms (grey) for sender and receiver degree heterogeneity, dyadic dependence, triadic dependence, and transitivity."----
gof_plot(fit)

## ----custom-gof---------------------------------------------------------------
# clustering coefficient: transitive triples over two-paths
trans_ratio <- function(Y) {
	Yb <- Y; Yb[is.na(Yb)] <- 0 # missing ties count as 0
	YY <- Yb %*% Yb
	triangles <- sum(YY * Yb) # transitive triples
	two_path <- sum(YY) - sum(diag(YY)) # two-paths (potential triangles)
	c(trans_ratio = triangles / max(two_path, 1))
}

gof_custom <- gof(fit, custom_gof = trans_ratio, nsim = 50, verbose = FALSE)
obs <- gof_custom[1, "trans_ratio"]
sim <- gof_custom[-1, "trans_ratio"]

# posterior predictive p-value (right tail): near 0 means under-predicted
c(
	observed = round(obs, 3),
	sim_mean = round(mean(sim), 3),
	pp_p_right = round(mean(sim >= obs), 3)
)

## ----latent-space, fig.width=8, fig.height=6, fig.alt="Biplot of the estimated 2D latent space: triangles mark each student's sender position and circles mark receiver positions on the two latent dimensions; students plotted near each other have similar friendship patterns beyond what the covariates explain."----
uv_plot(fit, layout = "biplot", show.edges = FALSE, label.nodes = FALSE)

## ----individual-effects, fig.width=10, fig.height=8, fig.alt="Two stacked lollipop charts showing the posterior-mean sender effect (sociality) and receiver effect (popularity) for each student as a point connected by a stem to a dashed zero line, sorted from the most negative effect on the left to the most positive on the right; positive values sit above the line and negative below."----
p1 <- ab_plot(
	fit,
	effect = "sender",
	sorted = TRUE,
	title = "Sender effects (sociality)"
)
p2 <- ab_plot(
	fit,
	effect = "receiver",
	sorted = TRUE,
	title = "Receiver effects (popularity)"
)

library(patchwork)
p1 / p2

## ----predictions--------------------------------------------------------------
pred_resp <- predict(fit, type = "response")

# observed and predicted ties as vectors
Y_vec <- as.vector(Y)
pred_vec <- as.vector(pred_resp)
keep <- !is.na(Y_vec)

# classification at a 0.5 threshold
pred_binary <- (pred_vec[keep] > 0.5) * 1
confusion <- table(Actual = Y_vec[keep], Predicted = pred_binary)
knitr::kable(confusion, caption = "Confusion matrix (threshold = 0.5)")

accuracy <- sum(diag(confusion)) / sum(confusion)
baseline <- max(mean(Y_vec[keep]), 1 - mean(Y_vec[keep])) # accuracy of always predicting the modal class
cat(
	"\nAccuracy:",
	round(accuracy, 3),
	" | Baseline (predict modal class):",
	round(baseline, 3),
	" | Lift:",
	round(accuracy - baseline, 3),
	"\n"
)

## ----auc-eval, eval = run_vignette && requireNamespace("pROC", quietly = TRUE) && requireNamespace("precrec", quietly = TRUE)----
# AUROC with pROC
roc_obj <- pROC::roc(
	response = Y_vec[keep],
	predictor = pred_vec[keep],
	quiet = TRUE
)
auroc <- as.numeric(pROC::auc(roc_obj))

# ROC and precision-recall AUCs with precrec; PR-AUC suits rare ties
ev <- precrec::evalmod(scores = pred_vec[keep], labels = Y_vec[keep])
precrec::auc(ev) # AUROC and PR-AUC side by side

cat(
	"AUROC:",
	round(auroc, 3),
	"\n",
	"Baseline AUROC (random ranker):",
	0.5,
	"\n",
	"Baseline PR-AUC (density of Y):",
	round(mean(Y_vec[keep]), 3),
	"\n"
)

## ----heldout------------------------------------------------------------------
# 80/20 stratified mask of off-diagonal dyads
set.seed(6886)
off_diag <- which(row(Y) != col(Y) & !is.na(Y))
pos_idx <- off_diag[Y[off_diag] == 1]
neg_idx <- off_diag[Y[off_diag] == 0]
test_idx <- c(
	sample(pos_idx, round(0.2 * length(pos_idx))),
	sample(neg_idx, round(0.2 * length(neg_idx)))
)

Y_train <- Y
Y_train[test_idx] <- NA # mask test dyads from the likelihood

fit_train <- ame(
	Y_train,
	Xdyad = Xdyad,
	Xrow = Xrow,
	Xcol = Xcol,
	R = 2,
	family = "binary",
	rvar = TRUE,
	cvar = TRUE,
	dcor = TRUE,
	burn = 30,
	nscan = 100,
	odens = 5, # short run for the vignette
	verbose = FALSE,
	gof = FALSE
)

pred_train <- predict(fit_train, type = "response")

# evaluate_heldout() scores the predictions on a logical test mask
test_mask <- matrix(
	FALSE,
	nrow(Y),
	ncol(Y),
	dimnames = dimnames(Y)
)
test_mask[test_idx] <- TRUE
heldout_metrics <- evaluate_heldout(
	y_obs = Y,
	y_pred = pred_train,
	mask = test_mask,
	family = "binary"
)
heldout_metrics
cat(
	"Test dyads:",
	length(test_idx),
	" | positives:",
	sum(Y[test_idx] == 1),
	"\n"
)

## ----simulation, fig.width=8, fig.height=4, fig.alt="Posterior predictive check histogram of simulated network densities with a dashed vertical line marking the observed density. Overlap indicates the model reproduces the observed density."----
sims <- simulate(fit, nsim = 100)

# simulated and observed densities
sim_densities <- sapply(sims$Y, function(y) mean(y, na.rm = TRUE))
obs_density <- mean(Y, na.rm = TRUE)

ggplot(data.frame(density = sim_densities), aes(x = density)) +
	geom_histogram(bins = 20) +
	geom_vline(
		xintercept = obs_density,
		linewidth = 1,
		linetype = "dashed"
	) +
	labs(
		title = "Posterior predictive check: network density",
		subtitle = "Dashed line = observed; histogram = simulated from the model",
		x = "Network density (mean tie probability)", y = "Replicate count"
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

