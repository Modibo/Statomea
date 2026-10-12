# Association génétique cas-témoins : Hardy-Weinberg (HardyWeinberg), tests allélique, génotypique, tendance
# d'Armitage (prop.trend.test), modèles codominant/dominant/récessif (glm), balayage ajusté et p.adjust.
source("_common.R")
suppressPackageStartupMessages(library(HardyWeinberg))
set.seed(20261013)
n <- 600
cas <- rbinom(n, 1, 0.4)
age <- round(rnorm(n, 50 + 4 * cas, 10)); sexe <- sample(c("F", "H"), n, TRUE)
geno <- function(maf, or = 1, hwd = 0) {
  # Génotype (nombre d'allèles mineurs) ; effet multiplicatif sur la cote chez les cas ; hwd > 0 : excès d'homozygotes.
  p <- maf; pr <- c((1 - p)^2 + hwd * p * (1 - p), 2 * p * (1 - p) * (1 - hwd), p^2 + hwd * p * (1 - p))
  g <- sample(0:2, n, TRUE, prob = pr)
  if (or != 1) for (i in which(cas == 1)) g[i] <- sample(0:2, 1, prob = pr * or^(0:2))
  g
}
G <- list(rs1 = geno(0.30, or = 1.8), rs2 = geno(0.25), rs3 = geno(0.10), rs4 = geno(0.40, hwd = 0.35), rs5 = geno(0.05), rs6 = geno(0.45))
alle <- list(rs1 = c("C", "T"), rs2 = c("A", "G"), rs3 = c("G", "A"), rs4 = c("T", "C"), rs5 = c("C", "G"), rs6 = c("A", "C"))
code <- function(g, a) c(paste0(a[1], "/", a[1]), paste0(a[1], "/", a[2]), paste0(a[2], "/", a[2]))[g + 1]
d <- data.frame(id = sprintf("S%03d", 1:n), statut = ifelse(cas == 1, "cas", "témoin"), age = age, sexe = sexe)
for (k in names(G)) d[[k]] <- code(G[[k]], alle[[k]])
d$rs2[sample(n, 9)] <- NA
write.csv(d, file.path(REF_DIR, "genetique_simule.csv"), row.names = FALSE, na = "")

hwe <- function(g) { x <- c(AA = sum(g == 0), AB = sum(g == 1), BB = sum(g == 2))
  list(counts = unname(x), exact = HWExact(x, verbose = FALSE)$pval, midp = HWExact(x, pvaluetype = "midp", verbose = FALSE)$pval,
       chisq = unname(HWChisq(x, cc = 0, verbose = FALSE)$chisq), chisq_p = HWChisq(x, cc = 0, verbose = FALSE)$pval,
       f = unname(1 - x[2] / (2 * sum(x) * ((2 * x[1] + x[2]) / (2 * sum(x))) * ((2 * x[3] + x[2]) / (2 * sum(x)))))) }
# Dosage = nombre d'allèles mineurs (fréquence calculée sur l'échantillon entier, génotypes connus).
dosage <- function(k) { g <- G[[k]]; g[is.na(d[[k]])] <- NA; if (mean(g, na.rm = TRUE) / 2 > 0.5) 2 - g else g }
assoc1 <- function(k) {
  g <- dosage(k); ok <- !is.na(g); g <- g[ok]; y <- cas[ok]
  tab <- table(factor(y, 0:1), factor(g, 0:2))
  al <- rbind(c(2 * tab[2, 1] + tab[2, 2], 2 * tab[2, 3] + tab[2, 2]), c(2 * tab[1, 1] + tab[1, 2], 2 * tab[1, 3] + tab[1, 2]))
  orw <- function(a, b, c, dd) { o <- (a * dd) / (b * c); s <- sqrt(1/a + 1/b + 1/c + 1/dd); c(o, exp(log(o) - qnorm(.975) * s), exp(log(o) + qnorm(.975) * s)) }
  cod <- glm(y ~ factor(g), family = binomial)
  list(geno_cases = as.vector(tab[2, ]), geno_controls = as.vector(tab[1, ]),
       allelic_chisq = unname(chisq.test(al, correct = FALSE)$statistic), allelic_p = chisq.test(al, correct = FALSE)$p.value,
       allelic_or = orw(al[1, 2], al[1, 1], al[2, 2], al[2, 1]),
       genotypic_chisq = unname(chisq.test(tab, correct = FALSE)$statistic), genotypic_p = chisq.test(tab, correct = FALSE)$p.value,
       trend_chisq = unname(prop.trend.test(tab[2, ], colSums(tab), 0:2)$statistic), trend_p = prop.trend.test(tab[2, ], colSums(tab), 0:2)$p.value,
       dominant_or = orw(sum(tab[2, 2:3]), tab[2, 1], sum(tab[1, 2:3]), tab[1, 1]),
       recessive_or = orw(tab[2, 3], sum(tab[2, 1:2]), tab[1, 3], sum(tab[1, 1:2])),
       codominant = unname(exp(cbind(coef(cod), confint.default(cod))))[2:3, ],
       hwe_controls = hwe(g[y == 0]))
}
scan <- lapply(names(G), function(k) { g <- dosage(k); m <- glm(cas ~ g + age + sexe, family = binomial)
  c(beta = unname(coef(m)["g"]), se = unname(sqrt(vcov(m)["g", "g"])), p = unname(summary(m)$coefficients["g", 4])) })
P <- sapply(scan, `[`, "p")
write_ref(list(
  snps = names(G), n = n, cases = sum(cas),
  minor = sapply(names(G), function(k) { g <- G[[k]]; if (mean(g) / 2 > 0.5) alle[[k]][1] else alle[[k]][2] }),
  maf = sapply(names(G), function(k) { g <- dosage(k); mean(g, na.rm = TRUE) / 2 }),
  rs1 = assoc1("rs1"), rs4 = assoc1("rs4"), rs2 = assoc1("rs2"),
  scan_beta = sapply(scan, `[`, "beta"), scan_se = sapply(scan, `[`, "se"), scan_p = P,
  p_bonferroni = p.adjust(P, "bonferroni"), p_holm = p.adjust(P, "holm"), p_bh = p.adjust(P, "BH"), p_by = p.adjust(P, "BY")
), "genetique")
