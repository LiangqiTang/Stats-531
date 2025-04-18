# load the data
library(tidyverse)
library(ggplot2)
read_csv(paste0("https://kingaa.github.io/sbied/stochsim/",
                "Measles_Consett_1948.csv")) |>
  select(week,reports=cases) -> meas

# implement the SIR model in pomp
library(pomp)

# step function: E is similar to the component I, add E in the chain
seir_step <- Csnippet("
  double dN_SE = rbinom(S,1-exp(-Beta*I/N*dt));
  double dN_EI = rbinom(E,1-exp(-mu_EI*dt));
  double dN_IR = rbinom(I,1-exp(-mu_IR*dt));
  S -= dN_SE;
  E += dN_SE - dN_EI;
  I += dN_EI - dN_IR;
  R += dN_IR;
  H += dN_IR;
")

# initial function: suppose we do not no the latent value of E at first.
seir_rinit <- Csnippet("
  S = nearbyint(eta*N);
  E = 0; 
  I = 1;
  R = nearbyint((1-eta)*N);
  H = 0;
")

# dmeasure component
seir_dmeas <- Csnippet("
  lik = dnbinom_mu(reports,k,rho*H,give_log);
")

# rmeasure component
seir_rmeas <- Csnippet("
  reports = rnbinom_mu(k,rho*H);
")

# add components to pomp model: clarify E and mu_EI
meas |>
  pomp(times="week",t0=0,
       rprocess=euler(seir_step,delta.t=1/7),
       rinit=seir_rinit,
       rmeasure=seir_rmeas,
       dmeasure=seir_dmeas,
       accumvars="H",
       statenames=c("S","E","I","R","H"),
       paramnames=c("Beta","mu_EI","mu_IR","N","eta","rho","k"),
       params=c(Beta=30,mu_EI=0.8,mu_IR=1,rho=0.5,k=10,eta=0.05,N=38000)
  ) -> measSEIR


measSEIR |>
  pfilter(Np = 1000) -> pf

plot(pf)




fixed_params <- c(N=38000, mu_EI=1.5, mu_IR=2, k=10) # here I additionally fix mu_EI=1.5
coef(measSEIR, names(fixed_params)) <- fixed_params




library(foreach)
library(doParallel)
library(doRNG)

registerDoParallel(36)
registerDoRNG(123456)


# running a particle filter
foreach(i=1:10,.combine=c,.packages = c("pomp")
) %dopar% {
  measSEIR |> pfilter(Np=5000)
} -> pf
pf |> logLik() |> logmeanexp(se=TRUE) -> L_pf
L_pf




pf[[1]] |> coef() |> bind_rows() |>
  bind_cols(loglik=L_pf[1],loglik.se=L_pf[2]) |>
  write_csv("measles_params.csv")




# do local search
foreach(i=1:20,.combine=c,.packages = c("pomp")
) %dopar% {
  measSEIR |>
    mif2(
      Np=2000, Nmif=50,
      cooling.fraction.50=0.5,
      rw.sd=rw_sd(Beta=0.02, rho=0.02, eta=ivp(0.02)),
      partrans=parameter_trans(log="Beta",logit=c("rho","eta")),
      paramnames=c("Beta","rho","eta")
    )
} -> mifs_local



# Iterated filtering diagnostics
mifs_local |>
  traces() |>
  melt() |>
  ggplot(aes(x=iteration,y=value,group=.L1,color=factor(.L1)))+
  geom_line()+
  guides(color="none")+
  facet_wrap(~name,scales="free_y")



# estimating the likelihood
system.time(foreach(mf=mifs_local,.combine=rbind,.packages = c("pomp")
) %dopar% {
  evals <- replicate(10, logLik(pfilter(mf,Np=5000)))
  ll <- logmeanexp(evals,se=TRUE)
  mf |> coef() |> bind_rows() |>
    bind_cols(loglik=ll[1],loglik.se=ll[2])
} -> results_local) -> time1

pairs(~loglik+Beta+eta+rho,data=results,pch=16)




# build up a picture of the likelihood surface
read_csv("measles_params.csv") |>
  bind_rows(results_local) |>
  arrange(-loglik) |>
  write_csv("measles_params.csv")




set.seed(2062379496)
runif_design(
  lower=c(Beta=5,rho=0.2,eta=0),
  upper=c(Beta=80,rho=0.9,eta=1),
  nseq=200 # change start points from 400 to 200
) -> guesses
mf1 <- mifs_local[[1]]




library(iterators)

system.time(foreach(guess=iter(guesses,"row"), .combine=rbind,.packages = c("pomp")
) %dopar% {
  mf1 |>
    mif2(params=c(guess,fixed_params)) |>
    mif2(Nmif=100) -> mf 
  replicate(
    10,
    mf |> pfilter(Np=1500) |> logLik() # change Np from 5000 to 1500
  ) |>
    logmeanexp(se=TRUE) -> ll
  mf |> coef() |> bind_rows() |>
    bind_cols(loglik=ll[1],loglik.se=ll[2])
} -> results_global) -> time2




# build up a picture of the likelihood surface
read_csv("measles_params.csv") |>
  bind_rows(results_global) |>
  arrange(-loglik) |>
  write_csv("measles_params.csv")





# show scatter plot matrix
read_csv("measles_params.csv") |>
  #filter(loglik>max(loglik)-50) |> # can't not filt, otherwise no data
  bind_rows(guesses) |>
  mutate(type=if_else(is.na(loglik),"guess","result")) |>
  arrange(type) -> all

pairs(~loglik+Beta+eta+rho, data=all, pch=16, cex=0.3,
      col=ifelse(all$type=="guess",grey(0.5),"red"))





# poor man's profile likelihood
all |>
  filter(type=="result") |>
  filter(loglik>max(loglik)-10) |>
  ggplot(aes(x=eta,y=loglik))+
  geom_point()+
  labs(
    x=expression(eta),
    title="poor man’s profile likelihood"
  )



local_global <- read_csv("measles_params.csv")
local_global[which.max(local_global$loglik[!is.na(local_global$loglik)]), c("loglik","loglik.se")]




local_global[which.max(local_global$loglik),c("Beta","rho","eta")]



read_csv("measles_params.csv") |>
  #filter(loglik>max(loglik)-20,loglik.se<2) |>
  sapply(range) -> box
box



freeze(seed=1196696958,
       profile_design(
         eta=seq(0.01,0.95,length=40),
         lower=box[1,c("Beta","rho")],
         upper=box[2,c("Beta","rho")],
         nprof=15, type="runif"
       )) -> guesses
plot(guesses)




system.time(foreach(guess=iter(guesses,"row"), .combine=rbind,.packages = c("pomp")
) %dopar% {
  mf1 |>
    mif2(params=c(guess,fixed_params),
         rw.sd=rw_sd(Beta=0.02,rho=0.02)) |>
    mif2(Nmif=30,cooling.fraction.50=0.3) -> mf
  replicate(
    10,
    mf |> pfilter(Np=1000) |> logLik()) |> # change Np from 5000 to 1500
    logmeanexp(se=TRUE) -> ll
  mf |> coef() |> bind_rows() |>
    bind_cols(loglik=ll[1],loglik.se=ll[2])
} -> results_profile) -> time3



read_csv("measles_params.csv") |>
  bind_rows(results_profile) |>
  filter(is.finite(loglik)) |>
  arrange(-loglik) |>
  write_csv("measles_params.csv")


read_csv("measles_params.csv") |>
  filter(loglik>max(loglik)-10) -> all
pairs(~loglik+Beta+eta+rho,data=all,pch=16)


results_profile |>
  filter(is.finite(loglik)) |>
  group_by(round(rho,5)) |>
  filter(rank(-loglik)<3) |>
  ungroup() |>
  filter(loglik>max(loglik)-20) |>
  ggplot(aes(x=rho,y=loglik))+
  geom_point()



maxloglik <- max(results_profile$loglik,na.rm=TRUE)
ci.cutoff <- maxloglik-0.5*qchisq(df=1,p=0.95)
results_profile |>
  filter(is.finite(loglik)) |>
  group_by(round(rho,5)) |>
  filter(rank(-loglik)<3) |>
  ungroup() |>
  ggplot(aes(x=rho,y=loglik))+
  geom_point()+
  geom_smooth(method="loess",span=0.25)+
  geom_hline(color="red",yintercept=ci.cutoff)+
  lims(y=maxloglik-c(5,0))



write.table(file="remote_time.csv",
            rbind(time1,time2,time3))


