# Randomisation mendélienne : analyses de sensibilité et multivariée (MendelianRandomization 0.9.0, réglages par défaut).
#  - mode pondéré (MBE, Hartwig et al. 2017) : rapports βY/βX, ES par la méthode delta √(se_Y²/βX² + βY²·se_X²/βX⁴)
#    (défaut de la méthode mr_mbe, même si la signature générique affiche « simple »), poids normalisés se⁻² ; densité
#    gaussienne de R (density : bw = φ·0,9·min(ET, MAD)/k^(1/5), φ = 1, discrétisation linéaire sur 2 × 512 cases,
#    convolution par FFT, interpolation sur 512 points de [min − 3 bw ; max + 3 bw]) ; estimation = abscisse du maximum ;
#    ES = MAD de 10 000 estimations bootstrap (rapports tirés selon N(βY/βX, se)) ; pour une comparaison exacte,
#    200 tirages (graine 20261108) sont écrits et rejoués ;
#  - leave-one-out : IVW (réglages de mr_ivw) en retirant chaque variant ;
#  - IVW multivariée : lm(βY ~ βX₁ + … − 1, poids se_Y⁻²), ES / min(σ̂, 1) dès 4 variants, Q = (k − p)·σ̂².
# DONNÉES PUBLIÉES : jeu ldlc/hdlc/trig/chdlodds du paquet (28 variants, Waterworth et al. 2010).
source("_common.R")
suppressPackageStartupMessages(library(MendelianRandomization))
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
k <- length(ldlc)
d <- data.frame(variant = sprintf("snp%02d", 1:k), beta_ldl = ldlc, se_ldl = ldlcse, beta_hdl = hdlc, se_hdl = hdlcse,
                beta_tg = trig, se_tg = trigse, beta_chd = chdlodds, se_chd = chdloddsse)
write.csv(d, file.path(DEMO_DIR, "mr_ldl_chd.csv"), row.names = FALSE, quote = FALSE)
inp <- mr_input(bx = ldlc, bxse = ldlcse, by = chdlodds, byse = chdloddsse)
mbe <- mr_mbe(inp)
ratio <- chdlodds / ldlc; seR <- sqrt(chdloddsse^2 / ldlc^2 + chdlodds^2 * ldlcse^2 / ldlc^4)
set.seed(20261108)
draws <- t(sapply(1:200, function(i) rnorm(k, ratio, seR)))
boot <- apply(draws, 1, function(r) MendelianRandomization:::mbe_est(r, seR, 1))
loo <- sapply(1:k, function(j) { o <- mr_ivw(mr_input(ldlc[-j], ldlcse[-j], chdlodds[-j], chdloddsse[-j])); c(o@Estimate, o@StdError, o@CILower, o@CIUpper) })
mv <- mr_mvivw(mr_mvinput(bx = cbind(ldlc, hdlc, trig), bxse = cbind(ldlcse, hdlcse, trigse), by = chdlodds, byse = chdloddsse))
write_ref(list(
  mbe = list(estimate = mbe@Estimate, se = mbe@StdError, lower = mbe@CILower, upper = mbe@CIUpper, p = mbe@Pvalue),
  mbe_draws = unname(draws), mbe_boot = unname(boot), mbe_mad_200 = mad(boot),
  loo_estimate = unname(loo[1, ]), loo_se = unname(loo[2, ]), loo_lower = unname(loo[3, ]), loo_upper = unname(loo[4, ]),
  mv = list(estimate = mv@Estimate, se = mv@StdError, lower = mv@CILower, upper = mv@CIUpper, p = mv@Pvalue, rse = mv@RSE,
            q = mv@Heter.Stat[1], q_p = mv@Heter.Stat[2], model = mv@Model)
), "mr_sensibilite")
cat("mode pondéré", mbe@Estimate, "±", mbe@StdError, "\nleave-one-out : de", min(loo[1, ]), "à", max(loo[1, ]),
    "\nmultivariée (LDL, HDL, TG)", mv@Estimate, "±", mv@StdError, " Q", mv@Heter.Stat[1], "\n")
