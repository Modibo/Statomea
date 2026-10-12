source("_common.R")
suppressPackageStartupMessages(library(metafor))
ctl <- list(threshold = 1e-12, maxiter = 1000)
res_of <- function(r) list(mu = as.numeric(r$b), se = r$se, ci = c(r$ci.lb, r$ci.ub), p = r$pval,
                           tau2 = r$tau2, Q = r$QE, Qp = r$QEp, I2 = r$I2 / 100, H2 = r$H2)
pi_t <- function(r) { k <- r$k; as.numeric(r$b) + c(-1, 1) * qt(.975, k - 2) * sqrt(r$tau2 + r$se^2) }
out <- list()
# --- BCG (Colditz 1994), données publiques de metafor
b <- dat.bcg
b$e1 <- b$tpos; b$n1 <- b$tpos + b$tneg; b$e2 <- b$cpos; b$n2 <- b$cpos + b$cneg
b$sub <- ifelse(b$alloc == "random", "aléatoire", "non aléatoire")
out$bcg_data <- lapply(seq_len(nrow(b)), function(i) list(label = paste0(b$author[i], " ", b$year[i]), e1 = b$e1[i], n1 = b$n1[i], e2 = b$e2[i], n2 = b$n2[i], ablat = b$ablat[i], sub = b$sub[i]))
for (m in c("RR", "OR", "RD")) {
  es <- escalc(measure = m, ai = e1, n1i = n1, ci = e2, n2i = n2, data = b)
  rr <- rma(yi, vi, data = es, method = "REML", control = ctl)
  dl <- rma(yi, vi, data = es, method = "DL")
  fe <- rma(yi, vi, data = es, method = "FE")
  hk <- rma(yi, vi, data = es, method = "REML", test = "knha", control = ctl)
  ll <- leave1out(dl)
  out[[paste0("bcg_", m)]] <- list(yi = as.numeric(es$yi), vi = as.numeric(es$vi), reml = res_of(rr), dl = res_of(dl), fe = res_of(fe),
    knha = res_of(hk), pi_reml = pi_t(rr), loo_dl = as.numeric(ll$estimate),
    egger = { e <- lm(I(es$yi / sqrt(es$vi)) ~ I(1 / sqrt(es$vi))); summary(e)$coefficients[1, c(1, 2, 4)] })
}
mhor <- rma.mh(ai = e1, n1i = n1, ci = e2, n2i = n2, data = b, measure = "OR")
mhrr <- rma.mh(ai = e1, n1i = n1, ci = e2, n2i = n2, data = b, measure = "RR")
out$bcg_mh <- list(or = c(as.numeric(mhor$b), mhor$se), rr = c(as.numeric(mhrr$b), mhrr$se))
es <- escalc(measure = "RR", ai = e1, n1i = n1, ci = e2, n2i = n2, data = b)
sg <- rma(yi, vi, mods = ~ sub, data = es, method = "FE")
out$bcg_subgroup_QM <- sg$QM
# --- Continu : Normand 1999 (durée d'hospitalisation)
nd <- dat.normand1999
out$normand_data <- lapply(seq_len(nrow(nd)), function(i) list(label = nd$source[i], m1 = nd$m1i[i], sd1 = nd$sd1i[i], n1 = nd$n1i[i], m2 = nd$m2i[i], sd2 = nd$sd2i[i], n2 = nd$n2i[i]))
for (m in c("MD", "SMD")) {
  es <- escalc(measure = m, m1i = m1i, sd1i = sd1i, n1i = n1i, m2i = m2i, sd2i = sd2i, n2i = n2i, data = nd)
  out[[paste0("normand_", m)]] <- list(yi = as.numeric(es$yi), vi = as.numeric(es$vi),
    reml = res_of(rma(yi, vi, data = es, method = "REML", control = ctl)), dl = res_of(rma(yi, vi, data = es, method = "DL")))
}
# --- Événements rares et cellules nulles (données fictives)
z <- data.frame(e1 = c(0, 1, 2, 0, 3), n1 = c(50, 120, 80, 40, 200), e2 = c(2, 4, 3, 0, 9), n2 = c(48, 118, 85, 42, 190))
out$zero_data <- as.list(z)
esz <- escalc(measure = "OR", ai = e1, n1i = n1, ci = e2, n2i = n2, data = z, drop00 = TRUE)
out$zero_OR <- list(yi = as.numeric(esz$yi), vi = as.numeric(esz$vi),
  dl = res_of(rma(yi, vi, data = esz, method = "DL")),
  mh = { m <- rma.mh(ai = e1, n1i = n1, ci = e2, n2i = n2, data = z, measure = "OR"); c(as.numeric(m$b), m$se) })
write_ref(out, "meta")
