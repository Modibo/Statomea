source("_common.R")
out <- list()
# --- Proportions
props <- list(c(0, 250), c(3, 412), c(17, 120), c(60, 60), c(48, 1000))
out$proportions <- lapply(props, function(v) {
  x <- v[1]; n <- v[2]
  w <- prop.test(x, n, correct = FALSE)$conf.int
  cp <- binom.test(x, n)$conf.int
  list(x = x, n = n, wilson = as.numeric(w), exact = as.numeric(cp))
})
# Newcombe hybride (méthode 10), calculé à partir des IC de Wilson de R
newc <- function(x1, n1, x2, n2) {
  p1 <- x1/n1; p2 <- x2/n2
  w1 <- prop.test(x1, n1, correct = FALSE)$conf.int; w2 <- prop.test(x2, n2, correct = FALSE)$conf.int
  d <- p1 - p2
  c(d - sqrt((p1 - w1[1])^2 + (w2[2] - p2)^2), d + sqrt((w1[2] - p1)^2 + (p2 - w2[1])^2))
}
# IC exact de Fisher résolu avec une tolérance serrée (fisher.test utilise
# uniroot avec tol ~1e-4, ce qui donne des bornes supérieures imprécises de
# quelques % quand elles sont grandes ; cf. docs/06-validation.md).
fisher_ci_precise <- function(a, b, c, d, conf = 0.95) {
  m <- a + c; n <- b + d; k <- a + b; lo <- max(0, k - n); hi <- min(k, m); s <- lo:hi
  ld <- dhyper(s, m, n, k, log = TRUE)
  pn <- function(ncp, upper) { l <- ld + log(ncp) * s; e <- exp(l - max(l)); e <- e / sum(e)
    if (upper) sum(e[s >= a]) else sum(e[s <= a]) }
  al <- (1 - conf) / 2
  U <- if (a == hi) Inf else uniroot(function(t) pn(1 / t, FALSE) - al, c(1e-12, 1e6), tol = 1e-14)$root
  U <- if (is.finite(U)) 1 / U else U
  L <- if (a == lo) 0 else uniroot(function(t) pn(t, TRUE) - al, c(1e-12, 1e6), tol = 1e-14)$root
  c(L, U)
}
# --- Tableaux 2x2 (a, b, c, d)
tabs <- list(c(30, 70, 15, 85), c(0, 25, 6, 19), c(3, 9, 1, 15), c(120, 380, 80, 420), c(9, 1, 2, 8))
out$two_by_two <- lapply(tabs, function(v) {
  a <- v[1]; b <- v[2]; c <- v[3]; d <- v[4]
  m <- matrix(c(a, c, b, d), 2)
  f <- fisher.test(m)
  cs <- suppressWarnings(chisq.test(m, correct = FALSE)); cy <- suppressWarnings(chisq.test(m, correct = TRUE))
  cc <- if (any(v == 0)) 0.5 else 0
  A <- a + cc; B <- b + cc; C <- c + cc; D <- d + cc
  or <- A*D/(B*C); se <- sqrt(1/A+1/B+1/C+1/D)
  rr <- (A/(A+B))/(C/(C+D)); serr <- sqrt(1/A - 1/(A+B) + 1/C - 1/(C+D))
  list(a = a, b = b, c = c, d = d,
       fisher_p = f$p.value, fisher_or = unname(f$estimate), fisher_ci = as.numeric(f$conf.int), fisher_ci_precise = fisher_ci_precise(a, b, c, d),
       chi2 = unname(cs$statistic), chi2_p = cs$p.value, chi2_yates = unname(cy$statistic), chi2_yates_p = cy$p.value,
       or = or, or_ci = exp(log(or) + c(-1, 1) * qnorm(.975) * se),
       rr = rr, rr_ci = exp(log(rr) + c(-1, 1) * qnorm(.975) * serr),
       rd = a/(a+b) - c/(c+d), rd_ci = newc(a, a+b, c, c+d))
})
# --- Groupes indépendants
set.seed(20261010)
g1 <- round(rnorm(23, 5.4, 1.1), 2); g2 <- round(rnorm(31, 6.1, 1.9), 2)
s1 <- c(1.2, 3.4, 2.2, 5.1, 0.7, 2.9, 4.4); s2 <- c(2.5, 6.3, 4.8, 7.7, 3.9, 5.5)
tw <- t.test(g1, g2); ts <- t.test(g1, g2, var.equal = TRUE)
mwE <- wilcox.test(s1, s2, exact = TRUE)
ti1 <- c(1, 2, 2, 3, 4, 4, 4, 6, 7); ti2 <- c(3, 4, 5, 5, 6, 7, 8, 8, 9, 10)
mwT <- suppressWarnings(wilcox.test(ti1, ti2))
mwL <- wilcox.test(g1, g2)
g3 <- round(rnorm(18, 7.0, 1.5), 2)
dfa <- data.frame(y = c(g1, g2, g3), g = factor(rep(c("A","B","C"), c(23, 31, 18))))
av <- summary(aov(y ~ g, dfa))[[1]]
ow <- oneway.test(y ~ g, dfa)
kw <- kruskal.test(y ~ g, dfa)
rxc <- matrix(c(20, 15, 30, 12, 25, 18, 8, 22, 10), 3)
cr <- chisq.test(rxc)
out$groups <- list(g1 = g1, g2 = g2, g3 = g3, s1 = s1, s2 = s2, ti1 = ti1, ti2 = ti2,
  welch = list(t = unname(tw$statistic), df = unname(tw$parameter), p = tw$p.value, ci = as.numeric(tw$conf.int)),
  student = list(t = unname(ts$statistic), df = unname(ts$parameter), p = ts$p.value, ci = as.numeric(ts$conf.int)),
  mw_exact = list(W = unname(mwE$statistic), p = mwE$p.value),
  mw_ties = list(W = unname(mwT$statistic), p = mwT$p.value),
  mw_large = list(W = unname(mwL$statistic), p = mwL$p.value),
  anova = list(F = av$`F value`[1], df1 = av$Df[1], df2 = av$Df[2], p = av$`Pr(>F)`[1]),
  welch_anova = list(F = unname(ow$statistic), df1 = unname(ow$parameter[1]), df2 = unname(ow$parameter[2]), p = ow$p.value),
  kruskal = list(H = unname(kw$statistic), p = kw$p.value),
  rxc = list(table = rxc, chi2 = unname(cr$statistic), p = cr$p.value))
# --- Appariés
pa <- c(142, 138, 150, 161, 129, 145, 133, 158, 147, 152, 139, 144)
pb <- c(135, 136, 141, 150, 128, 139, 135, 149, 140, 146, 133, 141)
pt_ <- t.test(pa, pb, paired = TRUE)
pc <- c(12.1, 9.8, 15.2, 11.0, 8.7, 13.4, 10.9, 14.8)
pd <- c(10.3, 9.9, 12.0, 11.6, 7.1, 11.5, 9.0, 12.2)
wsE <- wilcox.test(pc, pd, paired = TRUE, exact = TRUE)
wsT <- suppressWarnings(wilcox.test(pa, pb, paired = TRUE))
mc <- matrix(c(40, 5, 14, 41), 2)  # a=40, b=14, c=5, d=41  (x[1,2]=b, x[2,1]=c)
mct <- mcnemar.test(mc)
mce <- binom.test(14, 19, 0.5)
out$paired <- list(pa = pa, pb = pb, pc = pc, pd = pd,
  t = list(t = unname(pt_$statistic), p = pt_$p.value, ci = as.numeric(pt_$conf.int)),
  w_exact = list(V = unname(wsE$statistic), p = wsE$p.value),
  w_ties = list(V = unname(wsT$statistic), p = wsT$p.value),
  mcnemar = list(a = 40, b = 14, c = 5, d = 41, chi2 = unname(mct$statistic), p = mct$p.value, p_exact = mce$p.value,
                 or_ci = as.numeric(mce$conf.int / (1 - mce$conf.int))))
# --- Corrélations et Bland-Altman
x <- c(5.1, 6.3, 4.8, 7.7, 6.0, 5.5, 8.1, 7.2, 6.6, 5.9, 4.4, 7.0)
y <- c(4.9, 6.8, 4.5, 7.1, 6.4, 5.0, 8.6, 7.9, 6.1, 6.2, 4.1, 6.5)
pe <- cor.test(x, y); sp <- cor.test(x, y, method = "spearman", exact = FALSE)
d <- x - y; n <- length(d); s <- sd(d); tq <- qt(.975, n - 1)
out$correlation <- list(x = x, y = y,
  pearson = list(r = unname(pe$estimate), p = pe$p.value, ci = as.numeric(pe$conf.int)),
  spearman = list(rho = unname(sp$estimate), p = sp$p.value),
  bland_altman = list(bias = mean(d), bias_ci = mean(d) + c(-1, 1) * tq * s / sqrt(n),
                      loa = mean(d) + c(-1, 1) * qnorm(.975) * s,
                      loa_low_ci = mean(d) - qnorm(.975) * s + c(-1, 1) * tq * sqrt(3 * s^2 / n),
                      loa_high_ci = mean(d) + qnorm(.975) * s + c(-1, 1) * tq * sqrt(3 * s^2 / n)))
# --- Tailles d'échantillon
out$sample_size <- list(
  means = lapply(list(c(5, 10, .05, .8), c(1, 1, .05, .9), c(0.3, 1.2, .01, .8)), function(v)
    list(delta = v[1], sd = v[2], alpha = v[3], power = v[4], n = power.t.test(delta = v[1], sd = v[2], sig.level = v[3], power = v[4])$n)),
  props = lapply(list(c(.10, .05, .05, .8), c(.4, .25, .05, .9)), function(v)
    list(p1 = v[1], p2 = v[2], alpha = v[3], power = v[4], n = power.prop.test(p1 = v[1], p2 = v[2], sig.level = v[3], power = v[4])$n)),
  nct = lapply(list(c(2.1, 10, 1.5), c(-0.5, 25, 0.8), c(1.96, 58, 2.9), c(3, 4, 4)), function(v)
    list(t = v[1], df = v[2], ncp = v[3], p = pt(v[1], v[2], ncp = v[3]))))
write_ref(out, "fondamentaux")
