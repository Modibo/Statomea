# Modèle mixte logistique (GMMAT, Chen et al. 2016) : logit P(y = 1) = Xα + b, b ~ N(0, τK), K = GRM standardisée
# (comme 30_lmm.R) ; modèle nul ajusté par quasi-vraisemblance pénalisée (PQL) avec τ par REML sur le modèle de travail
# (dispersion fixée à 1), puis test du score par variant : U = gᵀ(y − μ̂), V = gᵀPg, U²/V ~ χ²₁.
# Références : GMMAT 1.4.2 (glmmkin, AI-REML, tol = 1e-5 ; U et V calculés à partir de obj$P et obj$scaled.residuals
# exactement comme glmm.score), et recalcul R serré du même point fixe :
#   à chaque itération, poids W = μ(1 − μ), réponse de travail Y = η + (y − μ)/W, Σ = W⁻¹ + τK ;
#   τ maximise la vraisemblance REML du modèle de travail (optimize sur log τ, tol 1e-12, bornes 1e-8 à 1e5) ;
#   α = (XᵀΣ⁻¹X)⁻¹XᵀΣ⁻¹Y, η = Xα + τKΣ⁻¹(Y − Xα) ; arrêt quand τ et α varient de moins de 1e-10 (relatif).
# DONNÉES : génotypes familiaux de 30_lmm.R (600 sujets dont 450 en fratries, 1 500 variants) ; maladie = 40 % des valeurs
# les plus élevées du trait quantitatif simulé ; covariables sexe et âge.
source("_common.R")
suppressPackageStartupMessages({ library(genio); library(GMMAT) })
GDIR <- file.path(REF_DIR, "genotypes")
P0 <- read_plink(file.path(GDIR, "lmm"), verbose = FALSE)
G <- t(P0$X); n <- nrow(G); m <- ncol(G); ids <- P0$fam$id
ph <- read.csv(file.path(GDIR, "lmm_phenotypes.csv"))
ph <- ph[match(ids, ph$id), ]
y <- as.integer(ph$trait > quantile(ph$trait, 0.6))
write.csv(data.frame(id = ids, maladie = ifelse(y == 1, "oui", "non")), file.path(GDIR, "glmm_phenotypes.csv"), row.names = FALSE, quote = FALSE)
sexe <- P0$fam$sex; age <- ph$age
pf <- colMeans(G) / 2
Xg <- sweep(sweep(G, 2, 2 * pf), 2, sqrt(2 * pf * (1 - pf)), "/")
K <- tcrossprod(Xg) / m; rownames(K) <- colnames(K) <- ids
Xf <- cbind(1, sexe == 2, age)

# 1) GMMAT.
d <- data.frame(id = ids, y = y, sexe = factor(sexe), age = age)
o <- glmmkin(y ~ sexe + age, data = d, kins = K, id = "id", family = binomial("logit"))
U <- as.vector(crossprod(G, o$scaled.residuals)); V <- colSums(G * (o$P %*% G))
p_gmmat <- pchisq(U^2 / V, 1, lower.tail = FALSE)

# 2) Recalcul serré.
pql <- function() {
  f0 <- glm(y ~ Xf - 1, binomial, control = glm.control(epsilon = 1e-14))
  alpha <- coef(f0); eta <- as.vector(Xf %*% alpha); tau <- 0.1
  for (it in 1:200) {
    mu <- plogis(eta); W <- mu * (1 - mu); Y <- eta + (y - mu) / W
    D <- sqrt(W); A <- outer(D, D) * K
    e <- eigen(A, symmetric = TRUE); U1 <- e$vectors; lam <- pmax(e$values, 0)
    Yt <- crossprod(U1, D * Y); Xt <- crossprod(U1, D * Xf)
    obj <- function(lt) {
      w <- 1 / (1 + exp(lt) * lam); A2 <- crossprod(Xt, Xt * w); b <- solve(A2, crossprod(Xt, Yt * w)); r <- Yt - Xt %*% b
      sum(log(1 + exp(lt) * lam)) + as.numeric(determinant(A2)$modulus) + sum(w * r^2)
    }
    tauN <- exp(optimize(obj, c(log(1e-8), log(1e5)), tol = 1e-12)$minimum)
    w <- 1 / (1 + tauN * lam); A2 <- crossprod(Xt, Xt * w); alphaN <- as.vector(solve(A2, crossprod(Xt, Yt * w)))
    r <- Y - Xf %*% alphaN
    Sir <- D * (U1 %*% (w * crossprod(U1, D * r)))                  # Σ⁻¹ r
    etaN <- as.vector(Xf %*% alphaN + tauN * K %*% Sir)
    conv <- abs(tauN - tau) / (tau + 1e-10) < 1e-10 && max(abs(alphaN - alpha) / (abs(alpha) + 1e-10)) < 1e-10
    tau <- tauN; alpha <- alphaN; eta <- etaN
    if (conv) break
  }
  mu <- plogis(eta); W <- mu * (1 - mu)
  D <- sqrt(W); e <- eigen(outer(D, D) * K, symmetric = TRUE); U1 <- e$vectors; lam <- pmax(e$values, 0)
  w <- 1 / (1 + tau * lam); Xt <- crossprod(U1, D * Xf); A2 <- crossprod(Xt, Xt * w)
  Gt <- crossprod(U1, D * G); XwG <- crossprod(Xt, Gt * w)
  V <- colSums(w * Gt^2) - colSums(XwG * solve(A2, XwG))
  U <- as.vector(crossprod(G, y - mu))
  list(tau = tau, alpha = alpha, iter = it, U = U, V = V, p = pchisq(U^2 / V, 1, lower.tail = FALSE))
}
t1 <- pql()
naive <- sapply(1:m, function(j) summary(glm(y ~ G[, j] + factor(sexe) + age, binomial))$coefficients[2, 4])
gc <- function(pv) median(qchisq(pv, 1, lower.tail = FALSE)) / qchisq(0.5, 1)
write_ref(list(n = n, m = m, gmmat_tau = unname(o$theta[2]), gmmat_alpha = unname(o$coefficients), p_gmmat = p_gmmat,
               tau = t1$tau, alpha = unname(t1$alpha), iter = t1$iter, U = t1$U, V = t1$V, p = t1$p,
               gc_glmm = gc(t1$p), gc_naive = gc(naive), cases = sum(y)), "glmm")
cat("τ GMMAT", o$theta[2], " serré", t1$tau, "(", t1$iter, "itérations ) ; α", t1$alpha, "\nmax |Δlog10 p| GMMAT–serré",
    max(abs(log10(p_gmmat) - log10(t1$p))), " ; λ naïf", gc(naive), " GLMM", gc(t1$p), "\n")
