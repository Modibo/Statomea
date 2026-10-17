# Modèle linéaire mixte pour mesures répétées (intercept et pente aléatoires par sujet), références lme4 1.1 et nlme 3.1.
#  - REML profilé de lme4 : θ = facteur de Cholesky relatif de la covariance des effets aléatoires (G = σ²ΛΛᵀ) ;
#    déviance REML d(θ) = Σᵢ log|Mᵢ| + log|XᵀV⁻¹X| + (N − p)(1 + log(2π r²/(N − p))), Mᵢ = ΛᵀZᵢᵀZᵢΛ + I,
#    r² = (y − Xβ̂)ᵀ(V/σ²)⁻¹(y − Xβ̂) ; σ̂² = r²/(N − p) ; vcov(β̂) = σ̂²(XᵀV⁻¹X)⁻¹ ; BLUP bᵢ = ΛMᵢ⁻¹ΛᵀZᵢᵀ(yᵢ − Xᵢβ̂) ;
#  - degrés de liberté de nlme (un niveau de regroupement) : terme constant dans chaque sujet → m − p_inter − 1 ;
#    autres termes (et constante) → N − m − p_intra ; p bilatérale par la loi de Student.
# DONNÉES : (1) sleepstudy (lme4 ; Belenky et al. 2003) : temps de réaction de 18 sujets sur 10 jours de privation de
# sommeil ; (2) essai simulé (demos/hba1c_longitudinal_simule.csv) : 120 patients, HbA1c à 0, 3, 6, 9 et 12 mois,
# bras A/B (pente plus forte sous B), âge ; sorties d'étude (visites manquantes).
source("_common.R")
suppressPackageStartupMessages({ library(lme4); library(nlme) })
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
data(sleepstudy)
write.csv(data.frame(sujet = paste0("S", sleepstudy$Subject), jours = sleepstudy$Days, reaction_ms = sleepstudy$Reaction),
          file.path(DEMO_DIR, "sommeil_belenky.csv"), row.names = FALSE, quote = FALSE)
set.seed(20261118)
m <- 120; vis <- c(0, 3, 6, 9, 12)
id <- rep(sprintf("P%03d", 1:m), each = length(vis)); mois <- rep(vis, m)
bras <- rep(sample(c("A", "B"), m, TRUE), each = length(vis)); age <- rep(round(rnorm(m, 55, 9)), each = length(vis))
b0 <- rep(rnorm(m, 0, 0.8), each = length(vis)); b1 <- rep(rnorm(m, 0, 0.03), each = length(vis))
hba1c <- 8.4 + 0.015 * (age - 55) + (-0.04 + b1) * mois - 0.035 * mois * (bras == "B") + b0 + rnorm(length(id), 0, 0.35)
d <- data.frame(patient = id, mois = mois, bras = bras, age = age, hba1c = round(hba1c, 2))
drop <- sample(m, 30); for (p in drop) { k <- sample(2:4, 1); d$hba1c[d$patient == sprintf("P%03d", p) & d$mois >= vis[k + 1]] <- NA }
d <- d[!is.na(d$hba1c), ]
write.csv(d, file.path(DEMO_DIR, "hba1c_longitudinal_simule.csv"), row.names = FALSE, quote = FALSE)

grab <- function(fit, lmeFit, dat, between) {
  X <- getME(fit, "X"); N <- nrow(X); mm <- length(unique(getME(fit, "flist")[[1]]))
  pB <- sum(between); pW <- ncol(X) - 1 - pB
  df <- ifelse(c(FALSE, between), mm - pB - 1, N - mm - pW)
  se <- sqrt(diag(as.matrix(vcov(fit)))); tv <- fixef(fit) / se
  vc <- as.data.frame(VarCorr(fit))
  re <- ranef(fit)[[1]]
  list(theta = unname(getME(fit, "theta")), reml = unname(REMLcrit(fit)), beta = unname(fixef(fit)), se = unname(se), t = unname(tv),
       df = unname(df), p = unname(2 * pt(-abs(tv), df)), sigma = sigma(fit), vc_sdcor = vc$sdcor,
       nlme_df = unname(summary(lmeFit)$tTable[, "DF"]), nlme_beta = unname(fixef(lmeFit)),
       blup_first = unname(as.matrix(re[1:3, , drop = FALSE])), N = N, m = mm)
}
ctl <- lmerControl(optimizer = "bobyqa", optCtrl = list(rhobeg = 0.2, rhoend = 1e-12, maxfun = 1e5))
s1 <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy, REML = TRUE, control = ctl)
s1n <- lme(Reaction ~ Days, random = ~ Days | Subject, data = sleepstudy)
s0 <- lmer(Reaction ~ Days + (1 | Subject), sleepstudy, REML = TRUE, control = ctl)
s0n <- lme(Reaction ~ Days, random = ~ 1 | Subject, data = sleepstudy)
h1 <- lmer(hba1c ~ mois * bras + age + (mois | patient), d, REML = TRUE, control = ctl)
h1n <- lme(hba1c ~ mois * bras + age, random = ~ mois | patient, data = d, control = lmeControl(opt = "optim"))
write_ref(list(sleep_slope = grab(s1, s1n, sleepstudy, c(FALSE)), sleep_int = grab(s0, s0n, sleepstudy, c(FALSE)),
               hba1c = grab(h1, h1n, d, c(FALSE, TRUE, TRUE, FALSE)), hba1c_n = nrow(d)), "lmm_longitudinal")
print(summary(s1)$coef); print(VarCorr(s1)); print(summary(h1)$coef); cat("N hba1c", nrow(d), "\n")
