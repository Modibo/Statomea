# Splines cubiques restreintes (Harrell), références rms 6.7 et Hmisc :
#  - nœuds : Hmisc::rcspline.eval (quantiles 0,05…0,95, ou 0,10/0,50/0,90 pour 3 nœuds ; < 100 valeurs : 5e plus petite
#    et 5e plus grande valeur) ; base de rms::rcs (normalisation (t_k − t_1)^(2/3)) ;
#  - coefficients et ES (ols, lrm, cph Efron) ; anova de rms (Wald : F pour ols, χ² sinon) : association globale et
#    non-linéarité ; Predict(ref.zero = TRUE) : contraste f(x) − f(médiane) et IC (t pour ols, normal sinon).
#  - lrm et cph avec eps = 1e-12 : leurs critères d'arrêt par défaut (cph : eps = 1e-4) laissent un écart relatif
#    de 1e-7 à 4e-3 sur les coefficients ; resserrés, ils rejoignent glm et coxph au maximum de vraisemblance.
# DONNÉES : regression_data.csv (pas selon l'âge, n = 300 ; sous-échantillon de 60 sujets pour la règle des petits
# effectifs), cardiometabolique_simule.csv (événement à 5 ans selon l'IMC, n = 800), cox_lung.csv (survival::lung).
source("_common.R")
suppressPackageStartupMessages(library(rms))
reg <- read.csv(file.path(REF_DIR, "regression_data.csv"))
cm <- read.csv(file.path("..", "..", "demos", "cardiometabolique_simule.csv"))
lung <- read.csv(file.path(REF_DIR, "cox_lung.csv")); lung$ev <- as.integer(lung$deces == "oui")
grid <- function(x) seq(min(x), max(x), length.out = 61)[c(1, 16, 31, 46, 61)]
pack <- function(fit, var, data, nk, fun_scale = identity) {
  dd <<- datadist(data); options(datadist = "dd")
  a <- anova(fit)
  rn <- rownames(a); i <- which(rn == var); j <- i + 1   # ligne de la variable puis « Nonlinear »
  st <- if ("F" %in% colnames(a)) "F" else "Chi-Square"
  g <- grid(data[[var]])
  args <- list(fit, ref.zero = TRUE); args[[var]] <- g
  pr <- do.call(Predict, args)
  list(knots = unname(attr(rcs(data[[var]], nk), "parms")),
       knots_hmisc = unname(rcspline.eval(data[[var]], nk = nk, knots.only = TRUE)),
       coef = unname(coef(fit)), names = names(coef(fit)), se = unname(sqrt(diag(vcov(fit)))),
       overall = unname(a[i, c(st, "d.f.", "P")]), nonlinear = unname(a[j, c(st, "d.f.", "P")]),
       ref = median(data[[var]]), x = g, est = pr$yhat, lower = pr$lower, upper = pr$upper)
}
lin <- ols(pas ~ rcs(age, 4) + sexe, data = reg)
small <- reg[1:60, ]
lin5 <- ols(pas ~ rcs(age, 5), data = small)
lg <- lrm(evenement_5ans ~ rcs(imc, 4) + age + sexe, data = cm, eps = 1e-12, tol = 1e-14)
cx <- cph(Surv(time, ev) ~ rcs(age, 3) + sexe, data = lung, method = "efron", eps = 1e-12, tol = 1e-14, x = TRUE, y = TRUE)
write_ref(list(linear = pack(lin, "age", reg, 4), small = pack(lin5, "age", small, 5),
               logistic = pack(lg, "imc", cm, 4), cox = pack(cx, "age", lung, 3)), "splines")
print(anova(lin)); print(anova(lg)); print(anova(cx))
