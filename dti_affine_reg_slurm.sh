#!/bin/bash 
# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

#SBATCH --job-name=dtitk-aff
#SBATCH --mem-per-cpu=3G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:30:00
#SBATCH --nice=2000
#SBATCH --output=inter_affine_%A_%a.log

#disabled##SBATCH --array=1-4%4

module load dtitk/2.3.1


. ${DTITK_ROOT}/scripts/dtitk_common.sh

export DTITK_USE_QSUB=0
sep_coarse=$(echo ${lengthscale}*4 | bc -l)
sep_fine=$(echo ${lengthscale}*2 | bc -l)
smoption=EDS

subjects=${2}
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" ${subjects})

template=${1}
ftol=${3}
useInTrans=${4}
coarse=${5}


#Usage: dti_affine_reg template subject SMOption xsep ysep zsep ftol [useInTrans]
if test ${coarse} -eq 1; then 
dti_affine_reg ${template} ${subj} ${smoption} ${sep_coarse} ${sep_coarse} ${sep_coarse} ${ftol} ${useInTrans}
else 
dti_affine_reg ${template} ${subj} ${smoption} ${sep_fine} ${sep_fine} ${sep_fine} ${ftol} ${useInTrans}
fi