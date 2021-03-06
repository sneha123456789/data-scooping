rm(list=ls())

library("e1071")
library("caret")
library("Rsolnp")
library("doParallel")
library("foreach")

## Used to alert me after a long analysis is completed
library(beepr)



################################################
####    Set Directory
################################################
## TODO: Set to your own directory
setwd("C:/Users/DongWei/Documents/Projects/data-scooping")

################################################
####    Load code for Algorithms
################################################
##    Naive Bayes
source("bcw-NaiveBayes.R")

##    Spy-EM
source("bcw-SpyEM.R")

##    Rocchio-SVM
source("bcw-RocchioSVM.R")

##    Rocchio-Clu-SVM
source("bcw-RocchioClusteringSVM.R")

##    LELC
source("bcw-LELC.R")

##    Utilities
source("bcw-utils-perf.R")







################################################
####    Loading the data
################################################
bcw <- read.table("data/breast-cancer-wisconsin/breast-cancer-wisconsin.data", sep=",")
bcw.headers <- c("id", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "class")
bcw.features <- c("V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9")
names(bcw) <- bcw.headers


## bcw has non-unique patient IDs
## We will replace all IDs to ensure uniqueness
rownames(bcw) <- paste("D", 1:length(bcw$id), sep="")


## bcw$V6 has missing values
## We will replace them with the mean of V6
index <- which(bcw$V6 %in% "?")

## Convert factor to numeric to find mean
bcw$V6 <- as.numeric(levels(bcw$V6))[bcw$V6]
V6.mean <- floor(sum(bcw$V6, na.rm=TRUE) / length(bcw$V6))

## Replace missing V6 values with mean
bcw$V6[index] <- V6.mean
bcw$V6 <- as.integer(bcw$V6)
rm(V6.mean)



################################################
####    Set up parallel
################################################
## You'll have 1 core left for work ;)
parallel.numberOfCores <- detectCores() - 1
parallel.cluster <-makeCluster(parallel.numberOfCores,
                               outfile = "bcw-output.txt")
registerDoParallel(parallel.cluster)


## Note: The status messages from the script are pushed to bcw-master-out.txt
## On windows, enter this command into command prompt to tail the file:
##    powershell Get-Content bcw-master-out.txt -wait



################################################
################################################
################################################
####    Start testing here


trnPercent <- c(0.10, 0.15, 0.25, 0.35, 0.50, 0.65)


## Set up data storage for F-measure and Accuracy
bcw.fmeasure <- data.frame(NB = numeric(0),
                                 SEM = numeric(0),
                                 RocSVM = numeric(0),
                                 RocCluSvm = numeric(0),
                                 LELC = numeric(0))

bcw.accuracy <- data.frame(NB = numeric(0),
                                 SEM = numeric(0),
                                 RocSVM = numeric(0),
                                 RocCluSvm = numeric(0),
                                 LELC = numeric(0))

## Vary % of data that is labeled data
for (var.i in 1:length(trnPercent)) {

  bcw.fmeasure.row <- data.frame(NB = numeric(0),
                                 SEM = numeric(0),
                                 RocSVM = numeric(0),
                                 RocCluSvm = numeric(0),
                                 LELC = numeric(0))

  bcw.accuracy.row <- data.frame(NB = numeric(0),
                                 SEM = numeric(0),
                                 RocSVM = numeric(0),
                                 RocCluSvm = numeric(0),
                                 LELC = numeric(0))

  ## Avoid sampling bias, repeat 10 times
  #for (var.j in 1:10) {
  foreach(var.j = 1:3,
          .packages = c("e1071", "caret", "Rsolnp", "plyr")) %dopar% {

    cat("TrnPct", trnPercent[var.i], " |  Sample", var.j, "of 10\n")

    ## Splitting the data
    temp <- createDataPartition(
      bcw$class,
      times = 1,
      p = 0.6,
      list = FALSE)

    bcw.trn <- bcw[temp, ]
    bcw.tst <- bcw[-temp, ]

    ## Class "4" (malignant) is the positive set
    bcw.trn.positive <- subset(bcw.trn, class=="4")
    bcw.trn.negative <- subset(bcw.trn, class=="2")

    ## Vary % of labeled data
    temp <- createDataPartition(
      bcw.trn.positive$class,
      times = 1,
      p = trnPercent[var.i],
      list = FALSE)

    ## Set up PS and US
    bcw.PS <- bcw.trn.positive[temp, ]
    bcw.US <- bcw.trn.positive[-temp, ]
    bcw.US <- rbind(bcw.US, bcw.trn.negative)

    ## Delete variables that are never again used
    ## Prevents confusion in Global Env
    rm(bcw.trn.positive, bcw.trn.negative)


    ## Creating folds for 10-fold cross validation used later
    bcw.tst$fold <- createFolds(rownames(bcw.tst), k = 10, list = FALSE, returnTrain = FALSE)



    ################################################
    ## Build the classifiers
    cat("    Building Classifiers...\n")

    classifier.naiveBayes <- bcw.getNaiveBayesClassifier(bcw.PS, bcw.US)
    classifier.spyEm <- bcw.getSpyEmClassifier(bcw.PS, bcw.US)
    classifier.rocchioSvm <- bcw.getRocSvmClassifier(bcw.PS, bcw.US)
    classifier.rocchioCluSvm <- bcw.getRocCluSvmClassifier(bcw.PS, bcw.US)
    classifier.lelc <- bcw.getLelcClassifier(bcw.PS, bcw.US)



    ################################################
    ## Run the classifers on test data
    cat("    Predicting...\n")
    bcw.tst.NB <- bcw.tst
    bcw.tst.NB$predict <- predict(classifier.naiveBayes, bcw.tst[, bcw.features])

    bcw.tst.SEM <- bcw.tst
    bcw.tst.SEM$predict <- predict(classifier.spyEm, bcw.tst[, bcw.features])

    bcw.tst.RocSVM <- bcw.tst
    bcw.tst.RocSVM$predict <- predict(classifier.rocchioSvm, bcw.tst[, bcw.features])

    bcw.tst.RocCluSVM <- bcw.tst
    bcw.tst.RocCluSVM$predict <- predict(classifier.rocchioCluSvm, bcw.tst[, bcw.features])

    bcw.tst.LELC <- bcw.tst
    bcw.tst.LELC$predict <- predict(classifier.lelc, bcw.tst[, bcw.features])


    ################################################
    ## Calculating performance
    cat("    Calculating Performance...\n")

    ## Calculate F-measure+Accuracy for each fold (10 folds)
    bcw.tst.NB.folds.f <- numeric(0)
    bcw.tst.NB.folds.a <- numeric(0)

    bcw.tst.SEM.folds.f <- numeric(0)
    bcw.tst.SEM.folds.a <- numeric(0)

    bcw.tst.RocSVM.folds.f <- numeric(0)
    bcw.tst.RocSVM.folds.a <- numeric(0)

    bcw.tst.RocCluSVM.folds.f <- numeric(0)
    bcw.tst.RocCluSVM.folds.a <- numeric(0)

    bcw.tst.LELC.folds.f <- numeric(0)
    bcw.tst.LELC.folds.a <- numeric(0)


    for (i in 1:10) {
      bcw.tst.NB.folds.f <- c(bcw.tst.NB.folds.f, bcw.calculateFMeasure(bcw.tst.NB[bcw.tst.NB$fold == i, ]))
      bcw.tst.NB.folds.a <- c(bcw.tst.NB.folds.a, bcw.calculateAccuracy(bcw.tst.NB[bcw.tst.NB$fold == i, ]))

      bcw.tst.SEM.folds.f <- c(bcw.tst.SEM.folds.f, bcw.calculateFMeasure(bcw.tst.SEM[bcw.tst.SEM$fold == i, ]))
      bcw.tst.SEM.folds.a <- c(bcw.tst.SEM.folds.a, bcw.calculateAccuracy(bcw.tst.SEM[bcw.tst.SEM$fold == i, ]))

      bcw.tst.RocSVM.folds.f <- c(bcw.tst.RocSVM.folds.f, bcw.calculateFMeasure(bcw.tst.RocSVM[bcw.tst.NB$fold == i, ]))
      bcw.tst.RocSVM.folds.a <- c(bcw.tst.RocSVM.folds.a, bcw.calculateAccuracy(bcw.tst.RocSVM[bcw.tst.NB$fold == i, ]))

      bcw.tst.RocCluSVM.folds.f <- c(bcw.tst.RocCluSVM.folds.f, bcw.calculateFMeasure(bcw.tst.RocCluSVM[bcw.tst.RocCluSVM$fold == i, ]))
      bcw.tst.RocCluSVM.folds.a <- c(bcw.tst.RocCluSVM.folds.a, bcw.calculateAccuracy(bcw.tst.RocCluSVM[bcw.tst.RocCluSVM$fold == i, ]))

      bcw.tst.LELC.folds.f <- c(bcw.tst.LELC.folds.f, bcw.calculateFMeasure(bcw.tst.LELC[bcw.tst.LELC$fold == i, ]))
      bcw.tst.LELC.folds.a <- c(bcw.tst.LELC.folds.a, bcw.calculateAccuracy(bcw.tst.LELC[bcw.tst.LELC$fold == i, ]))
    }

    f.row <- c(mean(bcw.tst.NB.folds.f),
              mean(bcw.tst.SEM.folds.f),
              mean(bcw.tst.RocSVM.folds.f),
              mean(bcw.tst.RocCluSVM.folds.f),
              mean(bcw.tst.LELC.folds.f))

    a.row <- c(mean(bcw.tst.NB.folds.a),
              mean(bcw.tst.SEM.folds.a),
              mean(bcw.tst.RocSVM.folds.a),
              mean(bcw.tst.RocCluSVM.folds.a),
              mean(bcw.tst.LELC.folds.a))


    bcw.fmeasure.row <- rbind(bcw.fmeasure.row, f.row)
    bcw.accuracy.row <- rbind(bcw.accuracy.row, a.row)
  }

  bcw.fmeasure <- rbind(bcw.fmeasure,
                        apply(bcw.fmeasure.row, 2, mean))

  bcw.accuracy <- rbind(bcw.fmeasure,
                        apply(bcw.accuracy.row, 2, mean))
}

## Keep speakers on for beeper alert
beepr::beep(8)
stopCluster(parallel.cluster)


## Utility function
shiftRownameThenMean <- function(dataset) {

  dataset <- data.frame(dataset, row.names = NULL)
  trnPercentName <- dataset[, 1]

  dataset <- dataset[, 2:length(dataset)]
  dataset <- data.frame(rowMeans(dataset, na.rm = TRUE))

  rownames(dataset) <- trnPercentName
  colnames(dataset) <- NULL
  return(dataset)
}

NB.f <- shiftRownameThenMean(f.NB)
SEM.f <- shiftRownameThenMean(f.SEM)
RocSVM.f <- shiftRownameThenMean(f.RocSVM)
RocCluSVM.f <- shiftRownameThenMean(f.RocCluSVM)
LELC.f <- shiftRownameThenMean(f.LELC)
results.f.raw <- rbind(f.NB, f.SEM, f.RocSVM, f.RocCluSVM, f.LELC)
results.f <- cbind(NB.f, SEM.f, RocSVM.f, RocCluSVM.f, LELC.f)

NB.a <- shiftRownameThenMean(a.NB)
SEM.a <- shiftRownameThenMean(a.SEM)
RocSVM.a <- shiftRownameThenMean(a.RocSVM)
RocCluSVM.a <- shiftRownameThenMean(a.RocCluSVM)
LELC.a <- shiftRownameThenMean(a.LELC)
results.a.raw <- rbind(a.NB, a.SEM, a.RocSVM, a.RocCluSVM, a.LELC)
results.a <- cbind(NB.a, SEM.a, RocSVM.a, RocCluSVM.a, LELC.a)



## PLOT FOR F-MEASURE
xrange <- range(rownames(results.f))
yrange <- range(c(0.5, 1))
plot(xrange, yrange, type = "n", xlab = "% of training set", ylab = "F-measure")
colors <- rainbow(length(results.f))
linetype <- c(1:length(results.f))
plotchar <- seq(18,18+length(rownames(results.f)),1)

for (j in 1:length(results.f)) {
  for (i in 1:1) {
    singleCol <- results.f[,j]
    lines(rownames(results.f), singleCol, type="b", lwd=1.5,
          lty=linetype[j], col=colors[j], pch=plotchar[j])

  }
}

legend("bottomright", colnames(results.f), cex=0.8, col=colors,
       pch=plotchar, lty=linetype, title="F-measure Graph")


## PLOT FOR ACCURACY
xrange <- range(rownames(results.a))
yrange <- range(c(0.5, 1))
plot(xrange, yrange, type = "n", xlab = "% of training set", ylab = "Accuracy")
colors <- rainbow(length(results.a))
linetype <- c(1:length(results.a))
plotchar <- seq(18,18+length(rownames(results.a)),1)

for (j in 1:length(results.a)) {
  for (i in 1:1) {
    singleCol <- results.a[,j]
    lines(rownames(results.a), singleCol, type="b", lwd=1.5,
          lty=linetype[j], col=colors[j], pch=plotchar[j])

  }
}

legend("bottomright", colnames(results.a), cex=0.8, col=colors,
       pch=plotchar, lty=linetype, title="Accuracy Graph")

