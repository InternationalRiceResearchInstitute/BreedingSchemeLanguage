#'Select individuals
#'
#'@param sEnv the environment that BSL functions operate in. Default is "simEnv" so use that to avoid specifying when calling functions
#'@param nSelect the number of selected individuals
#'@param popID population ID to be selected (default: When random=T, the last population. When random=F, it is the last evaluated population)
#'@param random assuming random selection or selection according to estimated value (T: random selection, F: selection for high value)
#'@param type "WithinFamily" or "Mass" (default: Mass). If Mass, all individuals are ranked against each other and the highest nSelect are taken.  If WithinFamily, individuals are ranked within paternal half-sib (if population was randomly mated) or full-sib (if population from selfFertilize or doubledHaploid) families. If random=T, then selection within families is random.
#'@param parms an optional named list or vector. Objects with those names will be created with the corresponding values. A way to pass values that are not predetermined by the script.
#'
#'@seealso \code{\link{defineSpecies}} for an example
#'
#'@return modifies the list sims in environment sEnv by selecting individuals of the specified popID with the default selection criterion and giving those individuals a new popID
#'
#'@export
select <- function(sEnv=NULL, nSelect=40, popID=NULL, random=F, type="Mass", parms=NULL){
  if(!is.null(parms)){
    for (n in 1:length(parms)){
      assign(names(parms)[n], parms[[n]])
    }
  }
  select.func <- function(bsl, nSelect, popID, random, type){
    criterion <- bsl$selCriterion$criterion
    if(is.null(popID)){
      popID <- bsl$selCriterion$popID
      if(is.null(popID)) popID <- 0
    }
    tf <- bsl$genoRec$popID %in% popID
    GIDcan <- bsl$genoRec$GID[tf]
    if (length(GIDcan) == 0) stop(paste("There are no selection candidates in the population", popID))
    if (random){
      if (type == "WithinFamily"){
        raggedRan <- function(canRan){
          if (length(canRan) == 1) return(canRan)
          nSel <- min(length(canRan), nSelect)
          return(sample(canRan, nSel))
        }
        selectedGID <- unlist(tapply(GIDcan, as.factor(bsl$genoRec$pedigree.1[GIDcan]), raggedRan))
      } else selectedGID <- sample(GIDcan, nSelect)
    } else{
      if(substr(criterion, 1, 5) == "pheno"){
        GIDcan <- intersect(GIDcan, bsl$phenoRec$phenoGID)
        if (length(GIDcan) == 0) stop(paste("There are no selection candidates in the population", popID, "with phenotypes"))
        usePheno <- subset(bsl$phenoRec, bsl$phenoRec$phenoGID %in% GIDcan)
        candValue <- by(usePheno, as.factor(usePheno$phenoGID), function(gidRec) stats::weighted.mean(x=gidRec$pValue, w=1/gidRec$error))
      }
      if(substr(criterion, 1, 4) == "pred"){
        GIDcan <- intersect(GIDcan, bsl$predRec$predGID)
        if (length(GIDcan) == 0) stop(paste("There are no selection candidates in the population", popID, "with predictions"))
        usePred <- bsl$predRec[bsl$predRec$predGID %in% GIDcan & bsl$predRec$predNo == max(bsl$predRec$predNo),]
        candValue <- usePred$predict[order(usePred$predGID)]
        GIDcan<- usePred[order(usePred$predGID),'predGID']
      }
      # Done computing the candidate values
      if (type == "WithinFamily"){
        canVal <- data.frame(GID=GIDcan, val=as.numeric(candValue))
        raggedSel <- function(canVal){
          nSel <- min(nrow(canVal), nSelect)
          return(canVal$GID[order(canVal$val, decreasing=T)[1:nSel]])
        }
        selectedGID <- unlist(by(canVal, as.factor(bsl$genoRec$pedigree.1[GIDcan]), raggedSel))
      } else{
        selectedGID <- GIDcan[order(candValue, decreasing=T)[1:nSelect]]
      }
    }#END not random selection
    popID.new <- max(bsl$genoRec$popID) + 1
    bsl$genoRec$popID[bsl$genoRec$GID %in% selectedGID] <- popID.new
    if (exists("totalCost", bsl)) bsl$totalCost <- bsl$totalCost + bsl$costs$selectCost
    return(bsl)
  } #END select.func
  
  if(is.null(sEnv)){
    if(exists("simEnv", .GlobalEnv)){
      sEnv <- get("simEnv", .GlobalEnv)
    } else{
      stop("No simulation environment was passed")
    }
  } 
  parent.env(sEnv) <- environment()
  with(sEnv, {
    if(nCore > 1){
      snowfall::sfInit(parallel=T, cpus=nCore)
      sims <- snowfall::sfLapply(sims, select.func, nSelect=nSelect, popID=popID, random=random, type=type)
      snowfall::sfStop()
    }else{
      sims <- lapply(sims, select.func, nSelect=nSelect, popID=popID, random=random, type=type)
    }
  })
}
