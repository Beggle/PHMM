library(MCMCglmm);library(brms);library(tidyverse);library(ape);library(caper);
library(phytools);library(MASS);library(bindata);library(phangorn);#library("plyr")
library(mvtnorm);library(mixtools)


##---------------------------- PRICE MODEL --------------------------------##

# DESCRIPTION
# grow tree to size N by adding one tip per time step. Draw state of new tip (open new niche) from mvnorm with 
# covariance defined by Sigma. calculate euclidean distance between tip states. attach new tip to existing tip 
# with closest state (simulates niche conservatism). N.B. all tips states drawn and euc dists calculated
# up front, but same result as drawing from mvnorm and calculating min dist at each time step.
#
# TO DO / THINK ABOUT
# 1. In the Price model, new species cannot be too close to existing species - incorporate
# 2. Because two clades are evolved separately then joined, open niches might be closer to species in other clade (i.e. represents allopatric clades evolving under identical ecological constraints)

N = 5 # number of species
Sigma <- matrix(c(1,0.75,0.75,1),2,2) # parameters for mvnorm
reps = 2
clades = 2 # generate 2 clades to stitch together
trees.temp <- list() # trees generated in each rep
traits.temp <- list() # trait data (niches) generated in each rep
trees <- list() # final list of trees (short/long stored at same list level)
traits <- list() # final list of (clade appended) trait data)

for (i in 1:reps){
  for (j in 1:clades){
    
    res <- sim.Price(N, Sigma)
    
    traits.temp[[j]] <- res[[1]]
    trees.temp[[j]] <- res[[2]]
    
  }
  
  # create backbone
  phy <- rtree(2); phy$edge.length <- c(1,1)
  a <- trees.temp[[1]] # clade A
  b <- trees.temp[[2]] # clade B
  # b$tip.label <- paste0("s", (N+1):(2*N))
  
  # merge trait data
  t <- rbind(traits.temp[[1]],traits.temp[[2]])
  
  # re-scale both clades to height 1
  a$edge.length<-a$edge.length/max(nodeHeights(a)[,2])*0.9
  b$edge.length<-b$edge.length/max(nodeHeights(b)[,2])*0.9
  
  # duplicate backbone and re-scale to short and long
  phy.1 <- phy;phy.1$edge.length<-phy.1$edge.length/max(nodeHeights(phy.1)[,2])*0.1
  phy.2 <- phy;phy.2$edge.length<-phy.2$edge.length/max(nodeHeights(phy.2)[,2])*1.1
  
  # bind clades onto backbones
  phy1 <- bind.tree(phy.1, a, where = 1, position = 0);phy1 <- bind.tree(phy1, b, where = 1, position = 0)
  phy2 <- bind.tree(phy.2, a, where = 1, position = 0);phy2 <- bind.tree(phy2, b, where = 1, position = 0)
  
  phy1$tip.label <- paste0("t", 1:(2*N))
  phy2$tip.label <- paste0("t", 1:(2*N))

  # store trees
  trees[[i]] <- list(phy1,phy2)
  traits[[i]] <- t
}

# check output
par(mfrow = c(1,2))
plot(trees[[1]][[1]]);plot(traits[[1]], type="n");text(traits[[1]], trees[[1]][[1]]$tip.label, cex=0.8,  col=(rep(c("red",rep("black",N-1)),2))) # short basal branches


##------------------------------ SIMULATE DATA ----------------------------------##

## define parameters

# constants
beta = c(0,0) # intercepts
m = 2 # number of traits

# variables
vars <- data.frame(mod.evo = c("BM1","BM2","BM3","BM4","Price_0.75"),
                   b11 = c(0.75,0.75,0.75,0.75, NA),
                   b22 = c(0,0.75,0.75,0.75, NA),
                   b12_rho = c(0,0,0.5,0.5, NA),
                   c11 = c(0.25,0.25,0.25,0.25, NA),
                   c22 = c(0.25,0.25,0.25,0.25, NA),
                   c12_rho = c(0,0,0,0.5,NA))


## create list to store trees and trait data simulated under each model
# list nesting = [[tree.rep]][[tree.type]][[model.evo]] - HOW TO NAME LIST ELEMENTS PROPERLY?
d.sim <- list(rep(NA,length(trees)))
for (i in 1:length(trees)){d.sim[[i]] <- list(NA,NA)}
for (i in 1:length(trees)){d.sim[[i]][[1]] <- list(NA,NA);d.sim[[i]][[2]] <- rep(list(NA),5)}

## create separate list for data, trees and sim conditions?
# d.sim.new <- rep(list(NA),reps*2*length(vars$mod.evo))
# tree.sim.new <- rep(list(NA),reps*2*length(vars$mod.evo))
# cond.sim.new <- rep(list(NA),reps*2*length(vars$mod.evo))

## LOOP OVER TREE REPS, TREE TYPES and MODEL OF EVOLUTION
for (i in 1:length(trees)){
  for (j in 1:length(trees[[1]])){
    for (k in 1:length(vars$mod.evo)){
      
      tree <- trees[[i]][[j]]
      
      if(k<length(vars$mod.evo)){ # sim data via BM on trees generated from Price model
      
      # phylogenetic covariance matrix
      sig.B <- c(b11 = vars[vars$mod.evo==vars$mod.evo[k],]$b11, b22 = vars[vars$mod.evo==vars$mod.evo[k],]$b22)
      Bcor <- matrix(c(c(1,vars[vars$mod.evo==vars$mod.evo[k],]$b12_rho),c(vars[vars$mod.evo==vars$mod.evo[k],]$b12_rho,1)),m,m, byrow = T) 
      B <- matrix(kronecker(sig.B, sig.B),m,m)*Bcor # VCV (point-wise product). 
      
      # residual covariance matrix
      sig.C <- c(c11 = vars[vars$mod.evo==vars$mod.evo[k],]$c11, c22 = vars[vars$mod.evo==vars$mod.evo[k],]$c22)
      Ccor <- matrix(c(c(1,vars[vars$mod.evo==vars$mod.evo[k],]$c12_rho),c(vars[vars$mod.evo==vars$mod.evo[k],]$c12_rho,1)),m,m, byrow = T) 
      C <- matrix(kronecker(sig.C, sig.C),m,m)*Ccor 
      
      # simulate bivariate trait data under BM
      d <- sim.biv.BM(B, C, tree)
      
      } else { # use trait data simulated under price model
        
        d <- data.frame(animal=tree$tip.label,y1=traits[[i]][,1],y2=traits[[i]][,2])
        
      }
      
      # store simulated data along with tree
      d.sim[[i]][[j]][[k]] <- list(d, tree) 
      
    }
  }
}

# check output by plotting (early split) tree and associated data under BM4
# starting species of each major clade plotted in red
par(mfrow = c(1,2))
plot(d.sim[[1]][[2]][[4]][[2]]);plot(d.sim[[1]][[2]][[4]][[1]][,-1], type="n")
text(d.sim[[1]][[2]][[4]][[1]][,-1], d.sim[[1]][[2]][[4]][[2]]$tip.label, cex=0.8, col=(rep(c("red",rep("black",N-1)),2)))


##------------------------------ FIT MODELS --------------------------------##


## test of sim.biv.fits() function
fits.sim <- list() # list to store all fits
rep <- d.sim[[1]][[1]][[1]] # higher list element within which data (d.sim[[]][[]][[]][[1]]) and tree (d.sim[[]][[]][[]][[2]]) are nested
fits.sim[[1]] <- sim.biv.fits(rep)

# plot focal data set
par(mfrow=c(1,1));plot(rep[[1]][,3],rep[[1]][,2])

# fit summaries
summary(fits.sim[[1]][[1]]) # PGLS
summary(fits.sim[[1]][[2]]) # PMM - need to condition on y2 to compare to effect size to PGLS


## DO NOT RUN ##
## LOOP sim.biv.fits() OVER LIST OF DATA/TREES - HOW TO DO WITH LAPPLY?!
counter = 0
fits.sim <- list()
for (i in 1){
  for (j in 1){
    for (k in 1:length(vars$mod.evo)){
      
      counter <-  counter + 1
      rep <- d.sim[[i]][[j]][[k]]
      fits.sim[[counter]] <- sim.biv.fits(rep)
      
    }
  }
}


## PREVIOUS APPROACH STORING MODEL FITS IN LIST WITHIN SIM LOOP
# ## create list to store model fits
# # list nesting = [[tree.rep]][[tree.type]][[model.evo]] - HOW TO NAME LIST ELEMENTS PROPERLY?
# fits.sim <- list(rep(NA,length(trees)))
# for (i in 1:length(trees)){fits.sim[[i]] <- list(NA,NA)}
# for (i in 1:length(trees)){fits.sim[[i]][[1]] <- list(NA,NA);fits.sim[[i]][[2]] <- list(NA,NA,NA,NA,NA)}

# fits[[i]][[j]][[k]] <- list(fit.pmm,fit.pgls)



##------------------------------ RESULTS ----------------------------------##

## TO DO
# 1. sort out list structure to get everything in the right shape for passing to sim.biv.fits()
# 2. fit PGLS and MV-PMM to each tree/dataset
# 3. confirm that PMM recovers generating parameters for BM
# 4. evaluate PMM partitioning for data generated from price model
# 5. compare conditional effects from PMM to PGLS fit to same data
 

## LEGEND
# list nesting = [[tree.rep]][[tree.type]][[model.evo]]
# tree.rep = 1:ntrees
# tree.type = c(early split, balanced)
# model.evo = c(BM1, BM2) (PRICE to be added)

# rm(list = ls())

select <- dplyr::select
summarise <- dplyr::summarise
map <- purrr::map
theme_set(theme_classic())


# list nesting = [[tree.rep]][[tree.type]][[model.evo]]
# tree.rep = 1:ntrees
# tree.type = c(early split, balanced)
# model.evo = c(BM1, BM2) (PRICE to be added)

compare_fits <- function(f) f %>% 
  map_dfr(~ .x %>% as.data.frame() %>% as_tibble %>% 
            select(-starts_with(c("r","lp"))) %>% 
            imap_dfr(~ c(mean = mean(.x), err = sd(.x)),.id = "var"), .id = "m") %>% 
  ggplot(aes(y = var)) +
  geom_linerange(aes(xmin = mean-2*err, xmax = mean+2*err), data = ~ .x %>% filter(m==1)) +
  geom_point(aes(x = mean), data = ~ .x %>% filter(m==1)) +
  geom_linerange(aes(xmin = mean-2*err, xmax = mean+2*err), 
                 position = position_nudge(y = 0.1),
                 col = "blue", data = ~ .x %>% filter(m==2)) +
  geom_point(aes(x = mean), position = position_nudge(y = 0.1),
             col = "blue", data = ~ .x %>% filter(m==2)) +
  labs(x = "x")


## compare fits to BM1 and BM2 from the same tree (adjusted to agree with structure of fits.sim)
vars
c(fits.sim[[1]][2],fits.sim[[2]][2]) %>% compare_fits + labs(subtitle = "Fits 111 and 112")


d111 <- fits.sim[[1]][[2]]$data %>% mutate(clade = c(rep("A",nrow(.)/2),rep("B",nrow(.)/2))) %>% as.tibble
d112 <- fits.sim[[2]][[2]]$data %>% mutate(clade = c(rep("A",nrow(.)/2),rep("B",nrow(.)/2))) %>% as.tibble
d111 %>% group_by(clade) %>% summarise(y1 =mean(y1),y2 = mean(y2)) 
d112 %>% group_by(clade) %>% summarise(y1 =mean(y1),y2 = mean(y2)) 
A111 <- fits.sim[[1]][[2]]$data2$A
A112 <- fits.sim[[2]][[2]]$data2$A # How do I reconstruct the tree from A?

## LIKE THIS (but something wrong....)
T111 <- vcv2phylo(A111) # tree from vcv
plot(T111);plot(trees[[1]][[1]]) # confirm it is the same tree - NO! don't know why...
fits.sim[[1]][[2]]$data2$A==vcv.phylo(trees[[1]][[1]], corr = T) # A.mat from model fit identical to that from trees[[]] aside from constant added to diagonal, so something to do with vcv2phylo()


# ## compare fits to BM1 from balanced and early split trees
# c(fits[[1]][[1]][1],fits[[1]][[2]][1]) %>% compare_fits + labs(subtitle = "Fits 111 and 121")
# summary(fits[[1]][[1]][[1]]);plot(trees[[1]][[1]]) # balanced
# summary(fits[[1]][[2]][[1]]);plot(trees[[1]][[2]]) # early split
# 
# ## compare fits to BM2 from balanced and early split trees
# c(fits[[1]][[1]][2],fits[[1]][[2]][2]) %>% compare_fits + labs(subtitle = "Fits 112 and 122")
# summary(fits[[1]][[1]][[2]])
# summary(fits[[1]][[2]][[2]])



# # generating parameters for reference
# vars
# ## compare fits to BM1 and BM2 from the same tree
# summary(fits[[1]][[1]][[1]])
# summary(fits[[1]][[1]][[2]])
# ## compare fits to BM1 from balanced and early split trees
# summary(fits[[1]][[1]][[1]]);plot(trees[[1]][[1]]) # balanced
# summary(fits[[1]][[2]][[1]]);plot(trees[[1]][[2]]) # early split
# ## compare fits to BM2 from balanced and early split trees
# summary(fits[[1]][[1]][[2]])
# summary(fits[[1]][[2]][[2]])




##---------------------------- ~ --------------------------------##



## TO DO / RESOLVE ##

# 1. WHY ARE MEANS FOR CLADES A AND B NOT MORE DIFFERENT IN OUR SIM DATA?

# means of clade A and clade B
mean(d[d$clade=="A",]$y1);mean(d[d$clade=="B",]$y1)
# sig difference between means of clade A and clade B?
t.test(d[d$clade=="A",]$y1,d[d$clade=="B",]$y1)
# compare to difference when BM simulated directly on the trees - sig2 != b_11?
x<-fastBM(trees[[1]][[1]],sig2=1)
mean(x[1:50])-mean(x[51:100])
y<-fastBM(trees[[1]][[2]],sig2=1)
mean(y[1:50])-mean(y[51:100])



##------------------------------ SIMULATE BD TREES ---------------------------------##

n=10 # n taxa

trees <- list()
for (i in 1:2){
  
  t <- geiger::sim.bdtree(b=1, d=0, stop="taxa", n=2, extinct=FALSE) # backbone
  a <- geiger::sim.bdtree(b=1, d=0, stop="taxa", n=n, extinct=FALSE) # clade A
  b <- geiger::sim.bdtree(b=1, d=0, stop="taxa", n=n, extinct=FALSE) # clade B
  
  b$tip.label <- paste0("s",(n+1):(2*n))
  
  # re-scale both clades to height 1
  a$edge.length<-a$edge.length/max(nodeHeights(a)[,2])*0.90
  b$edge.length<-b$edge.length/max(nodeHeights(b)[,2])*0.90
  
  # duplicate backbone and re-scale to short and long
  t.1 <- t;t.1$edge.length<-t.1$edge.length/max(nodeHeights(t.1)[,2])*0.1
  t.2 <- t;t.2$edge.length<-t.2$edge.length/max(nodeHeights(t.2)[,2])*1.1
  
  # bind clades onto backbones
  t1 <- bind.tree(t.1, a, where = 1, position = 0)
  t1 <- bind.tree(t1, b, where = 1, position = 0)
  t2 <- bind.tree(t.2, a, where = 1, position = 0)
  t2 <- bind.tree(t2, b, where = 1, position = 0)
  
  trees[[i]] <- list(t1,t2)
}

# saveRDS(trees, "trees.rds")



##--------------------------- NOTES --------------------------------##

# final tree heights and plot first pair of trees in list
nodeheight(trees[[1]][[1]],1);plot(trees[[1]][[1]])
nodeheight(trees[[1]][[2]],1);plot(trees[[1]][[2]])

# # match heights of clades by adding difference to shorter of the pair
# x <- c(nodeheight(t1,1)-nodeheight(t1,n+1),nodeheight(t1,n+1)-nodeheight(t1,1))
# if (which(x<=0)==1){t1$edge.length[1] <- t1$edge.length[1]+x[which(x>=0)]} else {t1$edge.length[100] <- t1$edge.length[100]+x[which(x>=0)]}


##-------------------------- REFERENCE --------------------------##

### DEFINE SIMULATION PARAMETERS ###


#### SIMULATE TREE ####

# simulate tree
seed <- 58198 # sample(1e6,1); seed
# seed 58198
t1 <- geiger::sim.bdtree(b=1, d=0, stop="taxa", n=50, seed = seed, extinct=FALSE) # sim until we get one with two major clades
plot(t1)
#t1 <- multi2di(t1)

# create duplicate with long basal edges
t2 <- t1
adj <- t2$edge.length[1]-t2$edge.length[50]
t2$edge.length[50] <- 5-adj
t2$edge.length[1] <- 5

# compare trees
plot(t1)
plot(t2)

### END ####


#### SIMULATE DATA ####

# Create VCV matrix from tree, scale to correlation matrix for BRMS
A.mat <- ape::vcv.phylo(t2, corr = T) # scale with corr = T
A.mat

# ## alternative method 
# inv.phylo <- MCMCglmm::inverseA(t.toy, nodes = "TIPS", scale = TRUE)
# A <- solve(inv.phylo$Ainv)
# rownames(A) <- rownames(inv.phylo$Ainv)
# A.mat <- A

# number of traits
k = 2

# intercepts for each trait - plogis(beta[1]) to get on probability scale
beta = c(1,2)

## B is the phylogenetic trait-level VCV matrix (Sigma_{phy} in the HTML). B specifies the phylogenetic
## variance in each trait (diagonals) as well as the phylogenetic covariance between traits (off-diagnonals).
## Each unique element in B is to be estimated by the model.
sig.B <- c(b11 = 0.4, b22 = 0.6) # standard deviation of diagonal components (i.e. sqrt of the phylogenetic variance for each trait)
b12_rho = 0.5

Bcor <- matrix(c(c(1,b12_rho), # correlation matrix
                 c(b12_rho,1)),k,k, byrow = T) 

B <- matrix(kronecker(sig.B, sig.B),k,k)*Bcor # VCV (point-wise product). 
B
# N.B. Kronecker used here just for matrix formatting. Do not confuse with kronecker discussed in the text / tutorial.

## C is the residual trait-level VCV matrix (Sigma_{res} in the HTML).
sig.C <- c(c11 = 0.1, c22 = 0.1) # standard deviation of diagonal components (i.e. sqrt of the residual variance for each trait)
c12_rho = 0 # off-diagonal correlation coefficients

Ccor <- matrix(c(c(1,c12_rho), # correlation matrix
                 c(c12_rho,1)),k,k, byrow = T) 

C <- matrix(kronecker(sig.C, sig.C),k,k)*Ccor # VCV
C

# The phylogenetic taxon-level VCV matrix, A, is supplied. It is therefore treated as fixed and known without error, although may represent a transformation (see above).
A = A.mat

# number of species
n = nrow(A); n

# identity matrix
I = diag(n)

# simulate phylogenetic random effects for all traits as one draw from a MVN:
a <- mvrnorm(1,rep(0,n*k),kronecker(B,A)) # In the Kronecker, trait-level covariance captured by B, taxon-level covariance captured by A. 

# extract random effects for each trait from the vector, a.
a1 <- a[1:n]
a2 <- a[1:n + n]

# simulate residuals (on the link scale)
e <- mvrnorm(1,rep(0,n*k),kronecker(C,I))
e1 <- e[1:n]
e2 <- e[1:n + n]

# construct response traits from each linear predictor
g1 <- beta[1] + a1 + e1 # gaussian
g2 <- beta[2] + a2 + e2
b1 <- rbinom(n,1,plogis(beta[1] + a1 + e1)) # binomial
b2 <- rbinom(n,1,plogis(beta[2] + a2 + e2))

# generate df
species <- t.toy$tip.label
d.toy <- data.frame(species,g1,g2,b1,b2)
d.toy$animal <- d.toy$species # "animal" is a reserved term in MCMCglmm used to identify taxa in quantitative and phylogenetic models
d.toy$obs <- 1:nrow(d.toy)
head(d.toy)

## plot gaussians
# plot(d.toy$g1, d.toy$g2)
# table binomials
table(d.toy$b1, d.toy$b2)
table(d.toy$b1, d.toy$b2)/250 # prop

## take a look at probabilities on the inverse-link scale
# plogis(beta[1])
# plogis(beta[1] + a1 + e1)[1:10]

### END ####


##------------------- MULTIVARIATE GAUSSIAN ---------------------##

m.1 <- readRDS("m.1.rds")
b.1 <- readRDS("b.1.rds")

### FIT MODELS ####

### MCMCglmm
p <- list(R = list(R1=list(V = diag(2), nu=2)),
          G = list(G1=list(V = diag(2), nu=2)))
m.1 <- MCMCglmm(cbind(g1, g2) ~ trait-1, 
                random = ~us(trait):animal, 
                rcov = ~us(trait):units, 
                pedigree=t.toy,
                family = c("gaussian","gaussian"), 
                nodes="ALL", data = d.toy, prior=p,
                nitt=600000, burnin=100000, thin=500, 
                pr=TRUE,verbose = FALSE)

## DIAGNOSTICS
# view chain
# plot(m.1$VCV)
# calculate autocorrelation among samples
# autocorr(m.1$VCV)


## For good practice, let's explicitly state the default priors

### BRMS
b.1 <- brm(
  mvbind(g1, g2) ~ (1|p|gr(animal, cov = A)), 
  data = d.toy,
  data2 = list(A = A.mat),
  family = gaussian(),
  cores = 4,
  chains = 4, iter = 2000, thin = 2
)
b.1
## DIAGNOSTICS
pairs(b.1)
b.1 %>% plot
b.1 %>% pp_check(resp = "g1",ndraws = 100)
b.1 %>% pp_check(resp = "g2",ndraws = 100)
conditional_effects(b.1)


## COMPARISON BETWEEN METHODS
# N.B. Location estimates are directly comparable between MCMCglmm and BRMS (assuming no variances have fixed OR fixed at same level). However, for variance 
# components, MCMCglmm reports (co)variances while brms reports standard deviations and trait-level correlations. Therefore, some re-scaling is necessary to 
# to compare results between model fits. We have chosen to re-scale the estimates from MCMCglmm, as stdevs and corrs are more natural to interpret.
#
# Presumably, any differences are due to the differing priors.. do we want to confirm this or discuss merits of brms defaults?

# summary outputs
summary(m.1) # MCMCglmm
summary(b.1) # brms

# make nice plots to compare estimates and simulated values (i.e., reflected density plots)

# intercepts
summary(m.1)$solutions
summary(b.1)[["fixed"]]

# transform posterior columns first, then compute summary statistics and density plots etc.
# phylogenetic variances (elements of sig.B) and phylogenetic correlation (b12_rho)  # Q. SQRT OF CI CORRECT CI FOR VARIANCES?
sqrt(summary(m.1)$Gcovariances)[c(1,nrow(summary(m.1)$Gcovariances)),];data.frame(row.names = "traitg1:traitg2.animal", post.mean = mean(m.1$VCV[,"traitg1:traitg2.animal"]/sqrt(m.1$VCV[,"traitg1:traitg1.animal"]*m.1$VCV[,"traitg2:traitg2.animal"])))
summary(b.1)[["random"]]

# residual covariances (elements of sig.C) and residual correlation (c12_rho) 
sqrt(summary(m.1)$Rcovariances[c(1,nrow(summary(m.1)$Gcovariances)),]);data.frame(row.names = "traitg1:traitg2.units", post.mean = mean(m.1$VCV[,"traitg1:traitg2.units"]/sqrt(m.1$VCV[,"traitg1:traitg1.units"]*m.1$VCV[,"traitg2:traitg2.units"])))
summary(b.1)[["spec_pars"]];summary(b.1)[["rescor_pars"]]


### END ####

