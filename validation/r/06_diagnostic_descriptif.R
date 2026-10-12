source("_common.R")
diag <- function(tp, fp, fn, tn) {
  w <- function(x, n) as.numeric(prop.test(x, n, correct = FALSE)$conf.int)
  se <- tp / (tp + fn); sp <- tn / (tn + fp)
  lrp <- se / (1 - sp); lrn <- (1 - se) / sp
  slp <- sqrt(1/tp - 1/(tp + fn) + 1/fp - 1/(fp + tn)); sln <- sqrt(1/fn - 1/(tp + fn) + 1/tn - 1/(fp + tn))
  list(tp = tp, fp = fp, fn = fn, tn = tn, se = se, se_ci = w(tp, tp + fn), sp = sp, sp_ci = w(tn, tn + fp),
       ppv_ci = w(tp, tp + fp), npv_ci = w(tn, tn + fn), lrp = lrp, lrp_ci = exp(log(lrp) + c(-1, 1) * qnorm(.975) * slp),
       lrn = lrn, lrn_ci = exp(log(lrn) + c(-1, 1) * qnorm(.975) * sln),
       ppv_01 = se * 0.01 / (se * 0.01 + (1 - sp) * 0.99))
}
x <- c(4.2, 5.8, 6.1, 3.9, 7.4, 5.5, 6.6, 12.3, 4.8, 5.1, NA, 6.0)
xx <- x[!is.na(x)]
tt <- t.test(xx)
q <- quantile(xx, c(.25, .5, .75), type = 7)
n <- length(xx); m <- mean(xx); s <- sd(xx)
skew <- (sum((xx - m)^3) / n) / (sum((xx - m)^2) / n)^1.5 * sqrt(n * (n - 1)) / (n - 2)
write_ref(list(diagnostic = list(diag(90, 30, 10, 870), diag(45, 12, 5, 38)),
  describe = list(x = x, mean = m, sd = s, ci = as.numeric(tt$conf.int), q = unname(q), skew = skew)), "diagnostic_descriptif")
