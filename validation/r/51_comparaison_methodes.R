# Comparaison de deux méthodes de mesure (laboratoire), références mcr 1.3.3 :
#  - Passing-Bablok (1983) : pente = médiane décalée des pentes de paires (pentes < −1 comptées K fois en tête, pente −1
#    exclue), IC analytique (rangs M1 = arrondi((N − C)/2), M2 = N − M1 + 1, C = z·√(n(n−1)(2n+5)/18)) ;
#    ordonnée = médiane(yᵢ − b·xᵢ), IC par les bornes de pente ; implémentation de référence ci-dessous (« classique »)
#    et mcr (angles, calc_PaBa) ;
#  - Deming : rapport des variances d'erreur λ = σ²(x)/σ²(y) (error.ratio de mcr) ; IC jackknife (pseudo-valeurs,
#    ES = sd/√n, quantile t à n − 2 ddl : mcr::mc.calcLinnetCI) ;
#  - biais au niveau de décision X꜀ : a + (b − 1)·X꜀.
# DONNÉES : créatinine sérique et plasmatique (mcr::creatinine, mg/dL, 110 patients ; 2 lignes incomplètes retirées).
source("_common.R")
suppressPackageStartupMessages(library(mcr))
data(creatinine)
cr <- na.omit(creatinine)
names(cr) <- c("creatinine_serum", "creatinine_plasma")
write.csv(cr, file.path("..", "..", "demos", "creatinine_serum_plasma.csv"), row.names = FALSE, quote = FALSE)
x <- cr$creatinine_serum; y <- cr$creatinine_plasma
paba_classic <- function(x, y, alpha = 0.05) {
  n <- length(x); S <- c()
  for (i in 1:(n - 1)) for (j in (i + 1):n) {
    dx <- x[j] - x[i]; dy <- y[j] - y[i]
    if (dx == 0 && dy == 0) next
    s <- if (dx == 0) sign(dy) * Inf else dy / dx
    if (s == -1) next
    S <- c(S, s)
  }
  S <- sort(S); N <- length(S); K <- sum(S < -1)
  b <- if (N %% 2 == 1) S[(N + 1) / 2 + K] else (S[N / 2 + K] + S[N / 2 + 1 + K]) / 2
  C <- qnorm(1 - alpha / 2) * sqrt(n * (n - 1) * (2 * n + 5) / 18)
  M1 <- round((N - C) / 2); M2 <- N - M1 + 1
  bl <- S[M1 + K]; bu <- S[M2 + K]
  list(slope = c(b, bl, bu), intercept = c(median(y - b * x), median(y - bu * x), median(y - bl * x)), N = N, K = K)
}
pc <- paba_classic(x, y)
pb <- mcreg(x, y, method.reg = "PaBa", method.ci = "analytical", alpha = 0.05)
dm1 <- mcreg(x, y, method.reg = "Deming", method.ci = "jackknife", error.ratio = 1)
dm2 <- mcreg(x, y, method.reg = "Deming", method.ci = "jackknife", error.ratio = 2)
cf <- function(m) list(intercept = unname(getCoefficients(m)[1, c(1, 3, 4)]), slope = unname(getCoefficients(m)[2, c(1, 3, 4)]),
                       se = unname(getCoefficients(m)[, 2]))
kt <- cor.test(x, y, method = "kendall", exact = FALSE)
# Petit jeu (n = 20) avec ex aequo et une paire verticale (x identiques) : cas limites de Passing-Bablok.
xs <- c(1.0, 1.2, 1.2, 1.5, 1.7, 2.0, 2.1, 2.4, 2.4, 2.8, 3.0, 3.3, 3.5, 3.9, 4.2, 4.4, 4.8, 5.1, 5.5, 6.0)
ys <- c(1.1, 1.1, 1.4, 1.6, 1.6, 2.2, 2.0, 2.6, 2.5, 2.9, 3.3, 3.2, 3.8, 4.1, 4.3, 4.9, 5.0, 5.6, 5.7, 6.5)
ps <- paba_classic(xs, ys); pbs <- mcreg(xs, ys, method.reg = "PaBa", method.ci = "analytical")
write_ref(list(n = length(x), paba_classic = pc, paba_mcr = cf(pb), deming1 = cf(dm1), deming2 = cf(dm2),
               kendall = list(tau = unname(kt$estimate), p = kt$p.value),
               bias_levels = c(1, 2, 4), small = list(x = xs, y = ys, classic = ps, mcr = cf(pbs))), "comparaison_methodes")
printSummary(pb); printSummary(dm1)
print(pc[c("slope", "intercept")])
