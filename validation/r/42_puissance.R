# Atelier de puissance et de taille d'échantillon : références pwr 1.3, powerSurvEpi 0.1.3 et stats.
#  - deux moyennes : pwr::pwr.t2n.test (groupes inégaux, test bilatéral à deux queues), power.t.test(strict = TRUE)
#    pour apparié et un échantillon ; puissance pour n donné et n pour puissance donnée ;
#  - deux proportions : power.prop.test (puissance pour n donné) ;
#  - cas-témoins non apparié : OR, fréquence de l'exposition chez les témoins p0, k témoins par cas ;
#    p1 = OR·p0/(1 + p0(OR − 1)) ; pwr::pwr.2p2n.test (transformation arcsinus, h = 2 asin √p1 − 2 asin √p0) ;
#  - survie (essai à deux bras) : formule de Freedman, powerSurvEpi::ssizeCT.default / powerCT.default ;
#    probabilité d'événement du bras expérimental sous risques proportionnels pE = 1 − (1 − pC)^HR ;
#    nombre d'événements de Schoenfeld d = (z₁₋α/₂ + z₁₋β)²·(1 + k)²/(k·log²HR) (formule) ;
#  - GWAS, test allélique cas-témoins : OR par allèle, fréquence p0 chez les témoins, p1 = OR·p0/(1 + p0(OR − 1)) ;
#    non-centralité λ = (p1 − p0)²/[p̄(1 − p̄)(1/(2Nca) + 1/(2Nco))], p̄ pondéré par les allèles ;
#    puissance = P(χ²₁(λ) > χ²₁;₁₋α) (pchisq non central), α = 5e-8.
source("_common.R")
suppressPackageStartupMessages({ library(pwr); library(powerSurvEpi) })
tol <- 1e-12
# Deux moyennes
m_pow <- pwr.t2n.test(n1 = 40, n2 = 80, d = 0.5)$power
m_n2 <- uniroot(function(n) pwr.t2n.test(n1 = n, n2 = 2 * n, d = 0.5)$power - 0.9, c(3, 1e4), tol = tol)$root
m_eq <- uniroot(function(n) pwr.t2n.test(n1 = n, n2 = n, d = 0.4)$power - 0.8, c(3, 1e4), tol = tol)$root
paired <- power.t.test(delta = 3, sd = 8, power = 0.85, type = "paired", strict = TRUE, tol = tol)$n
paired_pow <- power.t.test(n = 50, delta = 3, sd = 8, type = "paired", strict = TRUE)$power
one <- power.t.test(delta = 0.3, sd = 1, power = 0.8, type = "one.sample", strict = TRUE, tol = tol)$n
# Deux proportions : puissance pour n donné
pp <- power.prop.test(n = 150, p1 = 0.30, p2 = 0.18)$power
# Cas-témoins
or <- 2; p0 <- 0.20; k <- 2
p1 <- or * p0 / (1 + p0 * (or - 1)); h <- 2 * asin(sqrt(p1)) - 2 * asin(sqrt(p0))
cc_n <- uniroot(function(n) pwr.2p2n.test(h = h, n1 = n, n2 = k * n)$power - 0.8, c(3, 1e6), tol = tol)$root
cc_pow <- pwr.2p2n.test(h = h, n1 = 120, n2 = 240)$power
# Survie (Freedman)
hr <- 0.7; pC <- 0.45; pE <- 1 - (1 - pC)^hr; ks <- 1
s_n <- ssizeCT.default(power = 0.8, k = ks, pE = pE, pC = pC, RR = hr, alpha = 0.05)
za <- qnorm(0.975); zb <- qnorm(0.8)
s_m <- ((ks * hr + 1) / (hr - 1))^2 * (za + zb)^2 / ks
s_pow <- powerCT.default(nE = 300, nC = 300, pE = pE, pC = pC, RR = hr, alpha = 0.05)
schoen <- (za + zb)^2 * (1 + ks)^2 / (ks * log(hr)^2)
# GWAS
gw <- function(maf, or, nca, nco, alpha = 5e-8) {
  q1 <- or * maf / (1 + maf * (or - 1)); pbar <- (q1 * nca + maf * nco) / (nca + nco)
  lam <- (q1 - maf)^2 / (pbar * (1 - pbar) * (1 / (2 * nca) + 1 / (2 * nco)))
  c(lambda = lam, power = pchisq(qchisq(1 - alpha, 1), 1, ncp = lam, lower.tail = FALSE))
}
g1 <- gw(0.25, 1.2, 5000, 5000); g2 <- gw(0.05, 1.3, 3000, 6000)
g_n <- uniroot(function(n) gw(0.25, 1.15, n, n)[["power"]] - 0.8, c(10, 1e7), tol = tol)$root
write_ref(list(means = list(power_40_80 = m_pow, n1_ratio2 = m_n2, n_equal_d04 = m_eq, paired_n = paired, paired_power = paired_pow, one_n = one),
               props = list(power_150 = pp),
               cc = list(p1 = p1, h = h, n_cases = cc_n, power_120_240 = cc_pow),
               surv = list(pE = pE, nE = unname(s_n[1]), nC = unname(s_n[2]), m = s_m, power_300 = s_pow, schoenfeld = schoen),
               gwas = list(lambda1 = g1[["lambda"]], power1 = g1[["power"]], lambda2 = g2[["lambda"]], power2 = g2[["power"]], n_equal = g_n)), "puissance")
cat("moyennes", m_pow, m_n2, m_eq, paired, one, "\ncas-témoins n", cc_n, "puissance", cc_pow, "\nsurvie", s_n, s_pow, schoen, "\nGWAS", g1, g2, g_n, "\n")
