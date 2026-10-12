# IC par vraisemblance profilée pénalisée et tests du RV pénalisé (logistf, pl = TRUE).
source("_common.R")
suppressPackageStartupMessages(library(logistf))
ctl <- logistf.control(xconv = 1e-12, gconv = 1e-12, maxit = 500)
plc <- logistpl.control(xconv = 1e-12, lconv = 1e-12, maxit = 500)
one <- function(f, d) {
  m <- logistf(f, data = d, pl = TRUE, control = ctl, plcontrol = plc)
  list(coef = unname(coef(m)), lower = unname(m$ci.lower), upper = unname(m$ci.upper), p = unname(m$prob),
       names = names(coef(m)))
}
fd <- read.csv(file.path(REF_DIR, "firth_data.csv")); fd$grp <- relevel(factor(fd$grp), "A")
set.seed(99)
n <- 60
x1 <- round(rnorm(n, 0, 1), 3); x2 <- round(rnorm(n, 50, 10), 1); g <- sample(c("a", "b", "c"), n, TRUE)
y <- rbinom(n, 1, plogis(-1.8 + 0.9 * x1 + 0.03 * (x2 - 50) + 0.6 * (g == "c")))
d2 <- data.frame(y, x1, x2, g)
write.csv(d2, file.path(REF_DIR, "firth_data2.csv"), row.names = FALSE)
d2$g <- relevel(factor(d2$g), "a")
ag <- read.csv(file.path(REF_DIR, "aghbs_simule.csv"), na.strings = "")
inf <- ag[!is.na(ag$enfant_suivi) & ag$enfant_suivi == "oui", ]
inf$yy <- as.integer(inf$enfant_infecte == "oui"); inf$aghbe <- relevel(factor(inf$aghbe), "negatif")
write_ref(list(sep = one(y ~ x1 + grp, fd), multi = one(y ~ x1 + x2 + g, d2), events2 = sum(d2$y),
               aghbs = one(yy ~ aghbe, inf)), "firth_profile")
