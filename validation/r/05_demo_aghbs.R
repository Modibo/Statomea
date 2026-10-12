# Démonstration 1 : prévalence de l'AgHBs et événements rares.
# DONNÉES SIMULÉES à but pédagogique : aucune donnée de patiente réelle.
# Scénario : dépistage prénatal de l'AgHBs (étude transversale), puis suivi
# des enfants nés de mères porteuses (sérovaccination à la naissance).
source("_common.R")
suppressPackageStartupMessages(library(logistf))
set.seed(2026)
n <- 640
age <- round(runif(n, 16, 44))
residence <- sample(c("urbain", "rural"), n, TRUE, prob = c(.55, .45))
parite <- pmin(rpois(n, 2), 8)
p_hbs <- plogis(-2.75 + 0.45 * (residence == "rural") + 0.012 * (age - 28))
aghbs <- ifelse(rbinom(n, 1, p_hbs) == 1, "positif", "negatif")
pos <- which(aghbs == "positif")
aghbe <- rep(NA_character_, n); aghbe[pos] <- ifelse(runif(length(pos)) < 0.22, "positif", "negatif")
enfant_suivi <- rep(NA_character_, n); enfant_suivi[pos] <- ifelse(runif(length(pos)) < 0.9, "oui", "non")
enfant_infecte <- rep(NA_character_, n)
fu <- which(enfant_suivi == "oui")
# Transmission rare, uniquement chez des mères AgHBe+ (d'où la séparation).
enfant_infecte[fu] <- "non"
cand <- fu[aghbe[fu] == "positif"]
enfant_infecte[cand[1:2]] <- "oui"
d <- data.frame(id = sprintf("F%03d", 1:n), age, residence, parite, aghbs, aghbe, enfant_suivi, enfant_infecte)
write.csv(d, file.path("..", "..", "demos", "aghbs_simule.csv"), row.names = FALSE, na = "")
file.copy(file.path("..", "..", "demos", "aghbs_simule.csv"), file.path(REF_DIR, "aghbs_simule.csv"), overwrite = TRUE)
cat("AgHBs+ :", sum(aghbs == "positif"), "/", n, " ; enfants suivis :", length(fu), " ; infectés : 2 ; mères AgHBe+ suivies :", length(cand), "\n")
inf <- d[fu, ]; inf$y <- as.integer(inf$enfant_infecte == "oui"); inf$aghbe <- relevel(factor(inf$aghbe), "negatif")
ff <- logistf(y ~ aghbe, data = inf, pl = FALSE, control = logistf.control(xconv = 1e-12, gconv = 1e-12, maxit = 200))
bt <- binom.test(sum(aghbs == "positif"), n)
write_ref(list(n = n, positives = sum(aghbs == "positif"), prev_exact = as.numeric(bt$conf.int),
  infants = length(fu), firth_coef = unname(coef(ff)), firth_se = unname(sqrt(diag(vcov(ff)))),
  fisher_p = fisher.test(table(inf$aghbe, inf$y))$p.value), "demo_aghbs")
