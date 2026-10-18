# Bayésien d'introduction, références stats (qbeta, pbeta, qnorm, pnorm) :
#  - proportion : a priori Bêta(a, b), a posteriori Bêta(a + x, b + n − x) ; moyenne, médiane, mode, intervalle de
#    crédibilité à queues égales, P(p > seuil) ; a priori uniforme Bêta(1, 1), de Jeffreys Bêta(0,5 ; 0,5), informatif
#    (moyenne m, poids n₀ : a = m·n₀, b = (1 − m)·n₀) ;
#  - effet (Spiegelhalter) : vraisemblance normale θ̂ ~ N(θ, ES²) sur l'échelle log pour un rapport (ES déduit de l'IC à
#    95 %), a priori N(μ₀, τ²) ; a posteriori normal (précisions additionnées) ; a priori sceptique (centré sur 0,
#    P(effet au-delà de la cible) = 5 %), enthousiaste (centré sur la cible, même largeur), vague (τ = 10) ;
#    P(bénéfice) = P(θ < 0) et P(θ < log(cible)).
# DONNÉES : 7 événements sur 40 ; essai publié résumé par RR = 0,75 (IC 95 % 0,58 à 0,97), cible RR = 0,80.
source("_common.R")
prop <- function(x, n, a, b, thr) {
  A <- a + x; B <- b + n - x
  list(a = A, b = B, mean = A / (A + B), median = qbeta(0.5, A, B), mode = (A - 1) / (A + B - 2),
       ci = qbeta(c(0.025, 0.975), A, B), p_gt = 1 - pbeta(thr, A, B))
}
eff <- function(est, lo, hi, mu0, tau, target) {
  th <- log(est); se <- (log(hi) - log(lo)) / (2 * qnorm(0.975))
  prec <- 1 / tau^2 + 1 / se^2; m <- (mu0 / tau^2 + th / se^2) / prec; s <- sqrt(1 / prec)
  list(theta = th, se = se, post_mean = m, post_sd = s, ci = exp(m + c(-1, 1) * qnorm(0.975) * s),
       p_benefit = pnorm(0, m, s), p_target = pnorm(log(target), m, s))
}
tauS <- abs(log(0.8)) / qnorm(0.95)   # a priori sceptique : P(RR < 0,80) = 5 %
write_ref(list(uniform = prop(7, 40, 1, 1, 0.1), jeffreys = prop(7, 40, 0.5, 0.5, 0.1), informative = prop(7, 40, 0.1 * 20, 0.9 * 20, 0.1),
               tau_sceptical = tauS,
               sceptical = eff(0.75, 0.58, 0.97, 0, tauS, 0.8), enthusiastic = eff(0.75, 0.58, 0.97, log(0.8), tauS, 0.8),
               vague = eff(0.75, 0.58, 0.97, 0, 10, 0.8)), "bayesien")
print(prop(7, 40, 1, 1, 0.1)); print(eff(0.75, 0.58, 0.97, 0, tauS, 0.8))
