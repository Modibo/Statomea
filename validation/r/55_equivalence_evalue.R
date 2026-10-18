# Équivalence, non-infériorité et valeur E, références TOSTER 0.8.0 et EValue 4.1.3 :
#  - TOST (deux tests unilatéraux) sur deux moyennes indépendantes (Welch ou Student) ou appariées : t₁ = (d − Δ_inf)/ES,
#    t₂ = (d − Δ_sup)/ES, p = max(p₁, p₂) ; IC à 1 − 2α (t_TOST, tsum_TOST) ;
#  - deux proportions : différence, ES non poolée, tests z (twoprop_test, alternative = "equivalence") ;
#  - non-infériorité : un seul test unilatéral contre la marge (t.test alternative = "greater"/"less", mu = −Δ/+Δ) ;
#  - valeur E (VanderWeele et Ding 2017) : E = RR* + √(RR*(RR* − 1)), RR* = RR ou 1/RR ; OR et HR fréquents convertis
#    (√OR ; (1 − 0,5^√HR)/(1 − 0,5^√(1/HR))) ; différence standardisée : RR ≈ exp(0,91·d), IC exp(0,91·d ± 1,78·ES).
# DONNÉES : essai simulé de deux formulations (pression artérielle, mmHg) ; mesures appariées simulées ; proportions
# (guérison 0,62 contre 0,58, n = 150 et 140) ; exemples de valeur E (RR, OR, HR, différence de moyennes).
source("_common.R")
suppressPackageStartupMessages({ library(TOSTER); library(EValue) })
set.seed(20261219)
a <- round(rnorm(48, 132, 11), 1); b <- round(rnorm(52, 131, 13), 1)
write.csv(data.frame(pas = c(a, b), formulation = rep(c("generique", "reference"), c(48, 52))),
          file.path("..", "..", "demos", "equivalence_formulations_simule.csv"), row.names = FALSE, quote = FALSE)
pre <- round(rnorm(30, 6.8, 0.9), 2); post <- round(pre + rnorm(30, -0.05, 0.25), 2)
tost <- function(r) {
  tt <- r$TOST; es <- r$effsize
  list(t = unname(tt[, "t"]), df = unname(tt[, "df"]), p = unname(tt[, "p.value"]),
       ci = unname(unlist(es["Raw", c("lower.ci", "upper.ci")])), est = unname(es["Raw", "estimate"]))
}
w <- tost(t_TOST(x = a, y = b, low_eqbound = -5, high_eqbound = 5, alpha = 0.05))
s <- tost(t_TOST(x = a, y = b, low_eqbound = -5, high_eqbound = 5, alpha = 0.05, var.equal = TRUE))
pa <- tost(t_TOST(x = post, y = pre, paired = TRUE, low_eqbound = -0.2, high_eqbound = 0.2, alpha = 0.05))
pr <- twoprop_test(0.62, 0.58, 150, 140, null = c(-0.1, 0.1), alternative = "equivalence")
ni <- t.test(a, b, alternative = "greater", mu = -4)       # non-infériorité : marge 4 mmHg, plus haut = mieux
ev <- function(x) unname(x[2, ])
write_ref(list(a = a, b = b, pre = pre, post = post, welch = w, student = s, paired = pa,
               prop = list(z = unname(pr$statistic), p = pr$p.value, ci = unname(pr$conf.int)),
               noninf = list(t = unname(ni$statistic), df = unname(ni$parameter), p = ni$p.value, lower = ni$conf.int[1]),
               ev_rr = ev(evalues.RR(1.8, 1.3, 2.5)), ev_rr_protect = ev(evalues.RR(0.6, 0.45, 0.8)),
               ev_rr_null = ev(evalues.RR(1.3, 0.9, 1.9)), ev_or_common = ev(evalues.OR(2.2, 1.4, 3.5, rare = FALSE)),
               ev_or_rare = ev(evalues.OR(2.2, 1.4, 3.5, rare = TRUE)), ev_hr_common = ev(evalues.HR(0.7, 0.55, 0.9, rare = FALSE)),
               ev_md = ev(evalues.MD(0.5, se = 0.15))), "equivalence_evalue")
print(t_TOST(x = a, y = b, low_eqbound = -5, high_eqbound = 5)); print(evalues.HR(0.7, 0.55, 0.9, rare = FALSE)); print(evalues.MD(0.5, se = 0.15))
