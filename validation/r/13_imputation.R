# Imputation multiple : (1) règles de Rubin exactes sur des jeux complétés par
# mice ; (2) comparaison statistique des imputations (simulation MAR, vérité connue).
source("_common.R")
suppressPackageStartupMessages(library(mice))
# (1) Jeux complétés par mice (démo 3 : glycémie et HDL manquants).
dev <- read.csv(file.path(REF_DIR, "cardiometabolique_simule.csv"), na.strings = "")
d <- dev[, c("age", "sexe", "tour_taille", "pas", "glycemie", "hdl", "tabac", "atcd_familial", "evenement_5ans")]
for (v in c("sexe", "tabac", "atcd_familial")) d[[v]] <- factor(d[[v]])
imp <- mice(d, m = 5, seed = 2026, printFlag = FALSE)
long <- complete(imp, "long")
write.csv(long, file.path(REF_DIR, "mi_mice_completed.csv"), row.names = FALSE)
fl <- with(imp, glm(evenement_5ans ~ age + sexe + tour_taille + pas + glycemie + hdl + tabac + atcd_familial, family = binomial,
                    control = glm.control(epsilon = 1e-14, maxit = 100)))
pl <- summary(pool(fl)); plr <- pool(fl)$pooled
fm <- with(imp, lm(pas ~ age + sexe + glycemie + hdl))
pm <- summary(pool(fm)); pmr <- pool(fm)$pooled
pk <- function(s, r) list(term = as.character(s$term), est = s$estimate, se = s$std.error, df = s$df, p = s$p.value,
                          fmi = r$fmi, riv = r$riv, b = r$b)
ref1 <- list(logistic = pk(pl, plr), linear = pk(pm, pmr))
# (2) Simulation MAR : x1 manquant selon y (MAR), x2 binaire manquant selon x3.
set.seed(31)
n <- 1000
x3 <- rnorm(n); x1 <- 0.5 * x3 + rnorm(n); x2 <- rbinom(n, 1, plogis(0.3 * x3))
y <- 1 + 0.5 * x1 + 0.8 * x2 + 0.3 * x3 + rnorm(n)
x1[runif(n) < plogis(-2.2 + 1.0 * y)] <- NA
x2[runif(n) < plogis(-2 + 0.8 * x3)] <- NA
sim <- data.frame(y = round(y, 4), x1 = round(x1, 4), x2 = ifelse(is.na(x2), NA, ifelse(x2 == 1, "oui", "non")), x3 = round(x3, 4))
write.csv(sim, file.path(REF_DIR, "mi_simulation.csv"), row.names = FALSE, na = "")
sim$x2 <- factor(sim$x2, levels = c("non", "oui"))
ims <- mice(sim, m = 40, maxit = 10, seed = 7, printFlag = FALSE)
ps <- summary(pool(with(ims, lm(y ~ x1 + x2 + x3))))
cc <- summary(lm(y ~ x1 + x2 + x3, data = sim))$coefficients
# Variabilité de mice d'une graine à l'autre (12 graines) : référence de la comparaison statistique.
seeds <- t(sapply(1:12, function(sd) { im <- mice(sim, m = 40, maxit = 10, seed = sd, printFlag = FALSE)
  p <- summary(pool(with(im, lm(y ~ x1 + x2 + x3)))); c(p$estimate, p$std.error) }))
ref2 <- list(seeds_est_mean = unname(colMeans(seeds[, 1:4])), seeds_est_sd = unname(apply(seeds[, 1:4], 2, sd)),
             seeds_se_mean = unname(colMeans(seeds[, 5:8])), seeds_se_sd = unname(apply(seeds[, 5:8], 2, sd)), truth = c(1, 0.5, 0.8, 0.3), mice_est = ps$estimate, mice_se = ps$std.error, cc_est = unname(cc[, 1]), cc_se = unname(cc[, 2]),
             missing_x1 = sum(is.na(sim$x1)), missing_x2 = sum(is.na(sim$x2)))
write_ref(list(rubin = ref1, sim = ref2, mice = as.character(packageVersion("mice"))), "imputation")
cat("mice MI :", round(ps$estimate, 3), " CC :", round(cc[, 1], 3), " manquants x1/x2 :", ref2$missing_x1, ref2$missing_x2, "\n")
