# Comparaisons post hoc : loi de l'étendue studentisée (ptukey), Tukey HSD (stats::TukeyHSD),
# Games-Howell et Dunn-Holm (rstatix). Jeux publics PlantGrowth et InsectSprays + jeu simulé.
source("_common.R")
suppressPackageStartupMessages(library(rstatix))

# Loi de l'étendue studentisée : grille de valeurs (queue supérieure).
grid <- expand.grid(q = c(0.5, 1, 2, 3.5, 5, 8), k = c(2, 3, 5, 10), df = c(5, 20, 120, 30000))
grid$p <- ptukey(grid$q, grid$k, grid$df, lower.tail = FALSE)
# Quantiles précis : qtukey() de R s'arrête à 1e-4 près ; référence par uniroot serré.
qprec <- function(p, k, df) uniroot(function(q) ptukey(q, k, df) - p, c(0.01, 50), tol = 1e-13)$root
qgrid <- expand.grid(k = c(3, 4, 6), df = c(10, 27, 66))
qgrid$q95 <- mapply(function(k, df) qprec(0.95, k, df), qgrid$k, qgrid$df)
qgrid$q95_r <- qtukey(0.95, qgrid$k, qgrid$df)

# Jeu simulé : 4 groupes, effectifs et variances inégaux, valeurs arrondies (ex aequo).
set.seed(20261011)
sim <- data.frame(groupe = factor(rep(c("A", "B", "C", "D"), c(8, 12, 10, 15)), levels = c("A", "B", "C", "D")))
sim$y <- round(c(rnorm(8, 10, 1), rnorm(12, 11, 3), rnorm(10, 13, 1.5), rnorm(15, 10.5, 4)), 1)
write.csv(sim, file.path(REF_DIR, "posthoc_sim.csv"), row.names = FALSE)
data(PlantGrowth); data(InsectSprays)

tukey <- function(d, f, level = 0.95) {
  a <- aov(as.formula(f), data = d); t <- TukeyHSD(a, conf.level = level)[[1]]
  mse <- sum(residuals(a)^2) / a$df.residual
  k <- nlevels(d[[all.vars(as.formula(f))[2]]])
  q <- qprec(level, k, a$df.residual)
  n <- table(d[[all.vars(as.formula(f))[2]]])
  pairs <- strsplit(rownames(t), "-")
  se <- sapply(pairs, function(pr) sqrt(mse / 2 * (1 / n[[pr[1]]] + 1 / n[[pr[2]]])))
  list(pairs = rownames(t), diff = unname(t[, "diff"]), lwr_r = unname(t[, "lwr"]), upr_r = unname(t[, "upr"]),
       lwr = unname(t[, "diff"] - q * se), upr = unname(t[, "diff"] + q * se), p = unname(t[, "p adj"]))
}
gh <- games_howell_test(sim, y ~ groupe, conf.level = 0.95, detailed = TRUE)
# Recalcul indépendant de Games-Howell (rstatix arrondit p.adj).
ghm <- with(sim, {
  lv <- levels(groupe); k <- length(lv); out <- list()
  for (i in 1:(k - 1)) for (j in (i + 1):k) {
    a <- y[groupe == lv[i]]; b <- y[groupe == lv[j]]
    v <- var(a) / length(a) + var(b) / length(b)
    df <- v^2 / ((var(a) / length(a))^2 / (length(a) - 1) + (var(b) / length(b))^2 / (length(b) - 1))
    d <- mean(b) - mean(a); se <- sqrt(v / 2)
    out[[length(out) + 1]] <- c(d, df, ptukey(abs(d) / se, k, df, lower.tail = FALSE), d - qprec(0.95, k, df) * se, d + qprec(0.95, k, df) * se)
  }
  do.call(rbind, out)
})
dunn <- function(d, f) {
  r <- dunn_test(d, as.formula(f), p.adjust.method = "holm")
  list(g1 = r$group1, g2 = r$group2, z = r$statistic, p = r$p, p_adj = r$p.adj)
}
write_ref(list(
  ptukey = grid, qtukey = qgrid,
  tukey_plant = tukey(PlantGrowth, "weight ~ group"),
  tukey_sim = tukey(sim, "y ~ groupe"),
  plant = split(PlantGrowth$weight, PlantGrowth$group),
  insects = split(InsectSprays$count, InsectSprays$spray),
  gh_rstatix = list(estimate = gh$estimate, low = gh$conf.low, high = gh$conf.high, p_adj = gh$p.adj),
  gh = list(diff = ghm[, 1], df = ghm[, 2], p = ghm[, 3], low = ghm[, 4], high = ghm[, 5]),
  dunn_insects = dunn(InsectSprays, "count ~ spray"),
  dunn_sim = dunn(sim, "y ~ groupe"),
  anova_plant_p = summary(aov(weight ~ group, PlantGrowth))[[1]][["Pr(>F)"]][1]
), "posthoc")
