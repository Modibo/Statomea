# PCR quantitative : courbe standard (lm ; efficacité E = 10^(−1/pente) − 1), quantification relative ΔΔCt (Livak ;
# IC par t.test de Welch sur les ΔCt) et Pfaffl, limite de détection probit (glm probit, MASS::dose.p). Données simulées.
source("_common.R")
suppressPackageStartupMessages(library(MASS))
set.seed(20261015)
lq <- rep(1:6, each = 3)                      # log10 copies
ct <- round(38.5 - 3.42 * lq + rnorm(18, 0, 0.18), 2)
sc <- lm(ct ~ lq); ci <- confint(sc)["lq", ]
unk <- c(24.81, 30.12, 17.40)
std <- list(log10q = lq, ct = ct, slope = unname(coef(sc)[2]), intercept = unname(coef(sc)[1]), r2 = summary(sc)$r.squared,
            slope_ci = unname(ci), eff = 10^(-1 / unname(coef(sc)[2])) - 1, eff_ci = sort(10^(-1 / unname(ci)) - 1),
            unknown_ct = unk, unknown_log10q = (unk - coef(sc)[1]) / coef(sc)[2])
# ΔΔCt : gène cible et gène de référence, témoins (n = 6) et traités (n = 6), cible surexprimée ×4 environ.
ref_c <- round(rnorm(6, 20, 0.3), 2); ref_t <- round(rnorm(6, 20.1, 0.3), 2)
tgt_c <- round(ref_c + 6 + rnorm(6, 0, 0.35), 2); tgt_t <- round(ref_t + 4 + rnorm(6, 0, 0.35), 2)
dc <- tgt_c - ref_c; dt <- tgt_t - ref_t
tt <- t.test(dt, dc)
ddct <- unname(mean(dt) - mean(dc))
Et <- 1.94; Er <- 1.98   # facteurs d'amplification (1 + efficacité)
pf <- Et^(mean(tgt_c) - mean(tgt_t)) / Er^(mean(ref_c) - mean(ref_t))
dd <- list(tgt_c = tgt_c, ref_c = ref_c, tgt_t = tgt_t, ref_t = ref_t, ddct = ddct, ddct_ci = unname(tt$conf.int), p = tt$p.value,
           df = unname(tt$parameter), fold = 2^(-ddct), fold_ci = sort(2^(-unname(tt$conf.int))), Et = Et, Er = Er, pfaffl = pf)
# Limite de détection : 6 concentrations (copies/réaction), 20 réplicats chacune.
conc <- c(2, 5, 10, 20, 50, 100); n <- rep(20, 6)
det <- c(5, 10, 15, 18, 20, 20)
m <- glm(cbind(det, n - det) ~ log10(conc), family = binomial(link = "probit"), control = glm.control(epsilon = 1e-14, maxit = 100))
dp <- dose.p(m, p = 0.95)
lod <- list(conc = conc, n = n, det = det, coef = unname(coef(m)), log10_lod95 = unname(dp[1]), se = as.vector(attr(dp, "SE")),
            lod95 = 10^unname(dp[1]), lod95_ci = 10^(unname(dp[1]) + c(-1, 1) * qnorm(.975) * as.vector(attr(dp, "SE"))))
write_ref(list(std = std, dd = dd, lod = lod), "qpcr")
