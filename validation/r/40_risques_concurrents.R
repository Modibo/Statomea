# Risques concurrents : incidence cumulée (Aalen-Johansen) et modèle de Fine-Gray, références cmprsk 2.2 et survival.
#  - incidence cumulée : cmprsk::cuminc (estimation et variance de Gray, aux temps d'événement, par groupe et par cause) ;
#    IC ponctuel par transformation log(−log) : F^exp(±z·√v/(F·log F)) (non fourni par cuminc, calculé ici) ;
#    comparaison au 1 − Kaplan-Meier « naïf » (autres causes traitées comme censures) : survival::survfit ;
#  - modèle de Fine-Gray : cmprsk::crr (gtol resserré à 1e-12), variance sandwich de Fine et Gray (1999) ;
#  - modèle de Cox spécifique de cause (autres causes censurées) : survival::coxph (Efron).
# DONNÉES SIMULÉES (demos/risques_concurrents_simule.csv) : 400 patients suivis après traitement d'un cancer ; issue
# d'intérêt « rechute », événement concurrent « décès » (sans rechute), « censure » ; bras B (moins de rechutes mais
# autant de décès), âge (plus de décès et de rechutes), sexe ; durées en mois arrondies au dixième (ex aequo).
source("_common.R")
suppressPackageStartupMessages({ library(cmprsk); library(survival) })
set.seed(20261116)
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
n <- 400
bras <- sample(c("A", "B"), n, TRUE); age <- round(rnorm(n, 58, 11)); sexe <- sample(c("F", "H"), n, TRUE)
hR <- 0.035 * exp(-0.55 * (bras == "B") + 0.015 * (age - 58) + 0.2 * (sexe == "H"))
hD <- 0.018 * exp(0.05 * (age - 58))
tR <- rexp(n, hR); tD <- rexp(n, hD); tC <- runif(n, 12, 72)
tt <- pmin(tR, tD, tC)
statut <- ifelse(tt == tR, "rechute", ifelse(tt == tD, "deces", "censure"))
d <- data.frame(patient = sprintf("P%03d", 1:n), mois = round(tt, 1), statut = statut, bras = bras, age = age, sexe = sexe)
d$mois[d$mois == 0] <- 0.1
write.csv(d, file.path(DEMO_DIR, "risques_concurrents_simule.csv"), row.names = FALSE, quote = FALSE)

code <- ifelse(d$statut == "rechute", 1, ifelse(d$statut == "deces", 2, 0))
ci <- cuminc(d$mois, code, d$bras)
z <- qnorm(0.975)
grab <- function(e) {
  # cuminc renvoie chaque temps deux fois (marche) : garder la valeur après le saut, aux temps d'événement toutes causes.
  ut <- sort(unique(e$time[-1])); k <- sapply(ut, function(t) max(which(e$time == t)))
  F <- e$est[k]; v <- e$var[k]
  lo <- ifelse(F > 0 & F < 1, F^exp(z * sqrt(v) / (F * log(F))), NA); hi <- ifelse(F > 0 & F < 1, F^exp(-z * sqrt(v) / (F * log(F))), NA)
  list(time = ut, est = F, var = v, lower = lo, upper = hi)
}
cif <- lapply(ci[c("A 1", "B 1", "A 2", "B 2")], grab)
naive <- lapply(c("A", "B"), function(g) { s <- survfit(Surv(mois, statut == "rechute") ~ 1, data = d[d$bras == g, ]); list(time = s$time, est = 1 - s$surv) })
names(naive) <- c("A", "B")
at <- function(e, t) { k <- max(c(0, which(e$time <= t))); if (k == 0) 0 else e$est[k] }
h24 <- list(A = at(cif[["A 1"]], 24), B = at(cif[["B 1"]], 24), naiveA = at(naive$A, 24), naiveB = at(naive$B, 24))

X <- cbind(brasB = as.numeric(d$bras == "B"), age = d$age, sexeH = as.numeric(d$sexe == "H"))
fg <- crr(d$mois, code, X, gtol = 1e-12, maxiter = 50)
fg1 <- crr(d$mois, code, X[, "brasB", drop = FALSE], gtol = 1e-12, maxiter = 50)
cs <- coxph(Surv(mois, statut == "rechute") ~ (bras == "B") + age + (sexe == "H"), data = d, ties = "efron")
write_ref(list(n = n, events = as.list(table(d$statut)), cif = cif, naive = naive, at24 = h24,
               fg = list(coef = unname(fg$coef), se = unname(sqrt(diag(fg$var))), loglik = fg$loglik, loglik_null = fg$loglik.null, converged = fg$converged),
               fg_group = list(coef = unname(fg1$coef), se = unname(sqrt(diag(fg1$var)))),
               cs = list(coef = unname(coef(cs)), se = unname(sqrt(diag(vcov(cs)))))), "risques_concurrents")
print(table(d$statut)); print(summary(fg)$coef); print(h24); print(ci$Tests)
