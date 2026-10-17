# Régression logistique ordinale (cotes proportionnelles) et multinomiale, références MASS 7.3 (polr) et nnet 7.3
# (multinom, convergence resserrée).
#  - polr : logit P(Y ≤ k) = ζₖ − xᵀβ ; maximum de vraisemblance, ES par l'inverse de la hessienne ;
#  - multinom : logit de référence log(P(Y = k)/P(Y = 1)) = xᵀβₖ ; ES par l'inverse de la hessienne.
# DONNÉES (MASS::housing, Madsen 1976) : satisfaction (faible < moyenne < élevée) de 1 681 locataires de Copenhague selon
# l'influence perçue sur la gestion, le type de logement et le contact avec les voisins ; table développée en individus.
source("_common.R")
suppressPackageStartupMessages({ library(MASS); library(nnet) })
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
h <- housing[rep(seq_len(nrow(housing)), housing$Freq), c("Sat", "Infl", "Type", "Cont")]
d <- data.frame(satisfaction = c(Low = "1_faible", Medium = "2_moyenne", High = "3_elevee")[as.character(h$Sat)],
                influence = c(Low = "faible", Medium = "moyenne", High = "forte")[as.character(h$Infl)],
                logement = c(Tower = "tour", Apartment = "appartement", Atrium = "atrium", Terrace = "maison_rangee")[as.character(h$Type)],
                contact = c(Low = "faible", High = "fort")[as.character(h$Cont)])
write.csv(d, file.path(DEMO_DIR, "satisfaction_logement.csv"), row.names = FALSE, quote = FALSE)
d$satisfaction <- factor(d$satisfaction, ordered = TRUE)
d$influence <- factor(d$influence, levels = c("faible", "moyenne", "forte"))
d$logement <- factor(d$logement, levels = c("tour", "appartement", "atrium", "maison_rangee"))
d$contact <- factor(d$contact, levels = c("faible", "fort"))
po <- polr(satisfaction ~ influence + logement + contact, data = d, Hess = TRUE, control = list(reltol = 1e-14, maxit = 1000))
mn <- multinom(factor(satisfaction, ordered = FALSE) ~ influence + logement + contact, data = d, Hess = TRUE, reltol = 1e-14, maxit = 2000, trace = FALSE)
vp <- vcov(po); vm <- vcov(mn)
write_ref(list(polr = list(beta = unname(coef(po)), zeta = unname(po$zeta), se = unname(sqrt(diag(vp))), loglik = as.numeric(logLik(po))),
               multinom = list(coef = unname(as.vector(t(coef(mn)))), se = unname(sqrt(diag(vm))), loglik = as.numeric(logLik(mn))),
               n = nrow(d)), "ordinal")
print(summary(po)$coefficients); cat("logLik polr", logLik(po), " multinom", logLik(mn), "\n"); print(coef(mn))
