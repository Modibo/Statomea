# Expression différentielle RNA-seq, plan à plusieurs facteurs : 3 groupes (A, B, C), un effet lot (2 lots croisés
# avec les groupes) et une covariable quantitative (RIN). TMM + voom(design) + lmFit + eBayes.
#  - coefficients B − A et C − A : topTable(coef) de limma (exact) ;
#  - contraste C − B : limma après changement de niveau de référence (paramétrisation exacte) ;
#  - F modéré global du facteur groupe : calcul exact gène par gène (V = (XᵀWX)⁻¹ propre au gène).
# On mesure aussi l'écart des approximations de limma (contrasts.fit, topTableF) qui utilisent la corrélation
# des coefficients du plan NON pondéré.
source("_common.R")
suppressPackageStartupMessages({ library(edgeR); library(limma) })
set.seed(20261021)
G <- 1500
grp <- factor(rep(c("A", "B", "C"), each = 4))
batch <- factor(rep(c("L1", "L2", "L1", "L2"), 3))
rin <- round(runif(12, 6, 9.5), 1)
base <- rgamma(G, shape = 0.6, rate = 0.006) + 1
lfcB <- lfcC <- rep(0, G)
deB <- sample(G, 90); lfcB[deB] <- sample(c(-1, 1), 90, TRUE) * runif(90, 0.8, 2.5)
deC <- sample(G, 90); lfcC[deC] <- sample(c(-1, 1), 90, TRUE) * runif(90, 0.8, 2.5)
lot <- ifelse(runif(G) < 0.3, rnorm(G, 0, 0.7), 0)        # effet lot propre au gène
pente <- ifelse(runif(G) < 0.2, rnorm(G, 0, 0.3), 0)      # effet de la qualité d'ARN
libf <- runif(12, 0.7, 1.3)
disp <- exp(rnorm(G, log(0.06), 0.8))
mu <- sapply(1:12, function(j) base * libf[j] * 2^(lfcB * (grp[j] == "B") + lfcC * (grp[j] == "C") + lot * (batch[j] == "L2") + pente * (rin[j] - 7.5)))
cnt <- matrix(rnbinom(G * 12, mu = mu, size = 1 / disp), G, 12)
rownames(cnt) <- sprintf("G%04d", 1:G); colnames(cnt) <- paste0(grp, rep(1:4, 3))
write.csv(data.frame(gene = rownames(cnt), cnt, check.names = FALSE), file.path(REF_DIR, "rnaseq_plan_simule.csv"), row.names = FALSE)

y <- DGEList(cnt)
keep <- rowSums(cpm(y) >= 1) >= 4
y <- calcNormFactors(y[keep, , keep.lib.sizes = FALSE])
design <- model.matrix(~ grp + batch + rin)
v <- voom(y, design)
fit <- eBayes(lmFit(v, design))
tt <- function(f, coef) topTable(f, coef = coef, number = Inf, sort.by = "none")
ttB <- tt(fit, "grpB"); ttC <- tt(fit, "grpC")
design2 <- model.matrix(~ relevel(grp, "B") + batch + rin)
fit2 <- eBayes(lmFit(v, design2))
ttCB <- tt(fit2, 3)                                         # coefficient « C » avec B en référence
stopifnot(abs(fit2$s2.prior - fit$s2.prior) < 1e-12)

# F modéré exact du facteur groupe (coefficients 2 et 3).
Fex <- sapply(seq_len(nrow(v)), function(g) {
  V <- solve(crossprod(design, design * v$weights[g, ]))
  b <- fit$coefficients[g, 2:3]
  drop(t(b) %*% solve(V[2:3, 2:3], b)) / (2 * fit$s2.post[g])
})
dfT <- fit$df.total
Fp <- pf(Fex, 2, dfT, lower.tail = FALSE)

# Approximations de limma (pour documenter l'écart) : contrasts.fit et topTableF.
dn <- design; colnames(dn) <- make.names(colnames(dn))
cf <- eBayes(contrasts.fit(lmFit(v, dn), makeContrasts(CB = grpC - grpB, levels = colnames(dn))))
tF <- topTable(fit, coef = 2:3, number = Inf, sort.by = "none")

write_ref(list(
  kept = rownames(y), norm_factors = unname(y$samples$norm.factors), w_head = unname(v$weights[1:3, ]),
  group = as.character(grp), batch = as.character(batch), rin = rin,
  df_prior = fit$df.prior, s2_prior = fit$s2.prior, df_total = unname(dfT[1]),
  B = list(logFC = ttB$logFC, t = ttB$t, p = ttB$P.Value, adj = ttB$adj.P.Val),
  C = list(logFC = ttC$logFC, t = ttC$t, p = ttC$P.Value, adj = ttC$adj.P.Val),
  CB = list(logFC = ttCB$logFC, t = ttCB$t, p = ttCB$P.Value, adj = ttCB$adj.P.Val),
  F = unname(Fex), F_p = unname(Fp), F_adj = p.adjust(Fp, "BH"),
  n_sig = list(B = sum(ttB$adj.P.Val < 0.05), C = sum(ttC$adj.P.Val < 0.05), CB = sum(ttCB$adj.P.Val < 0.05), F = sum(p.adjust(Fp, "BH") < 0.05)),
  limma_approx = list(
    CB_t_max_rel_diff = max(abs(cf$t[, 1] - ttCB$t) / abs(ttCB$t)),
    CB_t_median_rel_diff = median(abs(cf$t[, 1] - ttCB$t) / abs(ttCB$t)),
    F_max_rel_diff = max(abs(tF$F - Fex) / Fex),
    F_median_rel_diff = median(abs(tF$F - Fex) / Fex),
    discordant_calls_CB = sum((cf$p.value[, 1] < 0.05) != (ttCB$P.Value < 0.05)))
), "expression_plan")
