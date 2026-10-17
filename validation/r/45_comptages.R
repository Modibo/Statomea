# Régression de comptages : Poisson (avec offset de temps d'exposition), quasi-Poisson et binomiale négative,
# références stats (glm) et MASS 7.3 (glm.nb, convergence resserrée).
#  - Poisson : IRLS, ES = (XᵀWX)⁻¹ ; déviance, χ² de Pearson, dispersion φ = χ²/(n − p) ;
#  - quasi-Poisson : mêmes β, ES × √φ ;
#  - binomiale négative NB2 (Var = μ + μ²/θ) : alternance IRLS (β | θ) et Newton sur θ (score et information de
#    MASS::theta.ml) jusqu'au maximum de vraisemblance ; ES des β à θ fixé, ES(θ) = 1/√information ;
#    test du rapport de vraisemblance Poisson contre binomiale négative (θ → ∞ : frontière, p/2).
# DONNÉES (paquet MASS, Venables et Ripley) : quine (146 élèves, jours d'absence ; origine, sexe, âge, apprentissage) ;
# Insurance (64 cellules, sinistres automobiles avec offset log(nombre d'assurés) ; district, puissance, âge).
source("_common.R")
suppressPackageStartupMessages(library(MASS))
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
q <- data.frame(origine = ifelse(quine$Eth == "A", "aborigene", "non_aborigene"), sexe = ifelse(quine$Sex == "F", "F", "M"),
                age = as.character(quine$Age), apprentissage = ifelse(quine$Lrn == "SL", "lent", "moyen"), jours_absence = quine$Days)
write.csv(q, file.path(DEMO_DIR, "absences_quine.csv"), row.names = FALSE, quote = FALSE)
ins <- data.frame(district = paste0("D", Insurance$District), puissance = as.character(Insurance$Group), age = as.character(Insurance$Age),
                  assures = Insurance$Holders, sinistres = Insurance$Claims)
ins$puissance <- c("<1l" = "p1_moins_1l", "1-1.5l" = "p2_1_1.5l", "1.5-2l" = "p3_1.5_2l", ">2l" = "p4_plus_2l")[ins$puissance]
ins$age <- c("<25" = "a1_moins_25", "25-29" = "a2_25_29", "30-35" = "a3_30_35", ">35" = "a4_plus_35")[ins$age]
write.csv(ins, file.path(DEMO_DIR, "sinistres_assurance.csv"), row.names = FALSE, quote = FALSE)

ctl <- glm.control(epsilon = 1e-14, maxit = 200)
s <- function(f) list(beta = unname(coef(f)), se = unname(sqrt(diag(vcov(f)))), deviance = f$deviance, df = f$df.residual,
                      pearson = sum(residuals(f, "pearson")^2), loglik = as.numeric(logLik(f)))
fq <- Days ~ Eth + Sex + Age + Lrn
qp <- glm(jours_absence ~ origine + sexe + age + apprentissage, family = poisson, data = q, control = ctl)
qq <- glm(jours_absence ~ origine + sexe + age + apprentissage, family = quasipoisson, data = q, control = ctl)
qn <- glm.nb(jours_absence ~ origine + sexe + age + apprentissage, data = q, control = ctl)
ip <- glm(sinistres ~ district + puissance + age + offset(log(assures)), family = poisson, data = ins, control = ctl)
inb <- glm.nb(sinistres ~ district + puissance + age + offset(log(assures)), data = ins, control = ctl)
nb <- function(f) c(s(f), list(theta = f$theta, se_theta = f$SE.theta, twologlik = f$twologlik))
lrt <- 2 * (as.numeric(logLik(qn)) - as.numeric(logLik(qp)))
write_ref(list(quine_pois = s(qp), quine_quasi = list(se = unname(sqrt(diag(vcov(qq)))), dispersion = summary(qq)$dispersion),
               quine_nb = nb(qn), quine_lrt = list(stat = lrt, p = pchisq(lrt, 1, lower.tail = FALSE) / 2),
               ins_pois = s(ip), ins_nb = nb(inb)), "comptages")
cat("quine : dispersion", summary(qq)$dispersion, " θ", qn$theta, "±", qn$SE.theta, " LRT", lrt, "\nInsurance : θ", inb$theta, "\n")
