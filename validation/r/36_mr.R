# Randomisation mendélienne à partir de statistiques résumées (variants instrumentaux) :
#  - IVW (pondération simple, poids 1/se_Y²) : lm(βY ~ βX − 1) ; effets aléatoires multiplicatifs (ES / min(σ̂, 1)) dès
#    4 variants, effets fixes (ES / σ̂) sinon ; loi normale ; hétérogénéité Q = (k − 1)·σ̂², ddl k − 1 ;
#  - MR-Egger : variants orientés (βX > 0), lm(βY ~ βX) pondéré, ES × max(1, σ̂), loi normale ; intercept = pléiotropie
#    directionnelle ; Q de Rücker (k − 2 ddl) ; I²_GX ;
#  - médiane pondérée : rapports βY/βX, poids (βX/se_Y)², médiane par interpolation des poids cumulés centrés ;
#    ES par bootstrap paramétrique (βX* ~ N(βX, se_X), βY* ~ N(βY, se_Y), poids fixes), écart-type des médianes ;
#  - F moyen = moyenne de (βX/se_X)².
# Référence : MendelianRandomization 0.9.0 (mr_ivw, mr_egger, mr_median « weighted », 10 000 itérations, graine
# 314159265). Pour comparer exactement le bootstrap, 200 tirages R (graine 20261107) sont écrits et rejoués par Statoméa.
# DONNÉES PUBLIÉES : 28 variants associés au LDL-cholestérol (βX, mmol/L) et leurs associations avec la maladie
# coronarienne (βY, log-odds) — jeu d'exemple ldlc/chdlodds du paquet MendelianRandomization (Waterworth et al. 2010).
source("_common.R")
suppressPackageStartupMessages(library(MendelianRandomization))
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
k <- length(ldlc)
d <- data.frame(variant = sprintf("snp%02d", 1:k), beta_ldl = ldlc, se_ldl = ldlcse, beta_hdl = hdlc, se_hdl = hdlcse,
                beta_tg = trig, se_tg = trigse, beta_chd = chdlodds, se_chd = chdloddsse)   # même fichier que 37_mr_sensibilite.R
write.csv(d, file.path(DEMO_DIR, "mr_ldl_chd.csv"), row.names = FALSE, quote = FALSE)
inp <- mr_input(bx = ldlc, bxse = ldlcse, by = chdlodds, byse = chdloddsse)
iv <- mr_ivw(inp); ivf <- mr_ivw(inp, model = "fixed"); eg <- mr_egger(inp); wm <- mr_median(inp, weighting = "weighted")
# Tirages exacts pour le bootstrap.
set.seed(20261107)
w <- (ldlc / chdloddsse)^2
draws <- t(sapply(1:200, function(i) c(rnorm(k, ldlc, ldlcse), rnorm(k, chdlodds, chdloddsse))))
med <- apply(draws, 1, function(r) MendelianRandomization:::weighted.median(r[(k + 1):(2 * k)] / r[1:k], w))
s <- function(o) list(estimate = o@Estimate, se = o@StdError, lower = o@CILower, upper = o@CIUpper, p = o@Pvalue)
write_ref(list(
  k = k,
  ivw = c(s(iv), list(q = iv@Heter.Stat[1], q_p = iv@Heter.Stat[2], rse = iv@RSE, fstat = iv@Fstat)),
  ivw_fixed = s(ivf),
  egger = c(list(estimate = eg@Estimate, se = eg@StdError.Est, lower = eg@CILower.Est, upper = eg@CIUpper.Est, p = eg@Pvalue.Est), list(intercept = eg@Intercept, se_intercept = eg@StdError.Int, lower_intercept = eg@CILower.Int, upper_intercept = eg@CIUpper.Int,
                        p_intercept = eg@Pvalue.Int, q = eg@Heter.Stat[1], q_p = eg@Heter.Stat[2], i2gx = eg@I.sq, rse = eg@RSE)),
  median = s(wm), draws = unname(draws), boot_sd_200 = sd(med)
), "mr")
cat("IVW", iv@Estimate, "±", iv@StdError, " Egger", eg@Estimate, "±", eg@StdError.Est, "intercept", eg@Intercept, "p", eg@Pvalue.Int,
    " I²GX", eg@I.sq, "\nmédiane pondérée", wm@Estimate, "±", wm@StdError, " ; F moyen", iv@Fstat, " ; OR IVW par mmol/L", exp(iv@Estimate), "\n")
