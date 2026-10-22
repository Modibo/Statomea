# Projet d'exemple 2 : essai randomisé zinc + SRO contre placebo + SRO dans la diarrhée aiguë de l'enfant.
# DONNÉES SIMULÉES à but pédagogique : aucune donnée de patient réelle.
# 240 enfants randomisés 1:1 (120 par bras, effectif volontairement insuffisant dans le protocole d'exemple) ;
# guérison à J5 : 60 % sous placebo, 74 % sous zinc ; observance incomplète chez ≈ 15 % (motif d'une analyse
# en intention de traiter).
source("_common.R")
set.seed(20261022)
n <- 240
bras <- sample(rep(c("zinc", "placebo"), each = n / 2))
age_mois <- round(runif(n, 6, 59))
sexe <- sample(c("F", "M"), n, TRUE)
deshydratation <- ifelse(runif(n) < 0.35, "moderee", "absente")
observance <- ifelse(runif(n) < ifelse(bras == "zinc", 0.17, 0.13), "incomplete", "complete")
lp <- qlogis(0.60) + (bras == "zinc") * (qlogis(0.74) - qlogis(0.60)) - 0.3 * (deshydratation == "moderee") - 0.4 * (observance == "incomplete") * (bras == "zinc")
guerison_j5 <- ifelse(rbinom(n, 1, plogis(lp)) == 1, "oui", "non")
duree_h <- round(ifelse(guerison_j5 == "oui", rgamma(n, 6, 6 / 70), rgamma(n, 8, 8 / 130)))
d <- data.frame(id = sprintf("E%03d", 1:n), bras, age_mois, sexe, deshydratation, observance, guerison_j5, duree_h)
write.csv(d, file.path("..", "..", "demos", "zinc_essai_simule.csv"), row.names = FALSE, na = "")
file.copy(file.path("..", "..", "demos", "zinc_essai_simule.csv"), file.path(REF_DIR, "zinc_essai_simule.csv"), overwrite = TRUE)
file.copy(file.path("..", "..", "demos", "zinc_essai_simule.csv"), file.path("..", "..", "app", "statomea", "assets", "demos", "zinc_essai_simule.csv"), overwrite = TRUE)
tab <- table(d$bras, d$guerison_j5)
print(tab)
pp <- power.prop.test(p1 = 0.60, p2 = 0.75, power = 0.8)
pw <- power.prop.test(n = 120, p1 = 0.60, p2 = 0.75)
cat("n par bras requis :", pp$n, " ; puissance avec 120 :", pw$power, "\n")
itt <- prop.table(tab, 1)[, "oui"]
pp_set <- d[d$observance == "complete", ]
write_ref(list(n = n, cured_zinc = sum(d$bras == "zinc" & d$guerison_j5 == "oui"), cured_placebo = sum(d$bras == "placebo" & d$guerison_j5 == "oui"),
  n_required = pp$n, power_120 = pw$power, itt_props = unname(itt[c("placebo", "zinc")]),
  per_protocol_n = nrow(pp_set)), "demo_zinc")
