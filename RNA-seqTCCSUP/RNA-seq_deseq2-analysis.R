## RNA-seq analysis with DESeq2
## Stephen Turner, @genetics_blog modified by Umar Ahmad, Medical Genetics Lab

# RNA-seq data from GSE52202
# http://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=gse52202. All patients with
# ALS, 4 with C9 expansion ("exp"), 4 controls without expansion ("ctl")

# Import & pre-process ----------------------------------------------------

# Import data from featureCounts
## Previously ran at command line something like this:
## featureCounts -a genes.gtf -o counts.txt -T 12 -t exon -g gene_id GSM*.sam
countdata <- read.csv("txicounts.csv", header=TRUE, row.names=1)

# Remove first five columns (chr, start, end, strand, length)
countdata <- countdata[ ,6:ncol(countdata)]

# Remove .bam or .sam from filenames
colnames(countdata) <- gsub("\\.[sb]am$", "", colnames(countdata))

# Convert to matrix
countdata <- as.matrix(countdata)
head(countdata)

# Assign condition (first three are controls, second three are treatments)
(condition <- factor(c(rep("EJ28Pi", 3), rep("EJ28", 3))))

# Analysis with DESeq2 ----------------------------------------------------

library(DESeq2)

# Create a coldata frame and instantiate the DESeqDataSet. See ?DESeqDataSetFromMatrix
(coldata <- data.frame(row.names=colnames(countdata), condition))
dds <- DESeqDataSetFromMatrix(countData=countdata, colData=coldata, design=~condition)
dds

# Run the DESeq pipeline
dds <- DESeq(dds)

# Plot dispersions
png("qc-dispersions.png", 1000, 1000, pointsize=20)
plotDispEsts(dds, main="Dispersion plot")
dev.off()

# Regularized log transformation for clustering/heatmaps, etc
rld <- rlogTransformation(dds)
head(assay(rld))
hist(assay(rld))

# Colors for plots below
## Ugly:
## (mycols <- 1:length(unique(condition)))
## Use RColorBrewer, better
library(RColorBrewer)
(mycols <- brewer.pal(8, "Dark2")[1:length(unique(condition))])

# Sample distance heatmap
sampleDists <- as.matrix(dist(t(assay(rld))))
library(gplots)
png("qc-heatmap-samples.png", w=1000, h=1000, pointsize=20)
heatmap.2(as.matrix(sampleDists), key=T, trace="none",
          col=colorpanel(100, " light blue", "white"),
          ColSideColors=mycols[condition], RowSideColors=mycols[condition],
          margin=c(10, 10), main="Sample Distance")
dev.off()

# Principal components analysis
## Could do with built-in DESeq2 function:
## DESeq2::plotPCA(rld, intgroup="condition")
## I like mine better:
rld_pca <- function (rld, intgroup = "condition", ntop = 500, colors=NULL, legendpos="bottomleft", main="PCA Biplot", textcx=1, ...) {
  require(genefilter)
  require(calibrate)
  require(RColorBrewer)
  rv = rowVars(assay(rld))
  select = order(rv, decreasing = TRUE)[seq_len(min(ntop, length(rv)))]
  pca = prcomp(t(assay(rld)[select, ]))
  fac = factor(apply(as.data.frame(colData(rld)[, intgroup, drop = FALSE]), 1, paste, collapse = " : "))
  if (is.null(colors)) {
    if (nlevels(fac) >= 3) {
      colors = brewer.pal(nlevels(fac), "Paired")
    }   else {
      colors = c("black", "red")
    }
  }
  pc1var <- round(summary(pca)$importance[2,1]*100, digits=1)
  pc2var <- round(summary(pca)$importance[2,2]*100, digits=1)
  pc1lab <- paste0("PC1 (",as.character(pc1var),"%)")
  pc2lab <- paste0("PC1 (",as.character(pc2var),"%)")
  plot(PC2~PC1, data=as.data.frame(pca$x), bg=colors[fac], pch=21, xlab=pc1lab, ylab=pc2lab, main=main, ...)
  with(as.data.frame(pca$x), textxy(PC1, PC2, labs=rownames(as.data.frame(pca$x)), cex=textcx))
  legend(legendpos, legend=levels(fac), col=colors, pch=20)
  #     rldyplot(PC2 ~ PC1, groups = fac, data = as.data.frame(pca$rld),
  #            pch = 16, cerld = 2, aspect = "iso", col = colours, main = draw.key(key = list(rect = list(col = colours),
  #                                                                                         terldt = list(levels(fac)), rep = FALSE)))
}
png("qc-pca.png", 1000, 1000, pointsize=20)
rld_pca(rld, colors=mycols, intgroup="condition", xlim=c(-75, 35))
dev.off()


# Get differential expression results
res <- results(dds)
table(res$padj<0.05)
## Order by adjusted p-value
res <- res[order(res$padj), ]
## Generate summary of testing
summary(res)
## Merge with normalized count data
resdata <- merge(as.data.frame(res), as.data.frame(counts(dds, normalized=TRUE)), by="row.names", sort=FALSE)
names(resdata)[1] <- "Gene"
head(resdata)
## Write results
write.csv(resdata, file="diffexpr-results.csv")


## Examine plot of p-values
hist(res$pvalue, breaks=50, col="grey")

## Examine independent filtering
attr(res, "filterThreshold")
plot(attr(res,"filterNumRej"), type="b", xlab="quantiles of baseMean", ylab="number of rejections")

## MA plot
## Could do with built-in DESeq2 function:
## DESeq2::plotMA(dds, ylim=c(-1,1), cex=1)
## I like mine better:
maplot <- function (res, thresh=0.05, labelsig=TRUE, textcx=1, ...) {
  with(res, plot(baseMean, log2FoldChange, pch=20, cex=.5, log="x", ...))
  with(subset(res, padj<thresh), points(baseMean, log2FoldChange, col="red", pch=20, cex=1.5))
  if (labelsig) {
    require(calibrate)
    with(subset(res, padj<thresh), textxy(baseMean, log2FoldChange, labs=Gene, cex=textcx, col=2))
  }
}
png("diffexpr-maplot.png", 1500, 1000, pointsize=20)
maplot(resdata, main="MA Plot")
dev.off()

## Volcano plot with "significant" genes labeled
volcanoplot <- function (res, lfcthresh=2, sigthresh=0.05, main="Volcano Plot", legendpos="bottomright", labelsig=TRUE, textcx=1, ...) {
  with(res, plot(log2FoldChange, -log10(pvalue), pch=20, main=main, ...))
  with(subset(res, padj<sigthresh ), points(log2FoldChange, -log10(pvalue), pch=20, col="red", ...))
  with(subset(res, abs(log2FoldChange)>lfcthresh), points(log2FoldChange, -log10(pvalue), pch=20, col="orange", ...))
  with(subset(res, padj<sigthresh & abs(log2FoldChange)>lfcthresh), points(log2FoldChange, -log10(pvalue), pch=20, col="green", ...))
  if (labelsig) {
    require(calibrate)
    with(subset(res, padj<sigthresh & abs(log2FoldChange)>lfcthresh), textxy(log2FoldChange, -log10(pvalue), labs=Gene, cex=textcx, ...))
  }
  legend(legendpos, xjust=1, yjust=1, legend=c(paste("FDR<",sigthresh,sep=""), paste("|LogFC|>",lfcthresh,sep=""), "both"), pch=20, col=c("red","orange","green"))
}
png("diffexpr-volcanoplot.png", 1200, 1000, pointsize=20)
volcanoplot(resdata, lfcthresh=1, sigthresh=0.05, textcx=.8, xlim=c(-2.3, 2))
dev.off()

# Annotate gene symbols
library(AnnotationDbi)
library(org.Hs.eg.db)

## Add gene full name
resdata$description <- mapIds(x = org.Hs.eg.db,
                              keys = row.names(resdata),
                              column = "GENENAME",
                              keytype = "ENSEMBL",
                              multiVals = "first")

## Add gene symbol
resdata$symbol <- row.names(resdata)

# Add ENTREZ ID
results$entrez <- mapIds(x = org.Hs.eg.db,
                         keys = row.names(resdata),
                         column = "ENTREZID", 
                         keytype = "SYMBOL",
                         multiVals = "first")

## Subset for only significant genes (p < 0.05)
resdata_sig <- subset(resdata, padj < 0.05)
head(resdata_sig)

## Write normalized gene counts to a .txt file
write.table(x = as.data.frame(count(resdata), normalized = TRUE), 
            file = 'normalized_counts.txt', 
            sep = '\t', 
            quote = FALSE,
            col.names = NA)

## Write significant normalized gene counts to a .txt file
write.table(x = count(resdata[row.names(resdata_sig)], normalized = TRUE), 
            file = 'normalized_counts_significant.txt', 
            sep = '\t', 
            quote = FALSE, 
            col.names = NA)

## Write the annotated results table to a .txt file
write.table(x = as.data.frame(resdata), 
            file = "results_gene_annotated.txt", 
            sep = '\t', 
            quote = FALSE,
            col.names = NA)

## Write significant annotated results table to a .txt file
write.table(x = as.data.frame(resdata_sig), 
            file = "results_gene_annotated_significant.txt", 
            sep = '\t', 
            quote = FALSE,
            col.names = NA)


## Gene clustering 1
library("genefilter")
topVarGenes <- head(order(rowVars(assay(rld) ), decreasing = TRUE), 20)
heatmap.2(assay(rld)[ topVarGenes, ], scale = "row", trace = "none", dendrogram = "column", col = colorRampPalette( rev(brewer.pal(9, "RdBu")) ) (150))
dev.off()

## Gene clustering 2
library("genefilter")
library(pheatmap)
topVarGenes <- head(order(rowVars(assay(rld)), decreasing = TRUE), 20)
mat  <- assay(rld)[ topVarGenes, ]
mat  <- mat - rowMeans(mat)
anno <- as.data.frame(colData(rld)[, c("condition")])
row.names(anno) <- colnames(rld)
pheatmap(mat, annotation_col = anno)

## Gene clustering 3
# Load libraries
library(pheatmap) 
library(RColorBrewer) 

# Convert all samples to rlog
rld_rlog <- rlog(rld, blind = FALSE)

# Gather 20 significant genes and make matrix
mat <- assay(rld_rlog[row.names(resdata_sig)])[1:20, ]

# Choose which column variables you want to annotate the columns by.
annotation_col = data.frame(
  Group = factor(colData(rld_rlog)$Group),
  Replicate = factor(colData(rld_rlog)$Replicate),
  row.names = colData(rld_rlog)$sampleid
)

# Specify colors you want to annotate the columns by.
ann_colors = list(
  Group = c("EJ28" = "blue", "EJ28Pi" = "orange"),
  Replicate = c(E28P_R1 = "red", EJ28_R2 = "green", EJ28_R3 = "yellow",
                EJ28Pi_R1 = "Brown", EJ28Pi_R2 = "Purple", EJ28_R3 = "Pink")
  )

# Make Heatmap with pheatmap function.
# See more in documentation for customization
pheatmap(mat = mat, 
         color = colorRampPalette(brewer.pal(9, "YlOrBr"))(255), 
         scale = "row", 
         annotation_col = annotation_col, 
         annotation_colors = ann_colors, 
         show_colnames = FALSE)

