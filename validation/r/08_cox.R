# Régression de Cox : références survival::coxph, cox.zph, concordance.
# Jeux publics du paquet survival : lung (NCCTG) et veteran (Kalbfleisch & Prentice).
source("_common.R")
suppressPackageStartupMessages(library(survival))
lung2 <- survival::lung
lung2$sexe <- ifelse(lung2$sex == 1, "H", "F")
lung2$deces <- ifelse(lung2$status == 2, "oui", "non")
write.csv(lung2[, c("time", "deces", "age", "sexe", "ph.ecog", "wt.loss")], file.path(REF_DIR, "cox_lung.csv"), row.names = FALSE, na = "")
vet <- survival::veteran
vet$deces <- ifelse(vet$status == 1, "oui", "non")
vet$trt <- ifelse(vet$trt == 1, "standard", "test")
write.csv(vet[, c("time", "deces", "trt", "celltype", "karno", "age", "prior")], file.path(REF_DIR, "cox_veteran.csv"), row.names = FALSE)
one <- function(f, d, ties) {
  m <- eval(bquote(coxph(.(f), data = .(d), ties = .(ties), control = coxph.control(eps = 1e-12, toler.chol = 1e-14, iter.max = 100))))
  s <- summary(m); z <- cox.zph(m)
  list(coef = unname(coef(m)), se = unname(sqrt(diag(vcov(m)))), names = names(coef(m)),
       loglik = m$loglik, lr = 2 * diff(m$loglik), wald = unname(m$wald.test), score = unname(m$score),
       concordance = unname(m$concordance["concordance"]), n = m$n, nevent = m$nevent,
       zph = unname(z$table[, 1]), zph_names = rownames(z$table))
}
lung2$sexe <- relevel(factor(lung2$sexe), "H")
vet$trt <- relevel(factor(vet$trt), "standard"); vet$celltype <- relevel(factor(vet$celltype), "squamous")
write_ref(list(
  lung_efron = one(Surv(time, deces == "oui") ~ age + sexe + ph.ecog + wt.loss, lung2, "efron"),
  lung_breslow = one(Surv(time, deces == "oui") ~ age + sexe + ph.ecog + wt.loss, lung2, "breslow"),
  vet_efron = one(Surv(time, deces == "oui") ~ trt + celltype + karno + age, vet, "efron")), "cox")
