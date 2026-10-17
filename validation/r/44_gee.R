# Équations d'estimation généralisées (GEE) pour données répétées, références geepack 1.3.9 (geeglm) et gee 4.13.
#  - familles gaussienne (identité), binomiale (logit), Poisson (log) ; corrélation de travail indépendante ou échangeable ;
#  - itérations : β par scores de Fisher avec V = φ·A½R(α)A½ ; résidus de Pearson r ;
#    geepack : φ = Σr²/N, α = Σᵢ Σⱼ<ₖ rᵢⱼrᵢₖ / [φ·Σᵢ nᵢ(nᵢ − 1)/2] ;
#    gee (Liang-Zeger) : φ = Σr²/(N − p), α = … / [φ·(Σᵢ nᵢ(nᵢ − 1)/2 − p)] ;
#  - variance robuste (sandwich) A⁻¹BA⁻¹, B = Σᵢ DᵢᵀVᵢ⁻¹eᵢeᵢᵀVᵢ⁻¹Dᵢ.
# DONNÉES : essai simulé HbA1c (demos/hba1c_longitudinal_simule.csv, script 43) ; issue binaire « contrôle » = HbA1c < 7,8 ;
# comptage « hypoglycemies ».
source("_common.R")
suppressPackageStartupMessages({ library(geepack); library(gee) })
d <- read.csv(file.path("..", "..", "demos", "hba1c_longitudinal_simule.csv"))
d$id <- as.integer(factor(d$patient, levels = unique(d$patient))); d <- d[order(d$id, d$mois), ]; d$ctl <- as.integer(d$hba1c < 7.8)
gp <- function(f, fam, cs) { g <- geeglm(f, data = d, id = id, family = fam, corstr = cs, control = geese.control(epsilon = 1e-12, maxit = 100))
  s <- summary(g)$coef; list(beta = unname(coef(g)), se = unname(s[, 2]), p = unname(s[, 4]), alpha = if (cs == "independence") 0 else unname(unlist(g$geese$alpha)), phi = unname(unlist(g$geese$gamma))) }
gl <- function(f, fam, cs) { g <- gee(f, data = d, id = id, family = fam, corstr = cs, silent = TRUE, tol = 1e-12, maxiter = 100)
  list(beta = unname(coef(g)), se = unname(sqrt(diag(g$robust.variance))), alpha = if (cs == "independence") 0 else g$working.correlation[1, 2], phi = g$scale) }
fg <- hba1c ~ mois * bras + age; fb <- ctl ~ mois * bras + age; fc <- hypoglycemies ~ mois + bras
write_ref(list(gauss_exch_geepack = gp(fg, gaussian, "exchangeable"), gauss_exch_gee = gl(fg, gaussian, "exchangeable"),
               bin_exch_geepack = gp(fb, binomial, "exchangeable"), bin_exch_gee = gl(fb, binomial, "exchangeable"),
               bin_ind_geepack = gp(fb, binomial, "independence"), pois_exch_geepack = gp(fc, poisson, "exchangeable"),
               pois_exch_gee = gl(fc, poisson, "exchangeable"), n = nrow(d)), "gee")
cat("ok\n"); print(summary(geeglm(fb, data = d, id = id, family = binomial, corstr = "exchangeable"))$coef)
