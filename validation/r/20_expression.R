# Expression différentielle RNA-seq : TMM (edgeR::calcNormFactors), voom (limma), lmFit pondéré, eBayes, BH.
# Comptages simulés (binomiale négative), 1000 gènes × 8 échantillons (4 témoins, 4 traités), 8 % de gènes DE.
source("_common.R")
suppressPackageStartupMessages({ library(edgeR); library(limma) })
set.seed(20261016)
G <- 1000; grp <- factor(rep(c("temoin", "traite"), each = 4), levels = c("temoin", "traite"))
base <- rgamma(G, shape = 0.6, rate = 0.006) + 1
lfc <- rep(0, G); de <- sample(G, 80); lfc[de] <- sample(c(-1, 1), 80, TRUE) * runif(80, 0.8, 2.5)
libf <- c(1.0, 1.3, 0.8, 1.1, 0.9, 1.2, 1.0, 0.7)
disp <- exp(rnorm(G, log(0.08), 0.9))           # dispersion biologique variable selon le gène
cnt <- sapply(1:8, function(j) rnbinom(G, mu = base * libf[j] * 2^(lfc * (grp[j] == "traite")), size = 1 / disp))
rownames(cnt) <- sprintf("GENE%04d", 1:G); colnames(cnt) <- c(paste0("T", 1:4), paste0("X", 1:4))
write.csv(data.frame(gene = rownames(cnt), cnt, check.names = FALSE), file.path(REF_DIR, "rnaseq_simule.csv"), row.names = FALSE)

y <- DGEList(cnt, group = grp)
cpm1 <- cpm(y)                               # filtre simple : CPM ≥ 1 dans au moins 4 échantillons
keep <- rowSums(cpm1 >= 1) >= 4
y <- y[keep, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y, method = "TMM")
design <- model.matrix(~ grp)
v <- voom(y, design)
fit <- eBayes(lmFit(v, design))
tt <- topTable(fit, coef = 2, number = Inf, sort.by = "none")
lx <- round(runif(60, 0, 10), 1); lx[1:5] <- lx[6]   # ex æquo volontaires
ly <- sin(lx) + rnorm(60, 0, 0.3); ly[c(7, 30)] <- ly[c(7, 30)] + 4   # valeurs aberrantes (robustesse)
write_ref(list(
  kept = rownames(y), lib_size = unname(y$samples$lib.size), norm_factors = unname(y$samples$norm.factors),
  E_head = unname(v$E[1:5, ]), w_head = unname(v$weights[1:5, ]),
  df_prior = fit$df.prior, s2_prior = fit$s2.prior,
  logFC = unname(tt$logFC), AveExpr = unname(tt$AveExpr), t = unname(tt$t), p = unname(tt$P.Value), adj = unname(tt$adj.P.Val),
  n_sig = sum(tt$adj.P.Val < 0.05), truth_de = rownames(cnt)[de],
  lowess = list(x = lx, y = ly, f23 = lowess(lx, ly)$y, f03 = lowess(lx, ly, f = 0.3, iter = 0)$y, xs = lowess(lx, ly)$x)
), "expression")
