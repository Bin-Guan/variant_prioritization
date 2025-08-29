#!/bin/bash
#SBATCH --gres=lscratch:50
#SBATCH --cpus-per-task=16
#SBATCH --mem=32g
#SBATCH --time=8:0:0

#while read -r gene; do sbatch ~/git/variant_prioritization/geneSearch_v1.sh $gene; done < genelist.tsv
#geneList.tsv file may require Unix file EOL symbols.
#for gene in X Y Z; do bash ~/git/variant_prioritization/geneSearch_v1.sh $gene; done
#for gene in X Y Z; do sbatch ~/git/variant_prioritization/geneSearch_v1.sh $gene; done

set -e

geneName=$1
TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
YEARSTAMP=$(date "+%Y%m%d")

mkdir /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP

module load R/4.3.0 parallel
export geneName TIMESTAMP YEARSTAMP SLURM_JOB_ID SLURM_CPUS_PER_TASK
#exome
find /data/OGL/resources/GeneSearch/exome/gemini_tsv_filtered/ -name "*.tsv*" \
	| parallel -j $SLURM_CPUS_PER_TASK -k 'Rscript ~/git/variant_prioritization/dev/geneSearch_exome.R {} $geneName $(echo {/} | cut -d. -f 1) /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/{/}'

# for file in /data/OGL/resources/GeneSearch/exome/gemini_tsv_filtered/*.tsv; do
# 	Rscript ~/git/variant_prioritization/dev/geneSearch_exome.R $file $geneName $(basename $file | cut -d. -f 1) /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/$(basename $file);
# 	done
head -n 1 $(ls /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/*.filtered.tsv | head -n 1) > /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/"$geneName".tsv
for file in /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/*.filtered.tsv; do tail -n +2 $file >> /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/"$geneName".tsv; done

Rscript ~/git/variant_prioritization/dev/geneSearch_combine_sample.R /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/"$geneName".tsv "$geneName".exome.$YEARSTAMP.tsv $YEARSTAMP."$geneName".exome.xlsx
rm /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/*

#genome
find /data/OGL/resources/GeneSearch/genome/gemini_tsv_filtered/ -name "*.tsv*" \
 | parallel -j $SLURM_CPUS_PER_TASK -k 'Rscript ~/git/variant_prioritization/dev/geneSearch.R {} $geneName /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/{/}'

# for file in /data/OGL/resources/GeneSearch/genome/gemini_tsv_filtered/*.tsv; do
# 	Rscript ~/git/variant_prioritization/dev/geneSearch.R $file $geneName /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/$(basename $file);
# 	done
head -n 1 $(ls /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/*.filtered.tsv | head -n 1) > /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/"$geneName".tsv
for file in /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/*.filtered.tsv; do tail -n +2 $file >> /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/"$geneName".tsv; done

Rscript ~/git/variant_prioritization/dev/geneSearch_combine_sample.R /lscratch/$SLURM_JOB_ID/temp-$TIMESTAMP/"$geneName".tsv "$geneName".genome.$YEARSTAMP.tsv $YEARSTAMP."$geneName".genome.xlsx

#chgrp OGL "$geneName".exome.$YEARSTAMP.tsv "$geneName".exome.$YEARSTAMP.xlsx "$geneName".genome.$YEARSTAMP.tsv "$geneName".genome.$YEARSTAMP.xlsx
chgrp OGL $YEARSTAMP."$geneName".exome.xlsx $YEARSTAMP."$geneName".genome.xlsx
