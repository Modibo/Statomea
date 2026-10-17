# Temps moyen de survie restreint (RMST) et analyse landmark, références survRM2 1.0.4 et survival 3.5.
#  - RMST(τ) = aire sous la courbe de Kaplan-Meier jusqu'à τ ; variance Σ (∫_{tⱼ}^{τ} S)² dⱼ/[nⱼ(nⱼ − dⱼ)] (survRM2::rmst1) ;
#    RMTL = τ − RMST ; comparaison de deux bras : différence (ES = √(v₁ + v₀)), rapport des RMST et des RMTL (échelle log,
#    méthode delta), IC et p normaux (survRM2::rmst2) ;
#  - landmark à L jours : sujets encore suivis à L, statut d'exposition figé à L (greffé avant L ou non), temps repris
#    depuis L ; Kaplan-Meier, log-rank (survdiff), Cox (coxph, Efron).
# DONNÉES : essai veteran (survival ; cancer du poumon, traitement standard contre test), test/reference/cox_veteran.csv ;
# greffe cardiaque de Stanford (demos/greffe_stanford.csv, script 41).
source("_common.R")
suppressPackageStartupMessages({ library(survRM2); library(survival) })
vet <- read.csv(file.path(REF_DIR, "cox_veteran.csv"))
vet$status <- as.integer(vet$deces == "oui"); vet$arm <- as.integer(vet$trt == "test")
r <- function(tau) {
  z <- rmst2(vet$time, vet$status, vet$arm, tau = tau)
  list(tau = tau, arm1 = unname(z$RMST.arm1$result[1, ]), arm0 = unname(z$RMST.arm0$result[1, ]),
       rmtl1 = unname(z$RMST.arm1$result[2, ]), var1 = z$RMST.arm1$rmst.var, var0 = z$RMST.arm0$rmst.var,
       diff = unname(z$unadjusted.result[1, ]), ratio = unname(z$unadjusted.result[2, ]), rmtl_ratio = unname(z$unadjusted.result[3, ]))
}
st <- read.csv(file.path("..", "..", "demos", "greffe_stanford.csv"))
lm <- function(L) {
  s <- st[st$jours > L, ]
  s$greffe_L <- ifelse(!is.na(s$attente_greffe) & s$attente_greffe <= L, "oui", "non")
  s$t <- s$jours - L; s$ev <- as.integer(s$deces == "oui")
  km <- survfit(Surv(t, ev) ~ greffe_L, data = s); lr <- survdiff(Surv(t, ev) ~ greffe_L, data = s)
  cx <- coxph(Surv(t, ev) ~ (greffe_L == "oui") + age, data = s)
  list(L = L, n = nrow(s), n_greffe = sum(s$greffe_L == "oui"), events = sum(s$ev), logrank = unname(lr$chisq),
       coef = unname(coef(cx)), se = unname(sqrt(diag(vcov(cx)))))
}
write_ref(list(rmst300 = r(300), rmst200 = r(200), lm30 = lm(30), lm60 = lm(60)), "rmst_landmark")
print(rmst2(vet$time, vet$status, vet$arm, tau = 300)); print(lm(30)[c("n", "n_greffe", "coef")])
