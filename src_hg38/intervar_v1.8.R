### sort intervar output according to PVS/PS/PM/PP ###
### after InterVar and Annovar to prepare for vcfanno
## PVS = 8
## PS  = 6
## PM  = 3
## PP  = 1
## BA = -5
## BS = -3
## BP = -1
## if PVS = 0 & frameshit or stop_gain or Start_loss (?intervar), Score=+6 (equals weight of PS)
## implemented after gemini: if PVS = 0 & dbscSNV's ada > 0.8 and rf>0.5, Score=+3 (equals weight of PM)
## implemented after gemini: if PVS = 0 & |dpsi_max_tissue+dpsi_zscore| > 5, score=+3; > 2.5, score=+1 make a histogram of dpsi of WGS set and determine the cut-off
## implemented after gemini: if PVS = 0 & spliceai_rank >0.8, score=+8; >0.5, score=+6; >0.2, score=+3; >0.15, score=+1; make a histogram of splicai score and determine the cut-off
## Intervar - select one gene for each variant
## If InterVar Likely path, then at least 9 pts; if InterVar Path, then at least 12 pts.

args <- commandArgs(trailingOnly=TRUE)
# args <- c("Z:/genome/USUHS/prioritization/temp/mini__24chr.avinput.hg38_multianno.txt.intervar",
#           "Z:/genome/USUHS/prioritization/temp/mini__24chr.avinput.hg38_multianno.modified.txt", 
#           "Z:/genome/USUHS/prioritization/temp/spliceai.mini__24chr.tsv.cut",
#           "Z:/resources/HGMD/HGMDtranscript.txt", 
#           "Z:/genome/USUHS/prioritization/temp/mini__24chr.spliceai_annovar_intervar")

library(tidyverse)
#library(vroom)

intervar_file <- args[1]
annovar_file <- args[2]
spliceai_file <- args[3]
hgmd_transcript_file <- args[4]
output_file <- args[5]


# change the file name below
intervar <- read.delim(intervar_file, sep = "\t", header = TRUE, na.strings = c(".", "None", "NONE"),
                       colClasses = c("factor","integer","integer","character","character","character","character","character","character",
                                      "character","character","character","character","character","numeric","numeric","numeric","numeric",
                                      "numeric","numeric","numeric","numeric","numeric","numeric","character","character","character","numeric",
                                      "character","integer","character","character","character","character") ) %>% 
  #mutate(Ref.Gene = toupper(Ref.Gene)) %>% 
  rename(InterVar_and_Evidence = `InterVar..InterVar.and.Evidence`)
#  mutate(X.Chr = sub("^", "chr", X.Chr))

#vroom --> NA in the number columns written as 0 in the output.
# annovar <- vroom(args[2], col_types = c(Chr = "f", CHROM = "f"), na = c("", "NA", "."), guess_max = 500) %>%
#   unite("variantkey_annovar", Chr:Alt, sep = "_", remove = TRUE) %>%
#   group_by(variantkey_annovar) %>%
#   slice(which.max(QUAL))

annovar <- read_tsv(annovar_file, col_names = TRUE, na = c("NA", "", "None", "NONE", "."), col_types = cols(.default = col_character())) %>% type_convert() %>%
  mutate(Chr = as.factor(Chr), CHROM = as.factor(CHROM)) %>%
  unite("variantkey_annovar", Chr:Alt, sep = "_", remove = TRUE) %>%
  group_by(variantkey_annovar) %>%
  slice(which.max(QUAL)) %>% 
  separate_rows(Interpro_domain, sep = "\\;|\\|") %>%
  mutate(Interpro_domain = na_if(Interpro_domain, ".")) %>% 
  distinct() %>%
  mutate(Interpro_domain = paste(Interpro_domain, collapse="|")) %>%
  mutate(Interpro_domain = gsub("NA\\||\\|NA", "", Interpro_domain)) %>% 
  distinct() %>% ungroup() %>% 
  rename(f1000g2015aug_all = `1000g2015aug_all`,
         fathmm_XF_coding_score = `fathmm-XF_coding_score`,
         fathmm_XF_coding_rankscore = `fathmm-XF_coding_rankscore`,
         fathmm_XF_coding_pred = `fathmm-XF_coding_pred`,
         Eigen_PC_raw_coding = `Eigen-PC-raw_coding`, 
         Eigen_PC_raw_coding_rankscore = `Eigen-PC-raw_coding_rankscore`,
         GERPplus_NR = `GERP++_NR`,
         GERPplus_RS = `GERP++_RS`,
         GERPplus_RS_rankscore = `GERP++_RS_rankscore`)

spliceai <- read.delim(spliceai_file, sep = "\t", header = TRUE, na.strings = c("."),
                       colClasses = c("factor","integer","character","character","character","character","numeric","integer") ) %>%
  select("CHROM", "POS", "REF", "ALT", "SpliceAI", "spliceai_maxscore", "spliceai_rank")

annovar <- left_join(annovar, spliceai, by = c("CHROM", "POS", "REF", "ALT"))
rm(spliceai)
HGMD <- read_tsv(hgmd_transcript_file, col_names = TRUE, na = c("NA", "", "None", "NONE", "."), col_types = cols(.default = col_character()))
hgmdNM <- dplyr::pull(HGMD, name)

mapHGMD <- function(x){
  x = as.character(x)
  annovarAA <- as.list(strsplit(x, ",|;"))[[1]]
  if (length(annovarAA) > 1) {
    hgmdVar <- purrr::keep(annovarAA, str_extract_all(annovarAA, "NM_[[:digit:]]+") %in% hgmdNM)
    if (length(hgmdVar) == 0) {
      return(x)
    } else if (length(hgmdVar) == 1) { return(hgmdVar) }
    else { return(paste(hgmdVar, collapse = ",")) }
  } else {
    return(x)
  }
}

annovar$AAChange.refGeneWithVer <- sapply(1:nrow(annovar), function(x) {mapHGMD(annovar[x, "AAChange.refGeneWithVer"])})
annovar$GeneDetail.refGeneWithVer <- sapply(1:nrow(annovar), function(x) {mapHGMD(annovar[x, "GeneDetail.refGeneWithVer"])})

annovarS <- annovar %>% unite("refgenewithver", GeneDetail.refGeneWithVer, AAChange.refGeneWithVer, sep = ",", remove = TRUE, na.rm = TRUE)

 # mutate(refgenewithver = gsub("\\.,|,\\.|\\.,\\.", "",refgenewithver))
rm(annovar)
#pick one annotation for each variant that is of highest Priority score

intervar_for_sorting <- intervar %>%
  separate(InterVar_and_Evidence,
           c('InterVarInterpretation','PVS1','PS','PM','PP','BA1','BS','BP'),
           sep = '\\]{0,1} [A-Z]{2,3}\\d{0,1}\\=\\[{0,1}', remove = FALSE, convert = TRUE) %>%
  separate(PS, c('PS1','PS2','PS3','PS4','PS5'), sep = ',', convert = TRUE) %>%
  separate(PM, c('PM1','PM2','PM3','PM4','PM5','PM6','PM7'), sep =',', convert = TRUE) %>%
  separate(PP, c('PP1','PP2','PP3','PP4','PP5','PP6'), sep = ',', convert = TRUE) %>%
  separate(BS, c('BS1','BS2','BS3','BS4','BS5'), sep = ',', convert = TRUE) %>%
  separate(BP, c('BP1','BP2','BP3','BP4','BP5','BP6','BP7',"BP8"), sep = ',', convert = TRUE) %>%
  mutate(BP8 = str_sub(BP8, 2, 2)) %>%
  mutate(BP8 = as.integer(BP8)) %>%
  replace_na(list(Freq_gnomAD_genome_ALL=0, Freq_esp6500siv2_all=0, Freq_1000g2015aug_all=0)) %>%
  mutate(maxaf_intervar = pmax(Freq_gnomAD_genome_ALL, Freq_esp6500siv2_all, Freq_1000g2015aug_all, na.rm = TRUE)) %>%
  #  mutate(BS1 = ifelse(Freq_gnomAD_genome_ALL < 0.005 & Freq_esp6500siv2_all < 0.01, 0, BS1)) %>% #need this step, partly because intervar 2.1 included asj subpopulation in BS1, removed 5/4/21 since applied in InterVar
  #  mutate(PM2 = ifelse(maxaf_intervar < 0.00005, 1, PM2)) %>% #added 4/29/2021, allowing 1 in 10,001 genomes and 12 in 120,000 exomes, removed 5/4/21 since applied in InterVar
  mutate(Priority.Score = (PVS1*8+(PS1+PS2+PS3+PS4+PS5)*6+(PM1+PM2+PM3+PM4+PM5+PM6+PM7)*3+(PP1+PP2+PP3+PP4+PP5+PP6)-BA1*5-(BS1+BS2+BS3+BS4+BS5)*3-(BP1+BP2+BP3+BP4+BP5+BP6+BP7+BP8))) %>%
  unite("variantkey", X.Chr:Alt, sep = "_", remove = TRUE ) %>%
  group_by(variantkey) %>%
  slice(which.max(Priority.Score)) %>%
  select(variantkey, Ref.Gene, `clinvar..Clinvar`, InterVar_and_Evidence, PVS1, maxaf_intervar, Priority.Score) %>% 
  ungroup()

#InterVar 2.2.2 PVS1: "nonsense","frameshift","splic","stopgain". Thus use ExonicFunc.ensGene for ^frameshift|stopgain|stoploss|startloss|startgain above. 2019-10-24 annovar did not annotate startloss/gain in ExonicFun.Ref
#intervar 2.1.2 use the following for BS1 (0.005 cutoff) and BS2: {'1000g2015aug_all':0,'esp6500siv2_all':0,'gnomAD_genome_ALL':0,'gnomAD_genome_AFR':0,'gnomAD_genome_AMR':0,'gnomAD_genome_EAS':0,'gnomAD_genome_FIN':0,'gnomAD_genome_NFE':0,'gnomAD_genome_OTH':0,'gnomAD_genome_ASJ':0}

annovar_inter <- merge(x = annovarS, y = intervar_for_sorting,
                       by.x = c("variantkey_annovar"), by.y = c("variantkey"), all.x = TRUE,
                       sort = FALSE, suffixes = c(".annovar", ".intervar"), no.dups = TRUE,
                       incomparables = NULL) %>%
  #replace_na(list(gnomAD_exome_ALL=0)) %>%
  mutate(popmax_gnomad3e = pmax(gnomAD_genome_ALL, gnomAD_genome_AFR, gnomAD_genome_AMR, gnomAD_genome_EAS, gnomAD_genome_NFE, gnomAD_genome_SAS, na.rm = TRUE)) %>%
 # mutate(popmax_gnomad3f = pmax(gnomAD_genome_AMI, gnomAD_genome_ASJ, gnomAD_genome_FIN, gnomAD_genome_MID, gnomAD_genome_OTH, na.rm = TRUE)) %>%
  #mutate(popmax_exome = pmax(gnomAD_exome_ALL, gnomAD_exome_AFR, gnomAD_exome_AMR, gnomAD_exome_EAS, gnomAD_exome_NFE, gnomAD_exome_SAS, na.rm = TRUE ) ) %>%
  mutate(maxaf_annovar =  pmax(maxaf_intervar, popmax_gnomad3e, na.rm = TRUE)) %>%
  #mutate(truncating = case_when(PVS1 == 0 & grepl("^frameshift|stop|start", ExonicFunc.ensGene, ignore.case = TRUE) & maxaf_annovar < 0.005  ~ 8,
  #                              PVS1 == 0 & grepl("^frameshift|stop|start", ExonicFunc.ensGene, ignore.case = TRUE) & maxaf_annovar < 0.02  ~ 3,
  #                              TRUE ~ 0)) %>%
  #mutate(Priority.Score = Priority.Score + truncating) %>%
  mutate(Priority.Score = case_when(grepl("Pathogenic", InterVar_and_Evidence, ignore.case = FALSE) ~ pmax(Priority.Score, 12),
                                    grepl("Likely pathogenic", InterVar_and_Evidence, ignore.case = FALSE) ~ pmax(Priority.Score, 9),
                                    TRUE ~ Priority.Score)) %>%
  select("CHROM", "POS", "ID", "REF", "ALT", "QUAL",  "Priority.Score", Ref.Gene, "Gene.refGeneWithVer",
        "Func.refGeneWithVer", "ExonicFunc.refGeneWithVer", "refgenewithver", InterVar_and_Evidence, "PVS1", "dbscSNV_ADA_SCORE", "dbscSNV_RF_SCORE", "dpsi_max_tissue", "dpsi_zscore", "SpliceAI", "spliceai_maxscore", "spliceai_rank",
         esp6500siv2_all,`f1000g2015aug_all`,'MutationTaster_score','MutationTaster_converted_rankscore','MutationTaster_pred','MutationAssessor_score','MutationAssessor_rankscore','MutationAssessor_pred','PROVEAN_score','PROVEAN_converted_rankscore','PROVEAN_pred','MetaSVM_score','MetaSVM_rankscore','MetaSVM_pred','REVEL_score','REVEL_rankscore','MPC_score','MPC_rankscore','PrimateAI_score','PrimateAI_rankscore','PrimateAI_pred','ClinPred_score','ClinPred_rankscore','ClinPred_pred','fathmm_XF_coding_score','fathmm_XF_coding_rankscore','fathmm_XF_coding_pred','Eigen_PC_raw_coding','Eigen_PC_raw_coding_rankscore','GERPplus_NR','GERPplus_RS','GERPplus_RS_rankscore','phyloP100way_vertebrate','phyloP100way_vertebrate_rankscore','mutscore','rmsk','avsnp150','regsnp_fpr','regsnp_disease','regsnp_splicing_site','Interpro_domain',everything()) 

#'MutationTaster_score','MutationTaster_converted_rankscore','MutationTaster_pred','MutationAssessor_score','MutationAssessor_rankscore','MutationAssessor_pred','PROVEAN_score','PROVEAN_converted_rankscore','PROVEAN_pred','MetaSVM_score','MetaSVM_rankscore','MetaSVM_pred','REVEL_score','REVEL_rankscore','MPC_score','MPC_rankscore','PrimateAI_score','PrimateAI_rankscore','PrimateAI_pred','ClinPred_score','ClinPred_rankscore','ClinPred_pred','fathmm_XF_coding_score','fathmm_XF_coding_rankscore','fathmm_XF_coding_pred','Eigen_PC_raw_coding','Eigen_PC_raw_coding_rankscore','GERPplus_NR','GERPplus_RS','GERPplus_RS_rankscore','phyloP100way_vertebrate','phyloP100way_vertebrate_rankscore','mutscore','rmsk','avsnp150','regsnp_fpr','regsnp_disease','regsnp_splicing_site','LRT_score','LRT_converted_rankscore','LRT_pred','FATHMM_score','FATHMM_converted_rankscore','FATHMM_pred','VEST4_score','VEST4_rankscore','MetaLR_score','MetaLR_rankscore','MetaLR_pred','MetaRNN_score','MetaRNN_rankscore','MetaRNN_pred','M_CAP_score','M_CAP_rankscore','M_CAP_pred','MutPred_score','MutPred_rankscore','MVP_score','MVP_rankscore''DEOGEN2_score','DEOGEN2_rankscore','DEOGEN2_pred','BayesDel_addAF_score','BayesDel_addAF_rankscore','BayesDel_addAF_pred','BayesDel_noAF_score','BayesDel_noAF_rankscore','BayesDel_noAF_pred','LIST_S2_score','LIST_S2_rankscore','LIST_S2_pred','Aloft_pred','Aloft_Confidence','CADD_raw','CADD_raw_rankscore','CADD_phred','DANN_score','DANN_rankscore','fathmm_MKL_coding_score','fathmm_MKL_coding_rankscore','fathmm_MKL_coding_pred','Eigen_raw_coding','Eigen_raw_coding_rankscore','GenoCanyon_score','GenoCanyon_rankscore','integrated_fitCons_score','integrated_fitCons_rankscore','integrated_confidence_value','LINSIGHT','LINSIGHT_rankscore','phyloP30way_mammalian','phyloP30way_mammalian_rankscore','phastCons100way_vertebrate','phastCons100way_vertebrate_rankscore','phastCons30way_mammalian','phastCons30way_mammalian_rankscore','SiPhy_29way_logOdds','SiPhy_29way_logOdds_rankscore','Interpro_domain','GTEx_V8_gene','GTEx_V8_tissue'
#  mutate(across(everything(), as.character)) %>% 
#  mutate_all(list(~na_if(.,"")))

#Ref.Gene is from InterVar, Annovar calls this column as Gene.refGene
#replace na. with ".": annovar_inter[is.na(annovar_inter)] <- "."
#vroom_write(annovar_inter, args[5], na="")

write_tsv(annovar_inter, file.path('.',  output_file), na=".")

#  replace_na(list(GeneDetail.refGeneWithVer = "", AAChange.refGeneWithVer = "")) %>%
