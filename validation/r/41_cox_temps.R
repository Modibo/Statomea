# Modèle de Cox avec covariable dépendant du temps (processus de comptage (début, fin]) et biais du temps immortel,
# références survival 3.5 (tmerge, coxph). Données réelles : programme de greffe cardiaque de Stanford (jeu « jasa » du
# paquet survival, Crowley et Hu 1977), 103 patients inscrits sur liste, 69 greffés.
# Préparation comme la vignette « Using time dependent covariates » de survival : durée ≥ 0,5 jour ; si la greffe a lieu
# le jour du décès, elle est avancée de 0,5 jour (sinon le décès précéderait la greffe).
#  - analyse naïve (biais du temps immortel) : coxph(Surv(futime, fustat) ~ greffe + age + chirurgie) ;
#  - découpage par tmerge(tdc(attente)) : (0, attente] sans greffe, (attente, futime] avec greffe ;
#  - Cox en processus de comptage : coxph(Surv(debut, fin, deces) ~ greffe + age + chirurgie), Efron et Breslow.
source("_common.R")
suppressPackageStartupMessages(library(survival))
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
j <- jasa
j$futime <- pmax(0.5, j$futime)
k <- which(j$wait.time == j$futime); j$wait.time[k] <- j$wait.time[k] - 0.5
d <- data.frame(patient = 1:nrow(j), jours = j$futime, deces = ifelse(j$fustat == 1, "oui", "non"),
                attente_greffe = j$wait.time, greffe = ifelse(j$transplant == 1, "oui", "non"),
                age = round(j$age - 48, 2), chirurgie = ifelse(j$surgery == 1, "oui", "non"))
write.csv(d, file.path(DEMO_DIR, "greffe_stanford.csv"), row.names = FALSE, quote = FALSE, na = "")

naive <- coxph(Surv(jours, deces == "oui") ~ (greffe == "oui") + age + (chirurgie == "oui"), data = d)
t0 <- d[, c("patient", "age", "chirurgie")]
td <- tmerge(t0, d, id = patient, evt = event(jours, as.numeric(deces == "oui")), gref = tdc(attente_greffe))
td$gref[is.na(td$gref)] <- 0
fitE <- coxph(Surv(tstart, tstop, evt) ~ gref + age + (chirurgie == "oui"), data = td)
fitB <- coxph(Surv(tstart, tstop, evt) ~ gref + age + (chirurgie == "oui"), data = td, ties = "breslow")
s <- function(f) list(coef = unname(coef(f)), se = unname(sqrt(diag(vcov(f)))), loglik = unname(f$loglik), score = unname(f$score),
                      wald = unname(f$wald.test))
write_ref(list(rows = list(patient = td$patient, start = td$tstart, stop = td$tstop, event = td$evt, greffe = td$gref),
               naive = s(naive), efron = s(fitE), breslow = s(fitB)), "cox_temps")
cat("lignes", nrow(td), "\n"); print(summary(naive)$coef[1, ]); print(summary(fitE)$coef)
