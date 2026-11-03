# lame 1.4.0

This release supersedes the 1.3.5 development builds published on GitHub; the
changes below are relative to CRAN 1.3.4. Many of the fixes change estimates,
so refit models rather than comparing them with fits saved by 1.3.x.

## Breaking changes

* `ame()` and `lame()` now run two chains by default (`chains = 2`) and
  compare them before they return. `options(lame.chains = k)` changes the
  default, and `chains = 1` runs one chain. `lame()` gains `chains` and
  `cores`; in `ame()`, `n_chains` is the older name of `chains` and `cores`
  now defaults to `NULL`.
  * Chain k is seeded `seed + 1000 * (k - 1)`, so the one-chain fit with the
    same `seed` is the first chain of the two-chain fit.
  * The chains run forked on Unix, on `cores` workers (`options(lame.cores)`,
    otherwise all cores but one), and one after the other on Windows. The
    draws do not depend on the number of cores.
  * A default fit costs 1.8 to 2.2 times the CPU time of one chain and 0.94 to
    1.09 times its wall time on a multicore machine (six configurations).
  * The result is the pooled fit, with `fit$chains`, `fit$chain_seeds`,
    `fit$rhat` and the `chain_indicator` that `as_draws()` and `trace_plot()`
    read.
  * ALS fits and `sampler = "tempered"` run one chain.
  * The pooled fit holds the stored draws of every chain
    (`chains * nscan / odens`).
* Every chain is checked for drift, and the chains are compared with each other.
  A chain that has not settled is extended, and the call is then refused.
  * Drift within a chain: for the intercept (or first coefficient), `va`,
    `vb`, `ve`, `rho`, `rho_ab`, `sigma_ab`, `rho_uv`, `sigma_uv` and
    `pi_snap`, the first and last thirds of the stored draws are compared. A
    quantity is flagged when the two means differ by more than 3 batch-means
    standard errors and by more than half a posterior standard deviation.
  * Between chains: the split rank-normalised R-hat is compared with 1.05.
    The monitored set holds every regression coefficient, the variance
    components and the dynamic hyperparameters. It also holds summaries of
    the additive and latent structure: the rms of the actor effects, the
    largest actor effect, the rms of the latent product, the norm of `G` of
    a bipartite fit and the split of scale between `U` and `V` of a directed
    fit (per period for dynamic fits). Individual dyadic products are not
    monitored.
  * When a chain drifts or an R-hat is above 1.05, every chain is extended
    from its own final state, as `lame_resume()` does, by another block of
    `nscan` sweeps. Up to `prior$chain_extensions` extensions are made
    (default 3, so at most four times `nscan` post-burn sweeps per chain).
    The flagged block is discarded, and `fit$auto_extend` records what was
    run.
  * Chains that are still flagged after the last extension stop the call with
    an error of class `lame_chain_unsettled`. The error carries the chains
    (`e$fits`), the pooled fit of the last block (`e$fit`), the monitored
    table (`e$rhat`) and the offending quantities (`e$moving`).
    `lame_resume(e$fit, nscan_more = N)` continues every chain, and
    `lame_resume(e$fits[[k]], nscan_more = N)` continues one.
  * `prior = list(chain_extensions = 0)` refuses at the first flag, and no
    setting returns a flagged fit. This replaces the warning that a chain
    "was still moving".
  * Measured on stationary chains: the drift check flagged none of 192
    blocks, and 1 of 72 single-chain fits of configurations that settle. On
    112 blocks of two chains from 28 configurations, the largest monitored
    R-hat had a median of 1.007 and a maximum of 1.040. No block was flagged,
    so the 95 percent upper bound on the false-extension rate is 3.2 percent.
  * On the 13 configurations of the replication study, at four seed pairs
    each (52 two-chain fits at the defaults), 47 fits settled as run, 5 were
    extended and none was refused. 47 of the 52 pass the two-chain gate on
    every identified parameter, dyadic products included. The other five sit
    at R-hat 1.04 to 1.08 on a dyadic product or one actor effect, which the
    monitored set leaves out.
  * `ame_parallel()` and `lame_parallel()` are the same call as
    `chains = n_chains`. Their seeds are `seed + 1000 * (k - 1)` (they were
    `seed + 1000 * k`). The gate and the extensions apply, and an unsettled
    call stops with `lame_chain_unsettled`.
* `compute_mcmc_diagnostics()` now reports the between-chain gate's
  statistic. `rhat` is the split rank-normalised R-hat (Vehtari et al. 2021,
  as `posterior::rhat()`), computed on the first `min(n_samples)` draws of
  every chain. The Gelman-Rubin statistic it reported before is now
  `rhat_classic`. The verdict it prints compares `rhat` with 1.05 (it used
  1.1). For `lame_robust` fits, `rhat` is the rank-normalised value (it was
  `rhat_split`) and `rhat_classic` the classic one; `pass` still requires
  both to be below 1.05. The `rhat_max_univariate` column of
  `rhat_dynamic_beta()` uses the same statistic.

* Default fits now keep their additive-effect and latent-factor posterior
  draws (`posterior_opts = NULL`), so post-hoc `gof()`, `gof_temporal()`,
  `simulate(type = "posterior")` and `posterior_quantiles()` work on a default
  fit. Fit objects are larger as a result. Dynamic latent trajectories larger
  than about 100 MB are not kept by default, and a message says how to keep
  them. Use `posterior_opts = posterior_options()` to store no draws.
* Post-hoc `gof()`, `gof_temporal()`, `predict(type = "distribution")` and
  `simulate_posterior(fit, "Y")` need these saved draws. Without them they
  now stop with an error instead of falling back to a conditional
  approximation.
* `simulate()` takes `type = c("posterior", "approximate", "auto")`
  (`"auto"` is an alias of `"posterior"`). A fit without aligned saved draws
  stops with an error of class `lame_simulate_draws` that names
  `type = "approximate"`, the conditional approximation, which now runs only
  when requested. `simulate.lame()` needs `type = "approximate"` for a
  `start_from` other than `"posterior"` and for `n_time` beyond the fitted
  periods (class `lame_simulate_periods`), and the approximation takes
  `newdata$Xdyad` as a list with one array per period (class
  `lame_simulate_xlist`).
* The fitted value of an MCMC Poisson fit (`fit$YPM`, `fitted()`,
  `predict(type = "response")` and `residuals()`, in `ame()` and `lame()`) is
  the mean count `exp(EZ + ve / 2)` at the posterior means of the linear
  predictor and of `ve`, times the period's `period_exposure`: the form the
  fast estimators report. It was the average of the counts replicated at each
  stored draw, whose expectation is infinite under the inverse-gamma prior on
  `ve`, and the one-time message that said so is gone. `predict(newdata = )`,
  forecast points and `prediction_draws_long(type = "response")` use the same
  form. On six simulated fits the new values are 2.7 to 8.5 percent lower on
  average than the old ones; the posterior draws are unchanged. The static
  empirical-Bayes Poisson fit (`ame_als()`, `lame_als()`) reports the same
  plug-in mean (`plug_in = FALSE` gives the mean that integrates the
  predictor, `exp(m + (v + ve) / 2)`, which is not finite in this model for a
  cell the data do not inform).
* `ame()` and `lame()` refuse a regression design that is exactly
  rank-deficient over the observed cells (a covariate that duplicates another
  or combines others, counting the intercept and the sender and receiver
  covariates), in every mode and with `dynamic_beta`, with an error of class
  `lame_design_rank` that names the aliased columns. The fast estimators
  (`ame_als()`, `lame_als()`, `lame(method = "als")`, every estimator and
  family) refuse the same designs with the same condition. The samplers used
  to run on such designs and return the prior along the aliased direction
  (contrast sd up to 2e8). Near-collinear designs are fitted.
* `ame(symmetric = TRUE)` stops with class `lame_symmetric_xdyad` when a dyadic
  covariate slice is not symmetric; the message names the slice and gives
  `(X + t(X)) / 2`. It was a warning that left a regression term that was not
  symmetric. `lame(symmetric = TRUE)` and the ALS fitters refuse an asymmetric
  `Xdyad` the same way; a hole in one triangle of a symmetric covariate is
  mirror-filled in `ame()`, `lame()` and ALS.
* An exactly symmetric `Y` fitted as directed (`symmetric = FALSE`) is an error
  of class `lame_symmetric_y` for a normal response with `dcor = TRUE` in
  `lame()`: the posterior of `rho` is improper once the reciprocal pairs of
  the panel, pooled over the periods, outnumber what the mean parameters absorb
  by four (the bound `ame()` applies; the error also has class
  `lame_improper_normal_reciprocity`). Fit it with `symmetric = TRUE`. Binary,
  Poisson, ordinal and cbin fits are sound (product R-hat at most 1.02), so the
  warning is a message (class `lame_symmetric_y_note`).
* A numerical failure in a sampler step no longer yields a fit with a
  warning: the call stops at the end of the chain with an error of class
  `lame_sampler_failure` whose `health` field holds the counts (0 firings in
  118 fits of the acceptance cells and shipped data). A dynamic binary or
  Poisson fit whose stored predictive draws have a tie rate or mean count off
  the observed one by a factor of 1.5, from 100 stored draws, stops with
  `lame_predictive_level` (0 of 44 fits). The proposals refused at the bounds
  `prior$uv_max_abs` and `prior$G_max` are counted in `fit$sampler_health`;
  removing the bounds changes nothing beyond chain-to-chain noise, and
  `summary()` states the count when it is on 1 percent or more of the sweeps.
* `residuals(type = "pearson")` divides by the family's variance (it divided by
  `sqrt(ve)` for every family); a `frn` fit is refused with class
  `lame_pearson_residuals`. `detect_change_point()` takes the reference of
  each path from the draw's own first state; over 7,800 fits the false positive
  rate at the default threshold of 10 is 1.2 percent on smooth paths and 2.3
  percent on paths drawn from the model, and a step of 1.2 is flagged in 20
  percent of 4- and 5-period panels, 85 percent at 8 and 100 percent at 12.
* `loo()` and `waic()` now need scores that are valid observed-data
  likelihood factors. They are refused for directed fits with `dcor = TRUE`
  (the directed default), for cbin and frn fits, for ordinal fits without
  `ordinal_cutpoints = "explicit"`, for `log_lik_method = "augmented"` and for
  fits saved by earlier versions. For LOO/WAIC on directed models, fit with
  `dcor = FALSE`. Saved scores can still be read with `read_log_lik()`.
* `save_log_lik = TRUE` with the default `log_lik_method = "observed_exact"`
  is refused for cbin, frn and data-induced ordinal fits. Use
  `ordinal_cutpoints = "explicit"`, or the approximate methods
  (`"observed_ghk"` in `lame()`, the new `"observed_approx"` in `ame()`).
* `dynamic_ab = TRUE` now models each actor's effect as a level plus a
  zero-mean AR(1) deviation. `va`, `vb` and `cab` are now the variances of the
  levels, while `rho_ab` and `sigma_ab` describe the deviations, so none of
  them are comparable with 1.3.x values. The levels are returned as
  `fit$a_level` / `fit$b_level`, and `a_dynamic` / `b_dynamic` still hold
  the full effects.
* `lame()` fits with a multiplicative term now report the identified split
  between the latent product and the additive terms. This applies to static
  positions in every family, and to dynamic positions combined with dynamic
  effects in the non-normal families. The row, column and grand means of
  `U G V'` move into the additive effects and the intercept. The reported
  intercept, `APM`, `BPM`, `U`, `V` and `UVPM` change, but the linear
  predictor does not. `fit$U_centered`, `fit$V_centered` and
  `fit$BETA_centered` are removed.
* Default priors changed:
  * The dyadic correlation prior is now proportional to `1 - rho^2` in both
    `ame()` and `lame()`, replacing the arc-sine prior, and every update of
    `rho` in the samplers and the fast estimators reads one shared definition.
    Directed `ame()` fits with `dcor = TRUE` change (the posterior mean of
    `rho` moves by at most 0.005 on typical panels of 70 to 100 actors, by
    0.045 on an 18-actor panel), and `ame()` and a single-period `lame()` now
    return the same posterior of `rho`. `rrho_mh(asp = TRUE)` keeps the
    arc-sine prior.
  * The refusal of directed normal fits whose reciprocal responses are all
    exactly equal (class `"lame_improper_normal_reciprocity"`) now starts from
    an excess of four pairs over the actor/regression bound, where the
    arc-sine prior needed one.
  * The residual-variance prior scale is fixed before sampling. `prior$s20`
    is honored and the scale is recorded in `fit$s2_prior_scale`.
  * The `dynamic_beta` innovation scale is now set from the response scale
    (`fit$sigma_beta_prior_scale`; override with `prior$sigma_beta_scale`).
  * The `sigma_ab` prior scale is fixed (`fit$sigma_ab_prior_scale`; override
    with `prior$sigma_ab_scale`).
  * Gaussian bipartite AR(1) positions use a persistence prior with mean 0.5
    and sd 0.2.
* Data-scaled additive-effect priors are now used for ordinal, cbin and frn
  fits in `lame()`, and for bipartite fits in both `ame()` and `lame()`;
  previously these used a fixed `diag(2)`.
* `ame()` and `lame()` use one prior for the multiplicative effects of a
  directed network (`R > 0`), and so do the empirical-Bayes and penalised fits
  of `ame_als()` and `lame_als()`. The covariance of the stacked factor rows
  `(u_i, v_i)` is inverse-Wishart with scale `Suv0 = s I` and `kappa0` degrees
  of freedom, both read from the data:
  * `s` is the scale of the additive effects that the default `Sab0` also
    reads. For binary fits it is the variance of the actor means of the
    standardised residuals; for ordinal, cbin and frn fits, the same probit
    moments of the ranks; for Poisson fits, the variance of the centred log
    row and column rates; for normal fits, the square root of the mean
    variance of the row and column means of the centred response.
  * `kappa0 = round((2R + 2) m)`. For binary, cbin and frn fits,
    `m = 0.25 / mean(p (1 - p))`, the inverse Bernoulli information of the
    cells, with `p` the probit fit of the additive moments; `m = 1` for the
    other families. A sparse network gets more pseudo-observations at the data
    scale, and `m` depends on the density, not on the number of actors.
  * A `lame()` panel pools its periods, and one period gives the value of
    `ame()`.
  * This is the rule that `ame()` used for binary fits in earlier releases,
    now applied to every family and shared by every estimator. Before,
    `ame()` used family-specific scales and degrees of freedom for the other
    families, and `lame()` used the identity scale with `max(R + 2, 2R)`
    degrees of freedom, so the two samplers fitted different models to the
    same data.
  * `prior$Suv0` and `prior$kappa0` still override the default in `ame()`.
    Symmetric, bipartite and dynamic-position priors are unchanged, and so is
    everything with `R = 0`. Refit saved `R > 0` fits.
* The default priors and starting values of the normal family are written in
  the unit of the response, so a fit of `c * y` is the fit of `y` in other
  units: with the same seed the draws of `ame()`, `lame()` and `lame_robust()`
  for `c * y` equal `c^k` times those for `y` (`k` = 1 for coefficients and
  effects, 2 for variances, 0 for correlations) to 1e-14 for directed and
  bipartite networks and 1e-7 for undirected ones, for `c` from 1e-6 to 1e6;
  the normal empirical-Bayes estimators (static and dynamic, penalised too) and
  the sampler's ALS start agree to 3e-6 or better. Before, the interaction
  matrix of a bipartite network and the weights of an undirected one had
  N(0, 1) priors (at `sd(y)` of 100 the interaction was shrunk to 3 percent of
  its size), the coefficient prior of a static `lame()` fit was
  `n^2 max(1, var(y))`, and the scales of the dynamic priors were absolute.
  Existing normal fits whose response variance is not 1 therefore move: on
  `YX_nrm` (sd 1.5) the coefficients by at most 0.01 posterior standard
  deviations and the rank-2 product by 1.5 percent, on simulated networks of sd
  0.3 and 5 the product by -8 to +25 percent, and on `comtrade` at rank 2 the
  product, which the variance-scaled prior had shrunk, is about 11.5 times
  larger. The prior scale of the factors of a directed normal network is the
  typical size of the additive effects (the square root of their mean
  variance, not the variance). The prior of an initial moving coefficient is
  per unit of its covariate (`prior$beta0_var`, `lambda_beta`; fits of moving
  coefficients with a covariate mean square far from 1 move by up to 0.04); the
  starting slopes of the samplers are divided by their covariate's standard
  deviation, so chains of `x` and `k * x` agree to 1e-15. Fits with `R = 0`,
  and binary, ordinal, cbin, frn and Poisson fits, are unchanged.
* `ame()` on a bipartite network takes `round(4 + 3 nA / 100)` degrees of
  freedom for the additive effects, as `lame()` does, so bipartite `ame()`
  ordinal, Poisson and frn fits change. `prior$Suv0` and `prior$kappa0` are
  an error of class `lame_prior_unused` for a bipartite network (they were
  read by nothing).
* Dynamic latent positions in the non-normal families now cap the
  stationary coordinate variance at 4 (`prior$uv_var_cap`). For the binary,
  ordinal, cbin and frn families, `prior$uv_max_abs` and `prior$G_max`
  default to 8 and 20 instead of 50 and 100; these bounds are stated priors,
  and removing them changes nothing beyond chain-to-chain noise.
* Removed or refused options:
  * `dynamic_G = TRUE` is refused on both the MCMC and ALS routes. With
    moving positions a per-period interaction matrix is not identified apart
    from them; with static positions it is identified but not implemented.
    Use `dynamic_uv = TRUE` and read `fit$UVPM` instead.
  * The development-build switches `prior$bip_uv_gibbs`,
    `prior$uv_hyper_move`, `prior$poisson_scale_move`,
    `prior$beta_hyper_move`, `prior$actor_hyper_move` and `prior$level_move`
    are removed. Each switched an exact update back to the slower one it
    replaced (random-walk rows for the bipartite factors, alternating draws of
    the position persistence and scale, plain residual scaling for Poisson
    fits, hyperparameter draws every 20th sweep, no level/scale move for
    binary fits); the posterior is the same. Passing one now gives the
    unknown-`prior` warning, and the exact update runs.
  * Snap ALS is removed: `lame_snap_als()` and
    `lame(method = "als", dynamic_uv_kind = "snap")` now stop with an error.
  * The `"t"` ALS kind is refused on bipartite panels.
  * MCMC `"snap"` and `"t"` are refused for symmetric fits.
* More combinations stop with an error:
  * `symmetric = TRUE` with cbin or frn;
  * `dynamic_rho` with `dynamic_uv` or with `method = "als"`;
  * bootstrapping a dynamic empirical-Bayes ALS fit of any family (class
    `"lame_dynamic_eb_unsupported"`) or a penalised binary or Poisson dynamic
    fit (class `"lame_als_bootstrap_unsupported"`); `ame_als_bootstrap()`
    checks this before it checks `R`.
* New input checks stop with an error where 1.3.x ran:
  * Poisson responses with non-integer or negative values, in `ame()`,
    `lame()` and the ALS fitters (in 1.3.x these silently froze the latent
    draws);
  * cbin or frn `odmax` values below an actor's observed out-degree;
  * on the ALS route, covariates with a standard deviation above 1e4 (the
    MCMC route accepts any scale; above 100 it suggests rescaling for
    readability);
  * in `lame()`: a constant `Y`, `symmetric = TRUE` with an asymmetric `Y`, a
    `period_exposure` or `time_index` of the wrong length, covariates whose
    slice counts differ across periods, unnamed bipartite slices, and a rank
    too large for the network.
* Normal, binary and Poisson ALS fits (`ame_als()`, `lame_als()`,
  `method = "als"`; static and dynamic) are now fitted by an empirical-Bayes
  estimator by default (the new `bias_correct` argument), so estimates,
  standard errors and variance components change. Refit saved ALS fits. The
  normal-family entries are the last bullets of this list.
  * The sender and receiver effects get the Gaussian prior that `ame()` and
    `lame()` use, with its covariance estimated by EM, and the coefficients
    solve the Laplace-marginal estimating equations. This removes the
    incidental-parameter bias of the fixed-effects fit with a single fit, and
    keeps actors without a tie (for counts, a count) in the fit with finite
    effects. `vcov()` and `confint()` return Laplace standard errors for every
    coefficient, node-covariate coefficients included.
  * Directed, bipartite and undirected networks are covered, at every latent
    rank and for one period or several.
  * `va`, `cab` and `vb` are the fitted covariance of the effects. In a static
    fit, `a` and `b` are not re-centred and the intercept is the population
    intercept; the dynamic estimator centres them as `lame()` does (see
    below). `fit$eb` holds the details.
  * `fitted()`, `predict()` and `residuals()` return predictive probabilities
    (predictive means for counts) that integrate the link over the uncertainty
    of the linear predictor; `plug_in = TRUE` returns the plug-in values.
  * A directed binary fit models the dyadic correlation by default (`dcor`,
    see New features), so its factors no longer absorb reciprocity;
    `dcor = FALSE` fits independent cells.
  * `bias_correct = "none"` returns the fixed-effects fit (on the dynamic
    route, the penalised fit); `"jackknife"` (split-sample) and `"bootstrap"`
    (parametric, static binary fits) correct it on request.
    `bias_correct = "eb"` is an error of class `"lame_als_eb"` for
    `non_normal_method = "transform"` and for families without the estimator.
    `ame_als_refit()` and
    `ame_als_bootstrap()` refit a static empirical-Bayes fit with the same
    estimator.
  * `multistart` keeps the converged start with the lowest value of the
    objective the fit minimises, at that start's own scales: the penalised
    deviance with the actor-effect and factor penalties and their
    hyperpriors, not the raw deviance, which always favours the least-shrunk
    optimum. Fixed-effects IRLS fits with `R > 0` compare their penalised
    deviance the same way. `fit$multistart_deviance` holds each start's
    deviance and `fit$multistart_distance` the distance of its fitted
    predictor from the kept start's, in deviance units. The warning for
    materially different local optima needs a converged start more than one
    deviance unit from the kept start; starts that agree on the fitted values
    do not warn, whatever their objectives. `fit$multistart_coefficients`
    holds the coefficients of every start (the kept start's row is
    `coef(fit)`) and `fit$multistart_product_distance` the relative distance
    of each start's multiplicative surface from the kept start's.
* Dynamic binary ALS fits (`lame(method = "als")` with `dynamic_ab`,
  `dynamic_beta` or `dynamic_uv`) are now empirical-Bayes fits by default;
  they were penalised fits with no correction for finite-sample bias. The
  level covariance, the persistences and the innovation scales are estimated
  by EM under the `lame()` hyperpriors, so `rho_ab`, `sigma_ab`, `rho_uv`,
  `sigma_uv` and `rho_beta` are estimates rather than prior means and
  penalty-implied scales. On simulated panels the slope bias is at most 2.7
  percent, against 4 to 19 percent for the penalised fit.
  * `bias_correct = "none"` restores the penalised fit. Fixing the smoothing
    penalties (`prior$lambda_ab_als`, `prior$lambda_beta_als`,
    `prior$lambda_uv_als`) now needs it: with the default it is an error of
    class `"lame_dynamic_eb_unsupported"`, as is a bootstrap.
  * `fitted()`, `predict(type = "response")` and `residuals()` of the fit
    return the predictive probability, the link integrated over the posterior
    of the predictor (including the additive cavity variance, the product of
    the positions and the coefficients' part at the design asked for), as the
    samplers and the static estimator do; they returned the plug-in
    probability. `plug_in = TRUE` gives it back, `fit$fitted` keeps it, and a
    fit stored without the variance record is refused
    (`lame_predictive_missing`). On 12 simulated panels the predictive
    probability was closer to the truth than the plug-in in 8.
* Dynamic Poisson ALS fits (`dynamic_ab`, `dynamic_beta` or `dynamic_uv`) are
  now empirical-Bayes fits of the Poisson-lognormal model that `lame()`
  samples. The penalised fit they replace fixed `rho_ab` at its prior mean and
  left `ve` at 0.000 on sparse panels.
  * `fit$bias_correct$method` is `"eb"` (it was `"jackknife"` or `"none"`),
    `rho_ab` and `sigma_ab` are estimates, `VC["ve"]` is the noise variance,
    and `EZ` and the intercept are on the latent scale (`fitted()` and
    `predict()` return `exp(EZ + ve / 2)`).
  * `bias_correct = "none"` and `"jackknife"` give the previous fits, except
    that the static factors of the penalised fit now carry a level prior (see
    the penalised bullet under Improvements). Fixing the smoothing penalties needs `"none"`, and a bootstrap is
    refused, as for binary fits.
* Normal ALS fits are empirical-Bayes fits by default, static and dynamic
  (`bias_correct = NULL` is `"eb"` for `family = "normal"`, as for binary and
  Poisson). The estimator is the one of the other families with an exact
  Gaussian cell: at `R = 0` the fit is the posterior mean of the linear
  Gaussian model at its fitted hyperparameters and `vcov()` is its
  generalised-least-squares covariance. The noise variance, the covariance of
  the additive effects and the factor scales are estimated by EM under the
  samplers' priors, and a directed network (`dcor = TRUE`) takes the two cells
  of a dyad as one bivariate normal observation. Against `ame()` and `lame()`
  on 55 simulated networks the coefficients lie within 0.28 posterior standard
  deviations (the fixed-effects fit: 2.19) and the standard errors are 0.91 to
  1.05 times the posterior standard deviations (the conditional sandwich: 0.11
  to 0.87 for the intercept, none for node covariates); 95 percent intervals
  cover 95.2 percent over 4,100 networks. They keep their level beyond four
  periods and 80 actors. On 1,000 simulated panels (40 actors with 8 and 12
  periods at ranks 0 and 2, and 120 actors with 4 periods at rank 2), the
  coverage was 0.943 for the dyadic coefficient, 0.959 and 0.956 for the row
  and column covariates and 0.950 for the intercept (cells 0.915 to 0.975).
  `vcov()` and `confint()` cover every coefficient, `fit$eb$log_marginal`
  chooses the rank (exact at `R = 0`), and
  `bias_correct = "none"` returns the fixed-effects fit of the earlier release
  bit for bit. A directed network whose reciprocal pairs are all exactly equal
  is refused (class `"lame_improper_normal_reciprocity"`; fit it with
  `symmetric = TRUE` or `dcor = FALSE`), as are a response without variation
  (`"lame_als_data"`) and a standard deviation outside 1e-6 to 1e8
  (`"lame_als_scale"`).
* Dynamic normal ALS fits (`dynamic_ab`, `dynamic_beta`, `dynamic_uv`) are
  empirical-Bayes fits of the Gaussian model that `lame()` samples; they were
  penalised fits. The residual variance, the covariance of the levels, the
  persistences and innovation scales (`rho_ab` was the prior mean 0.8) and the
  dyadic correlation are estimated by EM under the `lame()` hyperpriors, the
  coefficients and paths have exact Gaussian marginal standard errors, and
  `fit$bias_correct$method` is `"eb"`. Against 64 chains of `lame()` the
  slopes are within 0.05 posterior standard deviations on average and the
  standard errors are 0.99 to 1.04 times the posterior standard deviations;
  the intercept is reported as `lame()` reports it (next bullet).
  `bias_correct = "none"` restores the penalised fit; fixed smoothness
  penalties, a bootstrap (class `"lame_dynamic_eb_unsupported"`) and a
  constant response are refused by the default.
* The dynamic empirical-Bayes estimator (`lame(method = "als")` with
  `dynamic_ab`, `dynamic_beta` or `dynamic_uv`, every family) reports its
  intercept and additive effects as `lame()` does. Only the sum of the
  intercept and the mean of the additive effects is identified, and `lame()`
  holds the effects at mean zero over the actors. The estimator reported the
  intercept of its own parametrisation, off by the mean of its effects, with
  a standard error 8 to 12 times `lame()`'s.
  * The reported effects (`fit$a_dynamic`, `fit$b_dynamic`, `fit$a_level`,
    `fit$b_level`) have mean zero over the actors, and the intercept carries
    their mean. A moving intercept is shifted by the same constant in every
    period.
  * The standard error and the covariances of the intercept are those of the
    identified combination, from the joint information of the paths, levels
    and coefficients.
  * The intercept also carries the uncertainty of the mean of the latent
    product, which the mean-field posterior of the factors understated. For
    moving positions, the common shifts of the senders' and receivers'
    positions are integrated out with the intercept (a Laplace collapse of
    the shift directions). For static factors, the intercept's variance is
    the variance conditional on the factors.
  * A bipartite panel's static product is reported at mean zero, as the
    samplers report it, with its mean in the intercept. For an undirected fit
    with moving positions, `fit$Oarr` and `fit$UVPM` are the product of the
    factors less the constant `fit$eb$centre[["o"]]`.
  * The linear predictor, `fit$EZ`, fitted values, predictions, the slopes
    and their standard errors are unchanged. A converged fit is still its own
    fixed point under `ame_als_refit()`.
  * Against `lame()` (10,000 scans) on 78 simulated normal panels (30 actors,
    4 periods; directed, undirected and bipartite; ranks 1 and 2; static
    factors or moving positions; moving effects or a moving coefficient):
    * the intercept is within 0.3 posterior standard deviations on 77 panels
      (worst 0.55; up to 1.6 before);
    * its standard error is 0.9 to 1.1 times `lame()`'s on 72 panels (range
      0.82 to 1.20);
    * the slopes are within 0.24 standard deviations, with standard errors
      0.94 to 1.07 times `lame()`'s;
    * the standard error of a moving intercept's path is 1.0 times `lame()`'s
      (13 to 17 times before).
  * On the 64 chains of the earlier validation (16 settings, 4 panels each,
    33,000 scans), the intercept is within 0.3 standard deviations for 57
    fits (worst 0.89), and its standard error is within 0.9 to 1.1 times
    `lame()`'s for 63.
  * On 36 binary and 36 count panels, the slopes and fitted values are
    unchanged. The lowest intercept standard error rises from 0.51 to 0.78
    times `lame()`'s (binary) and from 0.53 to 0.70 (count), and 29 of the 36
    binary and 21 of the 36 count standard errors are within 0.9 to 1.1.
* The empirical-Bayes fast estimators withhold a latent product that the
  data do not determine. Each rule reads an estimated statistic, the signal
  per loading: the squared double-centred product, weighted by the
  information of each observed cell (the Fisher weight at the fit; for a
  normal cell, one over the noise variance), per factor loading.
  * Static fits (`ame_als()`, `lame_als()`, and `ame()` and `lame()` with
    `method = "als"`; normal, binary and Poisson; every mode) withhold the
    product below 2.1. The statistic is in `fit$eb$variational$information`:
    `"per_loading"` (noise variances of signal per loading) for a normal fit,
    and `"signal_per_loading"` for a binary or count fit.
    * Below 2.1, the variational mean product was up to 6.9 times the norm
      of the sampler's posterior mean product for normal fits (50 simulated
      networks). It was up to 6.2 times for binary fits and up to 7.5 times
      for count fits (118 networks).
    * From 2.1, it is 0.99 to 1.15 times the sampler's for normal fits, 0.83
      to 1.00 times for binary fits and 0.94 to 1.12 times for count fits.
    * The training events per loading did not measure this information: a
      binary fit with 5.6 ties per loading had up to 5.7 times the norm of the
      sampler's product.
  * Dynamic normal fits record the same statistic in `fit$eb$information`.
    * Static factors are withheld below 2.1. On 48 simulated panels, products
      below it were up to 5.8 times the norm of `lame()`'s; from 2.1 they
      were 0.99 to 1.03 times it.
    * Moving positions are withheld below 1.3 per loading of a period. On 30
      panels, products below it were up to 11 times `lame()`'s; above it,
      they were 1.00 to 1.09 times it.
  * Dynamic binary and count fits withhold static factors and moving
    positions below 0.7 (`fit$eb$information["signal_per_loading"]`). On 72
    simulated panels (30 actors a side, 4 periods; directed, undirected and
    bipartite; ranks 1 and 2):
    * below 0.65, the product was up to 5.7 times the sampler's norm (binary)
      and up to 11.5 times (count);
    * from 0.9, it was 0.92 to 1.14 times it (binary) and 0.97 to 1.10 times
      (count), with a correlation of 0.966 or more.
  * In a withheld fit:
    * `fit$U`, `fit$V`, `fit$L` and `fit$UVPM` are `NA`, and so are
      `fit$Omat`, `fit$Oarr`, `fit$U_sd` and `fit$V_sd` of a dynamic fit and
      the positions from `latent_positions()`;
    * `uv_plot()` stops with an error of class `lame_product_withheld`;
    * `fit$eb$product_withheld` records the statistic and the threshold. For
      a static fit it also records the log marginal likelihood of every rank
      up to the fitted one, and the rank that this evidence chooses; the
      dynamic estimators have no rank evidence and name no rank;
    * `print()` and `summary()` state the statistic and, for a static fit,
      the chosen rank;
    * coefficients, standard errors, variance components, `fitted()`,
      `predict()` (with `newdata` too) and `residuals()` are unchanged;
    * a bootstrap gives no interval for the positions, and `ame_als_refit()`
      withholds the product in the same way.
  * Neither the posterior-mean scale statistic
    (`options(lame.eb_scale_stat = "mean")`) nor the mean-field scale rule
    closes this gap for normal fits, so neither is the default. Below one
    noise variance per loading, their median norm ratios are 2.25 and 1.74,
    against 2.14 for the default.
* The dynamic empirical-Bayes estimator for binary panels withholds its
  intercept when the static factors are strong. This applies with static
  factors (`R >= 1`, `dynamic_uv = FALSE`) and `dynamic_ab` or
  `dynamic_beta`, from 1.5 units of signal per loading.
  * Strong static factors make the variational posterior shrink the variance
    of the linear predictor (0.86 times the sampler's on a 30-actor panel)
    and of the additive effects (0.72 to 0.76 times). The intercept
    compensates: the mean fitted probability is kept (0.5594 against the
    sampler's 0.5577), but the intercept sits below `lame()`'s posterior mean.
  * On 18 simulated binary panels, the intercept was within 0.25 posterior
    standard deviations of `lame()`'s on the six panels below 1.5. On the
    twelve above, it was 0.24 to 1.22 below (root mean square 0.66), and the
    gap grew with the signal.
  * From the threshold, these hold `NA` for the intercept: `coef()`,
    `fit$coefficients`, `fit$mu`, `fit$BETA`, `fit$eb$se` and `fit$eb$vcov`
    (its row and column), and its row of `fit$coef_path` for a moving
    intercept.
  * `fit$eb$intercept_withheld` records the reason, the statistic and the
    threshold, and `print()` and `summary()` state it.
  * The slopes and their standard errors, `fit$EZ`, fitted values,
    predictions and residuals are unchanged.
  * Binary fits with moving positions and count fits with static factors
    keep their intercepts: they are within 0.49 and 0.63 posterior standard
    deviations of `lame()`'s.
  * `options(lame.eb_withhold_product = FALSE)` and
    `options(lame.eb_withhold_intercept = FALSE)` return the fit without the
    two rules.
* Fits that do not finish are errors, not warnings. A dynamic fit that has
  not met its convergence criterion is an error of class
  `"lame_als_convergence"` whose field `fit` holds the last iterate, and moving
  positions with no identified scale give `"lame_dynamic_uv_scale_edge"` or
  `"lame_dynamic_uv_scale_unsettled"`; none occurred in 1,144 fits at the
  defaults. The penalised dynamic fit follows the same rule (a normal fit's
  sweep limit is raised once, to four times `max_iter`; 23 of 390 random panels
  stopped short before and none does now). A static empirical-Bayes fit whose
  iteration does not settle after its weakest columns are retired, and a
  fixed-effects fit
  (`bias_correct = "none"`, `"jackknife"`, `"bootstrap"`) that has not
  converged, are errors of class `"lame_als_convergence"` that give the stop,
  the score against its threshold and the remedy; a fixed-effects fit that
  stops on its iteration limit is first refitted once with four times
  `max_iter`. This includes the fixed-effects Poisson fit of a network with an
  actor without a count, whose effect runs to minus infinity.
* Sampler draws differ from earlier builds for the same `seed`: the exact
  moves listed under Improvements run by default and use the random-number
  stream, and `dynamic_beta` fits draw their scale and persistence at every
  sweep instead of every 20th. The posterior is unchanged. The moves listed
  under New features have `prior` switches that turn them off. The
  every-sweep hyperparameter draws, and the exact updates whose switches are
  removed (see Removed or refused options), have no switch.
* In the fixed-effects binary ALS fits (`bias_correct = "none"`, `"jackknife"`
  and `"bootstrap"`), the cells of an actor that has only one outcome value on
  a side are left out. That actor's effect is `NA` and is listed in
  `fit$not_estimated`.
* Poisson ALS fits now report the intercept, `EZ` and `ve` on the latent
  lognormal scale used by the MCMC samplers; the mean count is
  `exp(EZ + ve / 2)`, and the fitted values and predictions of the
  fixed-effects fit are unchanged. `rho` is reported as not estimated (`NA`,
  with the reason in `fit$rho_estimation`) when the latent variance cannot be
  distinguished from zero.
* ALS variance components `va` and `vb` now estimate the variance of the
  effects, with sampling noise removed; the old values are in `fit$vc_raw`.
  `fit$deviance` is the deviance of the reported fit, and the optimiser's
  objective is in `fit$objective`. `UVPM` is the double-centred product
  `U V'`.
* `lame()` stores `EZ` on the link scale for Poisson fits, as `ame()` does;
  in 1.3.x it held the rate, so `predict(type = "link")` returned rates.
* Reporting follows measured coverage (2,840 simulated fits, 24 to 30 actors).
  Directed binary panels of two periods or more report `va` and `vb` as not
  estimated below 1.2 events per actor-period (coverage of the 95 percent
  intervals below it 0.28 to 0.91, 0.91 or more from it) and the intercept
  below 0.6 (1.6 with a multiplicative term); `rho_ab`, `sigma_ab` and `cab`
  are reported at every rate. cbin and frn fits report `va`, `vb` and `cab` at
  every share of rows at the cap (coverage 0.88 to 1.00). With a supplied
  effects prior, `va` and `cab` are reported under that prior. The draws stay
  in `fit$VC` and `fit$BETA`, and `summary()` gains `ab_coef_reason`.
  * A cbin or frn fit reports the intercept and the row-covariate
    coefficients as not estimated in three cases. The first two are a
    one-period design with every row at the cap, and one with a share of
    hidden cells from 0.5 (coverage 0.64 and 0.84 there, 0.98 or more
    elsewhere).
  * The third case is a design of two periods or more in which at least half
    of the observed rows nominate the full `odmax` and the posterior mean of
    `va` lies from 0.5 to 1.5 (`ab_coef_reason = "cap_shrunk"`). There the
    posterior of `va` sits near its prior. The intercept's 95 percent
    interval covered 0.89 of 312 simulated panels in this region (0.76 at a
    generating sender sd of 0.5 and of 1.5), against 0.96 of the 1,128
    outside it (24 actors, 4 and 6 periods, cap 10). The region was set on
    two thirds of the seeds and checked on the rest.
  * `va` is reported in that region. Its interval covered 0.91 of the panels
    there (0.79, 1.00 and 0.72 at a generating sender sd of 0.5, 1 and 1.5)
    and 0.99 outside it. `vb` and `cab` covered 0.97 to 1.00 everywhere.
  * A 170 by 100 bipartite cbin or frn fit reports everything. On 200
    simulated panels (cap 10, shares 0.3 and 0.7), the intercept was covered
    in 1.00, `vb` in 0.98 to 1.00 and `va` in 0.90 to 1.00. The posterior
    mean of `va` was 0.09 to 0.15 below the generating variance.
  * The old withholding at 60 and 80 percent of rows at the cap, and the rule
    on the effective size of the intercept with hidden cells, are gone.
* Installation now needs a C++17 compiler and the `pbivnorm` package.
  Suggests now requires testthat (>= 3.1.7) and adds `withr`.

## New features

* `trace_plot()` draws the dynamic hyperparameters: the persistence and
  innovation of the actor effects (`rho_ab`, `sigma_ab`) and of the latent
  positions (`rho_uv`, `sigma_uv`), the reset rate of snap positions
  (`pi_snap`), the per-group `rho_beta` and `sigma_beta` of `dynamic_beta`
  fits and the per-period dyadic correlation of `dynamic_rho` fits.
  `params = "dynamic"` selects them, and the raw names filter in `include` and
  `exclude`. A quantity the model fixes (the error variance of binary-type
  families, the dyadic correlation and sender-receiver covariance of bipartite
  fits, the dyadic correlation without `dcor`) no longer draws a flat panel; it
  is left out only when its draws are constant, so a stuck chain on an
  estimated quantity still shows. A quantity `summary()` reports as not
  estimated is left out with a message naming it.

* `lame_robust()` fits directed continuous panels with a persistent residual
  scale for each directed pair (Student-type residuals). It also supports
  optional temporary observation shocks (`observation_df`) and
  heavy-tailed actor innovations (`actor_df`). Its fits have `print()`,
  `summary()`, `coef()`, `vcov()`, `confint()`, `predict()`, `fitted()`,
  `simulate()` and `nobs()` methods.
* `lame(sampler = "tempered")` adds a replica-exchange sampler for symmetric
  binary panels with static latent factors and shared dynamic actor effects.
* `predict()` on `lame` fits gains `interval = "prediction"`, an interval for
  the outcome itself. `interval = "credible"` is documented as the interval
  for the mean.
* `ame()` and `lame()` gain `multistart` and `bias_correct`, which are passed
  on to the ALS route. `lame()` also gains `als_lowrank_method`,
  `als_linear_solver` and `als_multistart`, and `ame()` gains
  `log_lik_method`.
* `lame()` supports `posterior_options(save_ab = TRUE)`, and
  `simulate_posterior(fit, "ab")` returns the saved additive-effect draws.
  `simulate_posterior()` also returns latent-factor and coefficient draws for
  dynamic fits.
* Forecasts carry forward the joint terminal posterior state, which is saved
  automatically. They no longer plug in posterior means.
* `lame_resume()` and `lame(resume_from = )` continue a checkpointed chain from
  its full saved sampler state. In 1.3.x they ran a cold restart that
  replayed the original random stream.
  * `lame_resume()` also takes a fitted object, including a pooled fit of
    several chains, whose chains are continued from their own final states and
    compared again.
  * A fit continued from the object runs with the arguments of its call,
    `max_seconds` included. A fit that stopped at its time limit therefore
    stops again at the same limit, unless `max_seconds = Inf` (or `NULL`) is
    passed.
  * A run of several chains writes one checkpoint per chain (`_chain1`,
    `_chain2`, ...). `lame_resume()` called with the path the run was given
    stops with an error of class `lame_resume_chain_files`. The error names
    those files and gives the two ways to continue: resume one chain from its
    file, or every chain with `lame_resume(fit, nscan_more = )`. The
    `?lame_resume` example does both.
* `fit$sampler_health` reports numerical failures and bound rejections in
  each update; a numerical failure stops the fit (`lame_sampler_failure`).
* Smaller additions: `ab_plot(effect = "both")` works for `ame` and `lame`
  fits; `Xdyad` can be a 4-D `[n, n, p, T]` array; `forecast_pit()` gains
  `newdata`, `newdesign` and `newexposure`; `ame_als_bootstrap()` and
  `boot_ame()` gain `max_iter` and `tol`; `ame_als_refit()` gains
  `bias_correct`.
* `prior` accepts `sigma_actor_shape`, `sigma_actor_scale`,
  `rho_actor_shape1` and `rho_actor_shape2` for actor-specific slope paths.
  It also accepts `snap_kappa` for the reset scale of `dynamic_uv_kind = "snap"`.
* ALS fits with `R > 0` expose `UVPM` (and `ULUPM` when symmetric). Dynamic
  ALS fits report the persistences and innovation scales of their paths (what
  the smoothing penalties imply for a penalised fit, estimates for an
  empirical-Bayes fit), and `als_start_vals()` passes them on to a
  warm-started MCMC run.
* `ame_als()` and `lame_als()` gain `dcor` (default `!symmetric`, as in
  `ame()` and `lame()`, which pass it on). A directed binary probit fit with
  the empirical-Bayes estimator takes the two cells of a dyad as one bivariate
  probit observation and estimates `rho` under the prior the samplers share
  (`fit$VC["rho"]`, `fit$rho_estimation`, `fit$eb$pair`); it agrees with the
  sampler's posterior mean to within 0.03 on average (100 simulated networks).
  The pairs cost up to 4.35 times the independent-cell fit, and `dcor = FALSE`
  is the fast path for very large networks. An explicit `dcor = TRUE` with the
  logit link is an error.
* Options for the fast estimators: `options(lame.als_threads = k)` splits the
  compiled quadratures over `k` OpenMP threads where the platform has them
  (default 1; the estimates do not depend on it; do not combine threads with
  forked workers such as `parallel::mclapply()`);
  `options(lame.als_engine = "r")` runs the R reference implementations;
  `options(lame.eb_scale = "plugin")` selects the mean-field rule for the
  scale of the factor prior and `options(lame.eb_scale_uncertainty = FALSE)`
  leaves its uncertainty out of `vcov()`.
* Empirical-Bayes ALS fits carry `fit$eb` (the estimator, the variational
  iteration, the factor posterior and scale, the dyadic-correlation record
  `pair`, the Laplace `vcov` and `se`, and for counts `ve` and `ve_search`).
  Moving-position fits add `U_sd`, `V_sd` and `UVPM` and, in `fit$eb`,
  `uv_scale`, `uv_search` and `restart`; Student-t fits add `lambda_u` and
  `lambda_v`.
* New `prior` switches of the sampler. All are `TRUE` by default and `FALSE`
  turns the move off: `actor_move_period` and `actor_move_room` (period
  updates of the intercept of `cbin` and `frn` fits), `actor_move_paths` (path
  moves of moving positions), `ab_hyper_move` (with `ab_hyper_move_tries`),
  `uv_g_scale_move`, `beta_hyper_nc`, `actor_hyper_nc`,
  `poisson_period_move` and `poisson_static_move`. `actor_move_every` sets how often the per-actor
  translations run (default 10; 2 for Poisson fits in `lame()`; 1 for the
  translations of `cbin` and `frn` fits). The work of the moves is recorded in
  `fit$actor_move`, `fit$ab_hyper_move`, `fit$uv_g_scale_move`,
  `fit$beta_hyper_move`, `fit$pa_hyper_move` and `fit$poisson_period_move`.
  The later moves are `ordinal_scale_move`, `binary_scale_move` (with
  `binary_scale_every`) and, for bipartite binary fits, the level move (with
  `level_move_every` and `level_move_tries`); their records
  are `fit$ordinal_scale_move`, `fit$binary_scale_move` and `fit$level_move`.
* `ame_als()` and `lame_als()` take `prior = list(s20 = )`, the scale of the
  inverse-gamma prior of the noise variance of a Poisson or normal fit
  (`ame(method = "als")` and `lame(method = "als")` forward it).
  `options(lame.eb_scale_stat = "mean")` sets the prior scale of the
  empirical-Bayes factors at the posterior mean of the covariance; it
  overshoots binary fits by 5 percent, so it is off.

## Improvements

* Print and summary methods (`print()`, `summary()` and `prior_summary()` for
  every class) format their output with cli and write it to standard output,
  so `capture.output()` and knitr chunks with `message = FALSE` show it.
  Headings are in sentence case.
* Package plots use sentence-case titles and labels, left-aligned titles and
  captions, and colour only where it encodes information: the observed series
  in goodness-of-fit plots is black, coefficient plots (including
  `autoplot()` of MCMC fits) colour estimates blue (positive), red (negative)
  or grey (interval covering zero), and highlighted trajectories in
  `uv_plot()` use the ColorBrewer Dark2 palette. `trace_plot(include = ,
  exclude = )` match parameter labels regardless of case.
* User-facing input errors are classed cli errors throughout.
* Static symmetric `lame()` fits with `R > 0` start their factors from signed
  eigenvectors. Chains previously often stuck in the all-positive eigenvalue
  sector and could not reach a negative (heterophilous) dimension.
* Binary `ame()` and `lame()` fits warn when the fit has separated, meaning at
  least 5% of observed dyads have a linear predictor beyond 8 in absolute
  value (class `lame_separation`). The warning that `R` is large relative to
  `n` is gone: ranks up to `n - 1` showed no numerical failure, only gradually
  lower accuracy, and `?ame` states that.
* Binary directed `lame()` fits with static latent positions now include the
  joint scale move along the intercept / effect-variance ridge that R = 0 and
  moving-position fits already had. On sparse panels an actor with no events
  could otherwise drag its level and the intercept far off for hundreds of
  thousands of sweeps. The posterior is unchanged.
* Directed `dynamic_uv` fits of the `"ar1"` and `"t"` kinds (normal, binary,
  Poisson) start from a penalised dynamic ALS fit by default. From a cold
  start, some chains settled at the wrong persistence and stayed there. Set
  `prior$als_start = FALSE` to keep the cold start.
* Binary samplers gain exact joint moves that improve mixing on sparse
  panels:
  * a level/scale move (`prior$level_move_every`, `prior$level_move_tries`);
  * a deviation-scale move (`prior$dev_move`);
  * observed-likelihood moves for some dynamic designs
    (`prior$marginal_move`, `prior$actor_factor_slice`,
    `prior$bipartite_scale_move`);
  * a collapsed per-actor update (`prior$actor_move`): each actor's level
    translation and, with static positions, its position is drawn by an exact
    elliptical slice step with the latent array integrated out. The augmented
    sweep moves an actor that has no events by about `1/sqrt(m)` per sweep
    however wide its posterior is, which left chains for sparse panels in
    different places after hundreds of thousands of sweeps (the static
    positions of inactive actors spread out, inflated the position covariance
    and carried the reported intercept and levels with them). The update runs
    for directed, symmetric and bipartite fits, in `lame()` and `ame()`, for
    panels with absent actors (only observed cells carry a likelihood factor),
    with `dynamic_beta` of kind `"ar1"` or `"rw1"`, and with fewer additive
    margins. The posterior is unchanged; `prior$actor_move = FALSE` switches
    the update off and `prior$actor_move_every` sets its frequency (default
    10). In `lame()` the positions are left to the sampler during the first
    half of burn-in, when it runs under a diffuse factor prior. With
    `dcor = TRUE` the same visit also updates the dyadic correlation with both
    latent responses of each dyad integrated out (`prior$actor_move_rho`),
    which raised its effective sample size by a factor of about 50 on a sparse
    panel. A rank-one fit of a symmetric alliance panel that failed the
    two-seed convergence gate without the update (bulk effective sample size
    58) passes with it (347); the update costs 10 to 30 percent more time per
    sweep.
* `cbin` and `frn` fits get exact moves for the quantities that data
  augmentation moves by about `1/sqrt(m)` per sweep. All run under
  `prior$actor_move`, add 15 to 40 percent to the time of a sweep and are
  recorded in `fit$actor_move`. At 170 actors and two periods both families
  now pass the two-seed convergence gate (largest split R-hat: `cbin` 1.099 to
  1.012, `frn` 1.285 to 1.018). The moves:
  * each receiver's level is translated with its latent column (the effective
    sample size of a receiver nobody nominates had fallen roughly as `1/n`: 57
    of 1,600 draws at 170 actors in `ame()`, now 1,618);
  * the rows at their cap are translated against the intercept and the rows
    with room by one exact draw;
  * directed fits with `dcor = TRUE` update the dyadic correlation with the
    non-nominations integrated out;
  * `dynamic_ab`, `dynamic_beta` (kinds `"ar1"` and `"rw1"`) and
    `dynamic_beta_per_actor` fits get the sender and receiver translations and
    the level update, and with a moving intercept the intercept of each period
    moves by two further exact updates (`prior$actor_move_period`,
    `prior$actor_move_room`).
* Bipartite `ame()` fits of every family but the binary one with an intercept
  draw exactly along the ridge that the intercept shares with the means of the
  levels, as the binary update already did (the intercept of a 30 x 20 normal
  fit: 133 to 2,000 effective draws of 2,000).
* Poisson and ordinal fits (unipartite and bipartite; static and `dynamic_ab`
  effects) now equilibrate on sparse panels with inactive actors. Every
  `prior$actor_move_every` sweeps each actor's level is translated with the
  latent values of its row or column by an exact draw; Poisson fits also
  translate each static coefficient and position and move the dyadic variance
  and correlation with the latent residuals, and ordinal fits draw the
  location of the latent array exactly. Thirteen sparse panels that failed the
  two-seed gate without the moves (R-hat 1.55 to 2.01) pass with them (at most
  1.010). A sweep costs about a quarter more.
* `lame()` Poisson fits with `dynamic_beta` also mix their period intercepts:
  each period and the whole path of every moving coefficient are translated
  with their latent values, as are the static coefficients beside them
  (`prior$poisson_period_move`, `prior$poisson_static_move`); the dyadic
  variance and correlation move with the latent residuals in every Poisson fit;
  and the level translations visit Poisson fits
  every second sweep. On a 170-actor, four-period panel the worst split R-hat
  falls from 2.34 to 1.006, at about a third more time per sweep; on a
  30-actor panel the integrated autocorrelation time of a moving covariate
  coefficient falls from 340 to 470 sweeps to about 11.
* `dynamic_ab` fits draw the level variances (`va`, `vb`, `cab`), `sigma_ab`
  and `rho_ab` jointly given the totals of the effects, with the levels
  integrated out, in every family and mode (`prior$ab_hyper_move`). On short
  or sparse panels these trade almost freely and the sweep crossed that ridge
  only over thousands of sweeps: on a sparse 60 x 80 x 5 bipartite binary
  panel the smallest effective sample size rises from 13 to 435.
* Bipartite fits with static positions draw the split of scale between the
  positions and the interaction matrix exactly (`prior$uv_g_scale_move`); on a
  roll-call panel the effective sample size of the scale of the positions
  rises from 49 to 1,464.
* Fits with moving positions (`dynamic_uv = TRUE`, Poisson and binary,
  directed, symmetric and bipartite) redraw the whole position path of each
  actor under its AR(1) prior with one elliptical slice step every
  `prior$actor_move_every` sweeps (`prior$actor_move_paths = FALSE` omits it).
  On nine sparse Poisson panels two chains had disagreed on the positions
  every time (R-hat 1.03 to 1.8); eight now pass the gate (at most 1.024).
  Symmetric fits also draw the scale ridge between coordinate paths and
  weights every sweep and `rho_uv` with an adaptive proposal scale (effective
  sample size 115 to 1,724 on a 30-actor panel), and the bipartite scale step
  (`prior$bipartite_scale_move`) now runs for Poisson and ordinal fits with
  moving positions.
* `dynamic_beta` fits draw the innovation scale and persistence of each
  coefficient path, and the pooled ones of `dynamic_beta_pool`, at every sweep
  instead of every 20th, which had left 4 to 20 times fewer effective draws
  (357 of 1,600 draws of the scale at 170 actors on a normal panel, now
  1,599). An interweaving step moves them with the path
  (`prior$beta_hyper_nc`). `dynamic_beta_per_actor` fits do the same for
  `sigma_actor` and `rho_actor` (`prior$actor_hyper_nc`): 18 to 75
  effective draws of 2,000, now 220 to 900.
* Ordinal `ame()` and `lame()` fits mix in the dyadic coefficients, the
  additive effects and the dyadic correlation. Each sweep draws, exactly, the
  factor by which the latent array, the coefficients and the static additive
  effects are multiplied, and the shift and scale of each period's latent
  array, along transformations that keep every rank (`prior$ordinal_scale_move
  = FALSE` omits them; `fit$ordinal_scale_move`). On 150 actors a dyadic
  coefficient has 600 effective draws of 600 (was 8); on 170 actors in four
  periods with dynamic additive effects 47 per 1,000 sweeps (was 1.3). A sweep
  costs about 10 percent more.
* Binary `ame()` and `lame()` fits draw the scale of the linear predictor
  exactly every fifth sweep (`prior$binary_scale_every`;
  `prior$binary_scale_move = FALSE` omits it). A covariate that separates the
  ties made the coefficient a random walk whose posterior mean depended on the
  chain length; now two seeds agree and the posterior mean is the same at
  2,000, 8,000 and 32,000 sweeps (12 effective draws of 2,000 become 460). A
  sweep costs 5 to 25 percent more.
* Poisson `ame()` fits take the moves of `lame()`: the dyadic variance and
  correlation move with the latent residuals, and the translations run every
  second sweep (`prior$actor_move_every`; was ten). The 50-actor rank-2 panel that failed the
  two-seed gate (R-hat 1.09, 18 effective draws) passes (1.02, 155). A sweep
  of that panel costs 37 percent more.
* Poisson fits of symmetric networks with a row or column covariate run the
  whole sampler. The scale move and the static-coefficient translations had
  been skipped without a message whenever the predictor was not symmetric (0
  attempts in 120 sweeps); the dyadic variance had 3 to 17 effective draws of
  800 and now has 111 to 889.
* Binary bipartite fits with an intercept, both additive margins and static
  coefficients take a joint scale step of the whole predictor with the latent
  array integrated out (`level_move_every`, `level_move_tries`;
  `fit$level_move`): on a 40 x 50 x 5 panel the effective
  size of the intercept rises from 770 to 1,293 of 4,000 draws.
* The persistence and stationary variance of AR(1) position paths
  (`dynamic_uv`, directed and bipartite) are drawn as a block; at a
  cap of 2 the effective size of `rho_uv` rises from 796 to 2,163 of 8,000. In
  bipartite fits `prior$uv_var_cap` is the prior of the scale of the
  positions, which the data do not identify, so read a bipartite fit through
  the product of positions and interaction matrix. The block draw also runs
  for the Student-t kind (effective size of persistence and scale 51 to 192 and
  198 of 1,200 with a binding cap).
* Symmetric `lame()` binary and ordinal fits with a nodal covariate draw the row
  and column coefficient as one (`prior$symmetric_node_tie`). The predictor of a
  symmetric network depends on them only through their mean, and the difference
  between them, of the width of the prior, leaked into every other draw: with
  `dynamic_ab` and a time-varying nodal covariate `sigma_ab` walked to 15 to 100
  (R-hat 2.5 to 2.9). The two-seed gate now gives R-hat 1.026 with 217
  (binary) and 284 (ordinal) effective draws.
* Bipartite fits with latent factors draw the rows of the two static factors
  from their Gaussian conditionals (`ame()` and `lame()`): the effective size of the amplitude of `U G V'` goes from 0.3 to
  170 per 1,000 sweeps, and 34 of 36 bipartite acceptance fits pass over three
  seeds (`ame()` was 0 of 6). Bipartite `ame()` fits also draw the
  covariate-ridge exactly (`prior$cov_ridge_move`).
* Directed `ame()` and static-position `lame()` fits with `R > 0` draw the split
  of scale between `U` and `V` exactly each sweep (`prior$uv_split_move`; `fit$uv_split_move`): the
  effective size of `log|U|/|V|` goes from 3 to 54 to 118 to 1,400 of 1,600
  draws, and the 170-actor, four-period ordinal panel with `dynamic_ab` goes from 3 to
  118.
* Directed static-position `cbin`, `frn` and ordinal fits draw the position of
  each sender and receiver together with the latent values of its row or column
  (`prior$sparse_position_move`; `prior$sparse_position_every` sets the visit
  interval; `fit$sparse_position_move`). The products of sparse actors had 18 to 40 effective draws of 8,000
  on the 50-actor cbin and frn panels (R-hat 1.07 to 1.09) and now have 70 and
  111 (1.027, 1.031). A cbin or frn sweep costs about 1.1 times a sweep
  without the move, and an ordinal fit that runs the move visits `actor_move`
  every sweep.
* Directed `lame()` and `ame()` fits with a row or column covariate draw the
  trade between its coefficient and the additive effects of its margin exactly
  (`prior$cov_ridge_move`): on the 170-actor ordinal panel with `dynamic_ab` the
  coefficient of a period-varying nodal covariate goes from 38 to 121 to 525 to
  569 effective draws of 800, and the panel passes the two-seed gate on four of
  four seed pairs. Fits without such a covariate are unchanged to the last bit.
* `lame()` Poisson fits with `dynamic_ab` move each actor-period effect together
  with the latent values of its row or column, exactly, at every sweep (in
  pairs where an intercept is present; `prior$ab_period_move = FALSE` omits
  the move; `fit$ab_period_move`). `sigma_ab` has 216 effective draws where it
  had 6, and the directed, symmetric and 170-actor four-period acceptance
  panels that failed the two-seed gate at the package defaults (0, 2 and 0 of 4
  seed pairs) pass on all four. A sweep costs 20 to 72 percent more; the
  symmetric case, whose actor pairs are visited in sequence, costs 7 percent
  more.
* `dynamic_uv` fits of the `"ar1"` kind draw their hyperparameters in a
  non-centred step as well (`prior$uv_nc_move`; `fit$uv_nc_move`). A symmetric
  fit draws the persistence `rho_uv` given the standardised innovations of the
  paths, which follow it; a bipartite fit scales the paths and `sigma_uv`
  together and divides the interaction matrix by the square of the factor. Both
  are exact. The persistence has 210 to 370 effective draws where it had 30
  to 70, and the symmetric binary panel (0 of 4 seed pairs before), the
  bipartite fixed-rank panel (1 of 4) and the symmetric ordinal panel (3 of 4)
  pass the two-seed gate on four of four.
* Symmetric Poisson fits with `dynamic_uv` of the `"ar1"` kind make a tempered
  transition of one eigen-direction every 5 sweeps (`prior$uv_temper_move`,
  `prior$uv_temper_every`; `fit$uv_temper_move`). The sign of a weight of a
  symmetric fit is part of the model, and on a sparse count panel the first
  weight stayed in one sign state for thousands of sweeps (22 changes of sign
  in 10,000), so the products of sparse actors failed the two-seed gate on four
  of four seed pairs. No move that keeps the predictor can cross between the
  states. The transition (Neal 1996; a ladder of 33 inverse temperatures from
  1 to 0.7, one pass per level) carries the latent array, is exact, and
  passes four of four; 10 percent of the transitions change a sign. A fit
  with the transition and the non-centred persistence step costs 1.4 times
  one without them, in this model class only.
* The costly parts of these moves run in compiled code: the translation moves
  of Poisson fits, the symmetric actor-period move of Poisson `dynamic_ab`
  fits, the feasibility check of the nomination families, the position and
  path visits of `cbin` and `frn` fits, and the tempered transition. The
  compiled code gives the same draws as the R code it replaces, to the last
  bit. The tempered transition also moved to the shorter ladder described
  above, which crosses between the sign states at least as often (10 percent
  of the transitions change a sign, against 6 percent on the longer ladder).
  * The symmetric actor-period move now adds 7 percent to a sweep (58 percent
    before), and the Poisson translations of a rank-2 `ame()` fit add 37
    percent (109 percent before).
  * `cbin` and `frn` fits with static positions run at 1.1 times the cost of
    a fit without the position move (2.6 to 2.8 times before), and with
    `dynamic_uv` at 1.06 times (2.0 times before).
  * Symmetric Poisson fits with `dynamic_uv` run at 1.4 times the cost of a
    fit without the tempered transition and the non-centred persistence step
    (2.3 times before).
* The `rho` update mixes in a wide proposal, so it no longer freezes on
  panels with few mutual dyads. `rho_uv`, `sigma_uv`, `rho_ab` and
  `sigma_ab` are now updated every sweep.
* cbin and frn fits with missing cells draw the hidden cells from their exact
  conditional, and the frn fits keep the observed rank order. Each sender's
  level moves jointly with its row. In 1.3.x, `va` came out at about half
  its value with a fifth of the cells hidden, and the intercept mixed poorly.
* `dynamic_uv_kind = "snap"`: resets now land on the stationary distribution
  of the paths by default. At rank one, `summary()` and `print()` report
  `rho_uv`, `sigma_uv` and `pi_snap`, but not at rank two or more. `"t"`
  fits report `rho_uv` and `sigma_uv` at any rank when the chain started from
  a dynamic ALS fit, and otherwise only at rank one.
* New messages flag weak information:
  * before sampling: what the fit will not report under the measured
    reporting rules (see "Reporting follows measured coverage"); panels with
    few mutual dyads, where `rho` is informed mainly by the absence of mutual
    ties and its posterior can stay near the prior or move toward -1; and
    `Y` that is symmetric in every period while `symmetric = FALSE`;
  * after sampling: a chain still drifting at the end of the run, or chains
    that disagree, are extended and then refused (see Breaking changes), and a fit whose latent draws
    were refused at their bound in 1 percent or more of the sweeps says so.
* Static ALS fits are 15 to 30 times faster on panels of 40 to 170 actors,
  with the same estimates. The block updates work on dyad-level sums and
  start the additive block from its exact solution.
* The fixed-effects binary ALS fit (`bias_correct = "none"`) is now the exact
  maximum-likelihood probit/logit fit. A cap on the working response had
  stopped it short of the maximum.
* The fixed-effects Poisson ALS fit halves an overshooting reweighting step.
  It no longer returns the least-squares starting fit, which could badly
  understate coefficients.
* Penalised dynamic ALS fits (`bias_correct = "none"` or `"jackknife"`) are
  proper descent methods: a sweep that raised the objective is undone and
  redone block by block, so the warning that it might not descend is gone.
  They are stable on sparse binary and Poisson panels, whose static factors
  now carry the level prior of the dynamic factors (precision 1; a separable
  binary panel used to run to a product of norm 20,000), and count the
  penalized paths in the residual degrees of freedom of `ve`. A panel with
  actors entering and leaving, or an actor present with no observed cell,
  converges instead of running to the budget at a fixed point. With `bias_correct = "jackknife"`, directed
  dynamic Poisson fits correct the latent variance and reciprocal covariance
  with a split-dyad jackknife.
* The latent factors of empirical-Bayes ALS fits are the means of a Gaussian
  variational posterior, with the variance of the product carried through the
  likelihood, not the posterior mode. The mode of a factor the data barely
  identify fits noise and inflates the slope of a covariate that follows the
  product (dense one-period directed panels: +3.9 percent at the generating
  rank; -0.4 percent for the variational fit and for the sampler).
  * The scale of the prior of the factors comes from the cavity covariances of
    the factor rows. With fewer than 3 events per loading, plain mean-field
    covariances drove it to the floor of the hyperprior; with the cavity rule
    the slope lies within 0.11 posterior standard deviations of the sampler's
    mean (197 simulated networks). `vcov()` includes the uncertainty of the
    scale.
  * Undirected and bipartite fits use the samplers' factor priors; in a
    bipartite fit a sender column the data do not inform falls to the small
    eigenvalues of a Wishart matrix instead of keeping the scale of its prior.
  * `fit$eb$estimator`, `fit$eb$variational` and `fit$eb$factor_posterior`
    record the iteration. A fit that does not reach its fixed point retires
    its weakest factor column (see the Poisson bullet) and is refused with
    class `"lame_als_convergence"` only when none is left; the posterior mode
    is never substituted. A product the data do not determine is withheld
    (see Breaking changes).
* `fit$eb$log_marginal` (also `logLik()`) is the Laplace approximation to the
  log marginal likelihood with the effects and factors integrated out, so
  ranks can be compared. Its largest value was the generating rank in every
  simulated network with at least 10 events per factor loading and in 95
  percent of those with 3 to 10 (1,040 networks). Below 3 events per loading
  `?ame_als` gives a rule that uses the held-out predictive score (right for
  88 percent of 624 networks).
* The quadratures of the empirical-Bayes fits run in compiled code. A
  170-state, 10-period fit with the dyadic correlation takes 43 s at rank 0
  and 297 s at rank 2 on one thread, and 16 s and 100 s on six
  (`options(lame.als_threads)`).
* Poisson ALS fits are empirical-Bayes / variational fits of the model that
  `ame()` and `lame()` sample: a count is `Poisson(exp(z))` with `z` the
  linear predictor plus normal noise of variance `ve`, which is estimated by
  maximising the Laplace marginal likelihood under the sampler's inverse-gamma
  prior (`fit$eb$ve_search`).
  * An actor without a count on a side keeps a finite effect, as in the
    sampler (-2.7 on a 30-actor network, where the fixed-effects fit gave
    -17.5).
  * A directed network takes the two counts of a dyad as one observation at
    the fitted state (`dcor = TRUE` by default; `fit$VC["rho"]` where the
    counts are overdispersed), and the information of the pairs enters
    `vcov()`. That matters for a covariate that is the same in both cells of a
    dyad, whose standard error was 13 to 23 percent too small at a reciprocity
    of 0.6 to 0.8. `dcor = FALSE` skips the pair stage.
  * A network without a count above zero, and a dyadic covariate of one sign
    that is non-zero only where every count is zero, are refused with an error
    of class `"lame_als_separation"`.
  * Against `ame()` and `lame()` on 29 simulated networks the coefficients are
    within 0.35 posterior standard deviations (fixed-effects fit: 2.8), and on
    1,500 simulated networks the 95 percent interval covered the slope in 95.5
    percent. A fit costs 4 to 39 times the fixed-effects fit on one thread.
  * With a latent rank and fewer than about three nonzero counts per factor
    loading, the slopes and their intervals are not affected, and `ve` is within 0.41
    (against `ame()`) and 0.28 (against `lame()`) posterior standard
    deviations on 22 networks of 1.1 to 6.6 nonzero counts per loading. For a
    plain Poisson panel (true `ve` 0) it sits where the sampler's posterior
    does, 0.034 to 0.046, held off zero by the inverse-gamma prior.
  * A rank the data do not support is not refused: its product is withheld
    when the signal per loading is below the threshold (see Breaking
    changes). A binary or count fit whose iteration does not settle
    first refines the quadrature of its pair likelihood (5, 7, then 9 nodes a
    side), then retires the weakest latent column and fits the next rank down;
    `fit$R` is the rank fitted, `fit$R_requested` the rank asked for and
    `fit$eb$retirement` the record, and the fit says so when it is made (a
    message of class `"lame_als_retirement"`). Nothing is refused on the validation sets
    (4 of 576 rank-evidence fits, 1 of 54 very sparse count networks and 3 of
    72 sparse bipartite fits retire a column); a fit that still does not
    settle with no column left is refused with class `"lame_als_convergence"`.
    With about one nonzero count per loading or fewer, `ve` averages 0.39, 0.35
    and 0.39 at ranks 1 to 3 for a truth of 0.4.
* Dynamic empirical-Bayes fits cover static latent factors (`R > 0` with
  `dynamic_uv = FALSE`: the static estimator's variational posterior, so the
  same data give the same answer through `ame_als()` and through the dynamic
  fit), moving positions (`dynamic_uv = TRUE`, the `"ar1"` kind; directed,
  bipartite -- also with `R_row != R_col` -- and undirected networks, any
  rank) and Student-t transitions (`dynamic_uv_kind = "t"`, directed and
  undirected networks; bipartite networks refuse it, as `lame()` does).
  * Moving positions have a mean-field Gaussian posterior whose product
    uncertainty enters the working problem of every cell: `fit$U` and `fit$V`
    (n x R x T), `fit$U_sd`, `fit$V_sd`, `fit$UVPM`, and in `fit$eb` the
    stationary variance of the positions (`uv_scale`) and the search that
    chose it (`uv_search`). On simulated panels the slope bias has a median of
    1.5 percent and a maximum of 5.5 percent. A fit takes seconds to a minute
    or two on panels of 20 to 120 actors, against 7 to 30 minutes for the
    sampler. `verbose = TRUE` prints one line per evaluation of the position
    scale; a scale at the edge of its range, or a search that did not settle,
    is an error of class `"lame_dynamic_uv_scale_edge"` or
    `"lame_dynamic_uv_scale_unsettled"`.
  * The mixing weights of the t transition have a variational posterior
    (`fit$lambda_u`, `fit$lambda_v`; `nu = 4` or `prior$t_nu`). On six
    t-generated panels the innovation scale is within 3 percent of the
    sampler's t fits.
  * A directed fit models the dyadic correlation as `lame()` does (`dcor`;
    `fit$VC["rho"]`, `fit$rho_estimation`, `fit$eb$pair`). A binary fit takes
    1.4 to 2.7 times as long as the independent-cell fit.
  * Dynamic empirical-Bayes fits honour `rvar`, `cvar` and `nvar` (a disabled
    margin is a point mass at zero, as in the sampler), `dynamic_beta_pool`
    and `dynamic_beta_kind = "rw2"`; the penalised routes name the switches
    they cannot honour in the warning about ignored arguments.
  * Dynamic Poisson fits estimate `ve`, the covariance of the levels and the
    persistences and scales of the paths, moving coefficients and moving
    positions by EM under the `lame()` hyperpriors (`prior$s20` included).
    Against the sampler on 108 simulated panels the slopes are within 0.04
    posterior standard deviations on average (penalised fit: up to 1.3) and
    the standard errors are 0.96 to 1.06 times the posterior standard
    deviations.
  * The noise variance of a zero-heavy panel is no longer low: `ve` is 1.02
    to 1.07 times the truth with 80 to 82 percent zero cells and 1.12 times
    with 92 percent (it was 0.81 to 0.84 and 0.59), where the data hardly
    inform it; it is within 3 percent of the truth on the non-sparse panels and
    within 0.6 posterior standard deviations of the sampler's on all 21 settings.
* A converged dynamic empirical-Bayes fit is its own fixed point under
  `ame_als_refit()` (zero iterations, identical coefficients), and
  `als_start_vals()` of one passes on the estimated `rho_ab`, `sigma_ab`,
  `rho_uv` and `sigma_uv`.
* ALS parametric-bootstrap intervals centre the replicate effects (the
  intercept's bootstrap SE had been several times the posterior SD); an
  empirical-Bayes fit draws them uncentred, since its intercept is the
  population intercept. `ame_als_bootstrap()` handles actors whose effect is
  not estimated.
* `bootstrap = N` below 30 is an error of class
  `"lame_als_bootstrap_replicates"`, raised before anything is fitted
  (`ame_als_bootstrap()` needs `R >= 10`). A replicate that has not converged
  is dropped, never kept; more than 5 percent dropped is an error of class
  `"lame_als_bootstrap_convergence"` (0 of about 40,000 replicates dropped in
  testing). A coefficient outside the central 95 percent of its own replicates
  is an error of class `"lame_als_bootstrap_optimum"`, a variance component in
  that position gets no interval (`vc_uncentred`), and factor columns whose
  singular values are not separated have `NA` column-wise intervals.
  Replicates of a fit with a latent rank are refit from the point estimate and
  from the cold start; the lowest-objective converged refit is kept.
* The split-sample jackknife no longer combines a half-sample refit that has
  not converged: a half is continued once with five times `max_iter`, then
  the call is an error of class `"lame_jk_nonconvergence"`.
* `ame_als_bootstrap()` refuses an estimator that has no bootstrap before it
  checks `R`, and penalised non-normal dynamic fits get class
  `"lame_als_bootstrap_unsupported"`; a binary or Poisson dynamic
  empirical-Bayes fit used to get an unclassed message.
* `gof_plot()` of a longitudinal `ame_als` fit draws every time slice; it used
  the first. The message that the additive effects were "approximate" is gone:
  the normal equations were always solved exactly (an exact solve that cannot
  reach them is an error of class `"lame_als_numerical"`).
* A block bootstrap (`type = "block"`) says which parameters it cannot cover
  instead of warning that they "can severely under-cover": resampling time
  slices holds the actors fixed, so the node-covariate coefficients, `va`, `vb`,
  `cab`, `ve` and, for an empirical-Bayes fit, the intercept and the shrunk
  effects and factors are `NA` in `se`, `confint()`, `vcov()`, `tidy()` and
  `summary()`, with the reason in `fit$bootstrap$withheld`; `type = "parametric"`
  gives them. Over 1,720 bootstraps a 95 percent block interval covered the
  node-covariate coefficients in 0.07 to 0.13 of the panels and `va`, `vb`,
  `cab` in 0.12 to 0.17, against 0.93 to 0.95 for the dyadic coefficients, `rho`
  and the fixed-effects intercept, which keep their intervals. Block intervals
  are read at the expanded percentile levels for the number of blocks
  (`n_blocks`; 0.95 against 0.90 for the plain percentile); use 200 or more
  replicates.
* The bootstrap of an uncorrected binary fixed-effects fit
  (`bias_correct = "none"`) is an error of class `"lame_als_bootstrap_bias"`,
  raised before anything is fitted: every replicate reproduces the
  incidental-parameters bias, and the 95 percent interval covered the dyadic
  coefficient in 0.54 to 0.84 of the panels. The default empirical-Bayes fit and
  the jackknife- and bootstrap-corrected fits are bootstrapped. For the
  corrected fits (`bias_correct = "jackknife"` or `"bootstrap"`), the
  intervals covered the dyadic coefficient, `va` and `vb` in 0.944, 0.940
  and 0.943 of 595 panels in four cells (30 actors with 4 periods, 60 actors
  with 2). A fixed-effects Poisson fit has no interval for its
  intercept (coverage 0.61 to 0.85).
* The parametric bootstrap interval of the intercept of a fixed-effects fit with
  node covariates is no longer 2.6 times too wide (coverage 0.92); the
  intervals of `va` and `vb` are bias-corrected (empirical-Bayes coverage 0.65
  to 0.75 becomes 0.91 to 0.97, fixed effects 0.82 to 0.89 becomes 0.92 to
  0.98). The bootstrap of a penalised normal dynamic fit follows the same
  contract (`N >= 30`, dropped replicates), redraws the additive paths as
  `ame_als_bootstrap()` does (intercept coverage 0.90 against 0.08 with the
  paths held fixed), and `lame(method = "als", bootstrap = N)` on a penalised
  binary or Poisson dynamic fit is an error of class
  `"lame_als_bootstrap_unsupported"`. `ame(method = "als", prior = )` forwards
  `prior` instead of warning that it is ignored.
* `summary()` of a dynamic `lame()` fit reports how much the data narrow
  `rho_uv` and `rho_ab`: `summary(fit)$persistence_prior_check` holds the
  posterior sd, the sd of the truncated prior and their ratio, and the printed
  summary says when it is above 0.6 (for example "posterior sd 0.112 is 0.89
  of the prior sd 0.126: the data barely inform it").

## Bug fixes

* Bipartite `lame()` fits with `dynamic_uv = TRUE` stored latent positions
  whose per-period products `U_t G V_t'` did not match the fit: the alignment
  across periods folded each period's rotation into the single interaction
  matrix `G`, changing the products of every period by up to 114% (relative
  Frobenius norm). The alignment now uses only the sign changes that a single
  `G` can absorb, so each period's product is unchanged and `fit$G` is not
  altered. This affected `fit$U`, `fit$V`, `fit$G`, `latent_positions()`,
  `uv_plot()` and `simulate(type = "approximate")`; `fit$UVPM` was correct.
  `procrustes_align(per_draw = TRUE)` on bipartite fits now aligns each draw
  with its own `G` draw.
* `simulate(type = "approximate", newdata = ...)` built the predictor from
  `newdata$Xdyad` without the intercept slice, so the intercept coefficient
  multiplied the first covariate; with `newdata` but no `Xdyad` the intercept
  was dropped. The approximation now builds each period's design as
  `type = "posterior"` does. Unnamed new covariates take the fitted names of
  their role when the counts match, for both types.
* `simulate(type = "approximate")` on a `dynamic_beta` fit used the
  period-averaged intercept when covariates were absent, and requesting more
  periods than the fit has stopped with a subscript error; it now uses each
  period's coefficients and refuses longer horizons with the classed error
  `lame_simulate_periods`.
* `simulate(return_latent = TRUE)` drew bipartite latent arrays without the
  bipartite flag.
* A `NULL` period in `Xdyad` was dropped from the period list (a trailing one
  shortened it); `lame()` now refuses it with a clear message.
* `prediction_draws_long()` failed on a fit with `intercept = FALSE` and no
  covariates.
* `gof_plot()` labelled its band "95%" whatever `credible.level` was.
* The error for `nscan` not a multiple of `odens` stated the condition the
  wrong way round.
* `latent_positions()` on an `ame_als` fit suggested an MCMC-only option for
  standard deviations.
* A single-period `lame()` fit with the default two chains stopped with
  "incorrect number of dimensions" when the chains were pooled, for every
  family. Its goodness-of-fit statistics were stored as vectors rather than
  one-row matrices. They are now one-row matrices, and `gof_plot()` and
  `plot()` on a single-period fit draw the cross-sectional histograms; before,
  both stopped with an error even with `chains = 1`.

* `trace_plot(burn.in = , thin = )` on a fit with several chains removed the
  burn-in from the first chain only and thinned across the pooled draws. Both
  now apply within each chain.

* The Rhat column of `summary()` on a two-chain fit could disagree with
  `fit$rhat`, so a fit that passed the 1.05 gate could show an Rhat above
  1.05. The column came from `compute_mcmc_diagnostics()`, which used the
  classic statistic without splitting or rank normalisation. Both used the
  same draws, the last block of every chain. On `ame(YX_nrm$Y, Xdyad =
  YX_nrm$X, burn = 100, nscan = 1000, odens = 10)`, `igpa_dyad` showed 1.064
  in `summary()` and 1.034 in `fit$rhat`. Now both show 1.034. `summary()`,
  `fit$diagnostics$rhat`, `compute_mcmc_diagnostics()` and
  `rhat_dynamic_beta()` report the gate's statistic, so for every monitored
  coefficient and variance component the Rhat column equals `fit$rhat`. A
  one-chain fit still has no Rhat column. The draws are unchanged.

* A `lame()` fit whose `max_seconds` ran out before the first stored draw
  returned its draw arrays at their planned size, filled with `NA` (`BETA`
  with `nscan / odens` rows per chain), and posterior means of 0. The draw
  arrays now have no draws along their draw dimension, with their other
  dimnames kept. The posterior means are `NA`, `fit$no_draws_stored` is
  `TRUE`, and `print()` says that no draw was stored. `coef()`, `vcov()`,
  `confint()`, `summary()`, `predict()`, `fitted()`, `residuals()`,
  `simulate()`, `tidy()`, `glance()`, `as_draws()`, `loo()`, `waic()`,
  `latent_positions()`, `plot()`, `autoplot()`, `trace_plot()`,
  `gof_plot()`, `ab_plot()` and `uv_plot()` stop with an error of class
  `lame_no_draws`. This applies to one chain and to the pooled fit of
  several. `lame_resume(fit, nscan_more = N, max_seconds = Inf)` continues
  the chains from their start values. A pooled fit leaves out of its
  posterior means any chain that stored no draw.
  `ame()` has no `max_seconds`, and `odens > nscan` was already refused.

* The Gaussian draw of regression coefficients and additive effects is now
  exact and scale-invariant. In 1.3.x a numerical ridge made posterior SDs
  far too wide for covariates on large scales (up to about 50 times).
* Poisson MCMC fits:
  * the residual-variance update was not a valid conditional;
  * symmetric fits gave each pair two latent values, so the residual
    variance came out about twice its value;
  * half-observed dyads were accepted or rejected cell by cell;
  * sparse panels pinned effects and factors at zero and inflated the fitted
    level (about 3 times at 5% density);
  * bipartite posterior predictive draws left out overdispersion and
    exposure;
  * forecasts on the response scale omitted the overdispersion factor.
* Dynamic latent positions:
  * with `dcor = TRUE`, directed fits drew positions while ignoring the
    dyadic correlation, which made larger sparse panels run away;
  * symmetric dynamic fits could not represent a negative eigen-direction;
  * bipartite fits with static effects conditioned on time-averaged
    positions;
  * bipartite `U` / `V` scale drift;
  * a refused position draw was still kept;
  * the snap reset indicator was drawn from the wrong conditional.
* Dynamic additive effects now use the dyadic correlation when `dcor = TRUE`.
  Without it, `rho` was attenuated by about a third.
* With `dynamic_beta` plus `dynamic_ab`, the effects follow a real AR(1).
  `intercept = FALSE` with additive effects no longer discards the level of
  the predictor.
* Symmetric fits recover the additive-effect variance; in 1.3.x it was
  understated by about half. Symmetric binary fits draw one latent value
  per unordered pair.
* `dynamic_beta_per_actor` coefficient paths now enter the likelihood and
  every conditional update; refit fits made with 1.3.x. Symmetric
  `dynamic_beta` fits with both nodal and dyadic covariates updated the
  wrong coefficients.
* Panel designs drop the intercept only when the covariates span a constant
  across the whole panel. Period indicators and covariates that vary only
  between periods no longer remove it.
* The latent-factor update failed at `R = 1` and silently fell back to a
  slower path.
* Bipartite `ame()` problems fixed:
  * variance components were stored in a different column order, so
    `predict()` and `residuals()` read `rho` in place of `ve`;
  * missing normal cells attenuated every estimate;
  * ordinal and cbin/frn posterior predictives were off;
  * `odmax` was not stored;
  * `R_row` and `R_col` were both bounded by the smaller dimension;
  * `predict(newdata = )` failed with nodal covariates.
* Bipartite `lame()` problems fixed: `start_vals` were ignored, the cbin
  posterior predictive ignored `odmax`, and absent actors' covariate cells
  blocked every `G` draw.
* cbin and frn samplers count a missing cell as a possible nomination when
  deciding whether a row is full. frn fits store the ranks you supplied in
  `fit$Y`.
* `start_vals` are matched by exact name; `start_vals$b` and `start_vals$rho`
  partially matched `beta` and `rho_uv`. Code reading `fit$V` or `fit$G` on
  fits without them received `fit$VC` or `fit$GOF` through partial
  matching.
* Fixes to `predict()`, `simulate()` and `lfo()`:
  * in-sample and forecast predictions use the posterior mean of the latent
    product (including `G`, and the `U L U'` term on symmetric fits);
  * `dynamic_ab` forecasts propagate each actor's level;
  * `simulate()` draws effects and start states from their posterior and
    uses `U L U'` on symmetric fits;
  * `lfo()` uses each held-out period's covariates, scores by posterior
    predictive density, refits with the original mode, symmetry and dynamic
    settings, and no longer adds a second intercept.
* Changing actor composition no longer breaks `residuals()`,
  `predict(newdata = )`, symmetric forecasts or `latent_positions()`.
* `plot()` on `lame` fits shows the longitudinal GOF panel correctly; it had
  read the stored statistics transposed. It skips the panel with a message
  when no draws are stored.
* A run stopped by `max_seconds` divided posterior means by the planned
  number of draws instead of the completed number.
* ALS variance components on panels whose observed dyads split into
  disconnected groups could be reported as zero: the noise correction
  inverted a singular matrix whenever rounding let its Cholesky factor
  complete. It now uses the minimum-norm inverse there.
* ALS fits (`ame_als()`, `lame_als()` and `method = "als"`, static and
  dynamic, bipartite included) handle a missing covariate as `ame()` and
  `lame()` do. A cell whose dyadic, sender or receiver covariate is missing in
  its period is now unobserved, a message gives the number of such cells, and
  the coefficients are estimated from the complete cells. It had been
  modelled as 0, which biases the coefficient of a covariate that is not
  centred (a slope of 0.7 came out near 0.2 with 15% of a covariate with mean
  3 missing).
  * The per-actor mean of a node covariate ignores the periods in which it is
    missing. An actor missing a node covariate in every period has no
    observed cell on that side: an empirical-Bayes fit leaves its effect
    there to the prior (zero when the actor has no cell on either side), and
    a fixed-effects fit reports it as not estimated (`NA`, listed in
    `fit$not_estimated`).
  * A covariate that is missing everywhere stops the fit, as in `ame()` and
    `lame()`.
* Missing covariates in `ame()` and `lame()`:
  * `ame(mode = "bipartite")` kept a cell whose covariate was missing and
    warned that it was not data-augmented; the coefficient came out biased
    toward zero (a slope of 0.7 near 0.1 with 20% of a covariate with mean 3
    missing). Such a cell is now unobserved, as in the unipartite sampler and
    in `lame()`.
  * A symmetric fit leaves the whole dyad unobserved when the dyadic covariate
    of either of its two cells is missing; the other cell used to stay with a
    covariate of 0.
  * `ame()`, `lame()` (unipartite and bipartite) and the ALS routes give one
    note with the number of cells removed, in one wording. The bipartite
    warning and the "(data-augmented)" wording are gone, and the post-hoc
    log-likelihood of `ame()` no longer scores those cells.
* `update()`, `ame_als_refit()` and `ame_als_bootstrap()` work on ALS fits
  with dynamic positions. Symmetric dynamic ALS converges at `R >= 2`.
* Smaller fixes: `lame_parallel()` combines symmetric `dynamic_uv` chains;
  `posterior_quantiles(component = "UV")` works; `procrustes_align()` rotates
  `U` and `V` together, so `U V'` is preserved; `uv_plot(layout = "circle")`
  works for dynamic snapshot plots; `lame()` works through a wrapper that
  forwards `...`.
* Bundled data:
  * the `sampsonmonks` liking layers had their actors in the wrong order;
  * `addhealthc9$X` had one row too many.
* `cbin` fits with absent actors drew the cells of an absent actor
  independently of their dyad partners, which read as dyads of correlation
  zero in the update of `rho`: with 30 percent of the actors absent from three
  of four periods, a generating `rho` of 0.6 came back as 0.08 to 0.11. The
  cells are now drawn from their conditional given the partner cell (0.48 to
  0.64 over four seeds). `frn` fits and fits without absent actors are
  unchanged.
* In `ame()`, ordinal, `cbin` and `frn` fits without covariates kept the fixed
  `diag(2)` prior for the additive effects instead of the data-scaled one, so
  `ame()` and `lame()` disagreed on `va` (0.34 against 0.19 on a test panel).
  Both now use the data-scaled prior.
* `lame()` and `ame()` fits started from an ALS fit (`start_vals =
  als_start_vals(fit)`) no longer stop with "subscript out of bounds". The
  Poisson, ordinal and binary translation visits copied the actor labels of the
  start into the prior they build; with a visit at every sweep 46 of 75
  combinations of mode, family, dynamic effects and estimator failed and none
  does now. A bipartite `ame()` start (every family but normal) and a
  `dynamic_ab` start that carries one margin only also work.
* `lame()` on a normal network with almost no observed cells kept the scale of
  the factor positions at 80 to 160 times its prior median (60 actors, 4
  observed dyads); it follows the prior now (median ratio 162 to 1.09).
* A one-triangle hole of a symmetric covariate no longer leaves an asymmetric
  design slice for the hidden dyad (mirror-filled); symmetric `ame()` stores
  `b_samples`, and `posterior_quantiles(component = "ab")` works for symmetric
  fits.
* `cbin` and `frn` fits whose starting latent rows lay outside the nomination
  constraints (the start from z-scores) kept them there: the truncated-normal
  sweep never repaired a row it could not move, which pinned the actor's
  effect for the whole chain (a bipartite `frn` panel with a +303 outlier).
  Infeasible rows are repaired before each sweep; feasible states are
  untouched, and only the two bipartite `frn` fits with infeasible starts
  change.
* Static Poisson ALS fits ignored `prior$s20` (see New features) and took the
  degrees of freedom of a bipartite fit's additive effects from the larger
  side; `ame_als_refit()` of a converged empirical-Bayes fit on its own data is
  now its own fixed point (coefficients move by 3e-5, were up to 7e-3).
* `evaluate_heldout()` gains `fit`. For `family = "normal"`, `mean_logdens`
  is the normal log density at the prediction with the fit's residual
  variance: the posterior mean of `VC[, "ve"]` for an MCMC fit, or the fitted
  `ve` for a fast fit. It used the standard deviation of the held-out errors
  themselves. Without `fit` it is `NA`, and a fit that is not a normal
  `ame`, `lame` or `ame_als` fit is refused with class `lame_heldout_fit`.
* `als_dynamic_beta()` names the covariate rows of its coefficient matrix by
  the covariate slices of `Xdyad` (`"x1"`, `"x2"`, ... for unnamed slices),
  after the `"intercept"` row. They were empty, or `"v1"`, `"v2"`, ... without
  an intercept. An `Xdyad` whose number of slices changes between periods is
  refused.
* Release acceptance: the two-seed convergence gate (classic and split R-hat
  below 1.05 on every identified parameter) was run with one chain per seed
  at the other package defaults on 102 simulated configurations (six families, directed, undirected and
  bipartite networks, `ame()` and `lame()` with static, `dynamic_ab`,
  `dynamic_uv` and `dynamic_beta` specifications, and 170-actor panels).
  98 passed on the first seed pair; of the four that did not, three pass
  three of four seed pairs with failures that move between parameters, and
  the fourth (bipartite `frn` with moving positions) passes eight of eight
  seed pairs after the path move for nomination families.

## Documentation

* `?lame` states why the between-chain gate leaves out the dyadic products and
  what that means at the defaults. On stationary chains of 17 simulated
  configurations with a latent product (68 two-chain blocks) the largest
  product R-hat of a block reached 1.055, so a product gate at 1.05 would
  extend and refuse settled fits. The three acceptance configurations whose
  products failed the book's gate at the defaults passed it at four times the
  default `nscan`, and `fit$UVPM` moved by at most 0.27 posterior standard
  deviations on any dyad. A study that reports individual dyadic products keeps
  the position draws (`posterior_opts = list(save_UV = TRUE)`) and continues
  the chains with `lame_resume()` until every reported product has an R-hat
  below 1.05.

* The bipartite, dynamic-effects and overview vignettes are now articles on
  the package website (https://netify-dev.github.io/lame/articles/), which
  keeps the source package under CRAN's size limit. The other four vignettes
  (`lame`, `cross_sec_ame`, `fast_estimation` and `forecasting`) ship with
  the package; the getting-started vignette carries the notes on migrating
  from `amen`.
* The vignettes run their models when the package is built; `R CMD check`
  re-knits their text only, so the shipped HTML keeps every output.
* `?ame`, `?lame` and `?lame_resume` describe the two-chain default, the
  between-chain gate and the continuation of a refused call. The
  cross-sectional vignette reads split R-hat and the bulk and tail effective
  sample sizes of every stored parameter, and shows a run with `chains = 4`.
* `?lame` states the sparse-cbin property: at a generating sender sd of 0.25,
  the posterior mean of `va` runs up to 2.3 times the generating variance
  while its interval still covers. `?ame_als_bootstrap` gives the measured
  coverage of the bias-corrected binary fits.
* Every exported user-facing topic has a runnable example. Low-level sampler
  kernels are marked internal.
* `?lame` explains that a `dynamic_beta` coefficient follows a zero-mean
  AR(1), so `rho_beta` measures persistence of the coefficient's level. It
  also explains how the dynamic additive effects are reported.
* `?comtrade` describes the data the package ships, and its measurement
  scale is corrected.
* The `predict()`, `fitted()` and `confint()` help pages are clearer: the
  Poisson predictive mean, the coefficient-only default of `confint()`, and
  ordinal predictive draws matched to observed category frequencies.
* `latent_positions()` and `procrustes_align()` explain that alignment is
  across the periods of one fit. `uv_plot()` describes the inner-product
  latent space.
* README and vignettes:
  * the README reproducibility section uses `seed`;
  * the fast-estimation vignette reports its measured speed-ups;
  * the overview vignette builds without an X11 display.
* `?lame`, `?ame`, `?ame_als`, `?lame_als`, `?ame_als_refit`,
  `?ame_als_bootstrap` and `?als_start_vals` describe the empirical-Bayes
  estimators (what they fit, report, withhold and refuse, with the error
  classes), the dyadic correlation and the Poisson model, and `?lame` and
  `?ame` document the sampler's new `prior` switches and fit records. The fast-estimation
  vignette gains sections on normal-response fits and on dynamic binary,
  Poisson and normal fits, and a corrected table of what the fast estimators
  cover.
# lame 1.3.4
* The handful of Gibbs samplers and helpers once adapted from `amen` have been
  rewritten from the underlying published methods, so the package carries no
  derived code and stays under the MIT license.
* Fixed a prior-scaling bug that could silently collapse the latent factors in
  asymmetric `ame()` fits with `R > 0`; fits now match `amen`.
* `dynamic_ab` fits carry per-period posterior SDs, so
  `ab_plot(fit, plot_type = "ribbon")` draws a real credible band.
* A few documented options now do what they say: `log_lik_method = "augmented"`,
  `gof(nsim = NULL)` (uses all draws), and bootstrap error bars in `ab_plot()`
  for `ame_als` fits. Dropped an unused argument and fixed some stale help text.
* Fitting no longer leaves a `.Random.seed` behind or touches `options(warn)`.
* Fixed Rd markup flagged by CRAN.
* Time-varying coefficients (`dynamic_beta`) compose freely with the
  multiplicative latent factors (`R > 0`) and additive sender/receiver effects,
  for every family and network type. Coefficients can follow AR(1),
  random-walk, or Matern dynamics, and `predict()` carries that drift into its
  forecasts.
* `netify` objects can be passed straight to `ame()`, `lame()`, and the ALS
  fitters; a network's `symmetric` attribute is honored automatically, and
  named covariates are aligned to `Y` by actor.
* Set `posterior_opts = list(save_UV = TRUE)` to keep the per-draw latent
  factors (and the bipartite mixing matrix), so `latent_positions()`,
  `uv_plot()`, and the goodness-of-fit tools report posterior uncertainty
  directly. Symmetric fits now store `V_samples` (`U L` per draw) alongside
  `U_samples`, so the per-draw latent similarity `U L U'` is reconstructable
  via `simulate_posterior(fit, "UV")`.
* `summary()` on a `lame` fit exposes the coefficient table under
  `$coefficients`, matching `summary.ame` and the `broom`/`lm` idiom.
## Known limitations
* Bipartite `fit$U` / `fit$V` are a single posterior draw (the rotation is
  unidentified); use `fit$YPM` or `reconstruct_UVPM()` for the stable
  multiplicative structure.
* In the bipartite `dynamic_uv` path, latent persistence `rho_uv` is only
  weakly identified -- read it qualitatively. The unipartite path is unaffected.
# lame 1.2.0
* Cleaned up ALS support and documentation.
* Raised the `lame(method = "als")` iteration cap and exposed dynamic ALS
  convergence component traces.
* Stabilized dynamic-UV MCMC by normalizing the raw `U`/`V` coordinate scale,
  centering additive row/column effects, pooling very sparse additive effects
  toward the prior mean, and carrying ALS fits into MCMC with `als_start_vals()`.
# lame 1.1.0
## New features
* Fast, MCMC-free estimation via `ame_als()` and `lame_als()`: an alternating
  least squares / IRLS point estimator for the normal, binary, and Poisson
  families. Supports parametric-bootstrap and sandwich standard errors and the
  full S3 method set (`coef()`, `vcov()`, `confint()`, `predict()`, `tidy()`,
  `glance()`, and the diagnostic plots).
# lame 1.0.0
## Initial CRAN Submission
### Features
* Cross-sectional network analysis via `ame()` with support for 6 distributional
  families: normal, binary, ordinal, Poisson, censored binary, and fixed rank
  nomination.
* Longitudinal network analysis via `lame()` with dynamic additive and
  multiplicative effects modeled as AR(1) processes.
* Support for both unipartite (square) and bipartite (rectangular) network
  structures.
* Covariate support: dyadic (`Xdyad`), row (`Xrow`), and column (`Xcol`)
  covariates with automatic design matrix construction.
* S3 methods: `print()`, `summary()`, `coef()`, `vcov()`, `confint()`,
  `predict()`, `fitted()`, `residuals()`, `simulate()`, `plot()`.
* Visualization functions: `trace_plot()`, `gof_plot()`, `ab_plot()`,
  `uv_plot()` for MCMC diagnostics and model assessment.
* Goodness-of-fit via posterior predictive checks with `gof()`.
* C++ acceleration via Rcpp and RcppArmadillo for core sampling routines.
* Handles changing actor compositions across time periods.
