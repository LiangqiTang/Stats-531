## check to see that the version of R is sufficiently recent
minRversion <- "4.3.1"
rv <- getRversion()
if (rv < minRversion)
  stop("R version >= ",minRversion," is required",call.=FALSE)

## get list of packages to install
pkglist <- scan(
  what=character(0),
  text="
coda
colorspace
cowplot
deSolve
foreach
iterators
doFuture
doRNG
gridExtra
gtable
knitr
mvtnorm
nloptr
scales
subplex
tidyverse
tidyr
magrittr
pomp
circumstance
"
)

lib <- Sys.getenv("R_LIBS_USER")

inst_pkg <- function (pkglist, lib = Sys.getenv("R_LIBS_USER")) {
  op <- options(warn=2)

  pkglist <- setdiff(pkglist,rownames(installed.packages()))

  if (length(pkglist)>0) {
    cat("trying to install packages in user directory...\n")
    dir.create(lib,recursive=TRUE,showWarnings=FALSE)
    res <- try(install.packages(pkglist,lib=lib))
    if (inherits(res,"try-error")) {
      stop("cannot install to ",lib,call.=FALSE)
    }
  }

  options(op)
  invisible(NULL)
}

inst_pkg(pkglist,lib=lib)
cat("first set of packages installed successfully to user directory\n\t(",lib,")!\n")
