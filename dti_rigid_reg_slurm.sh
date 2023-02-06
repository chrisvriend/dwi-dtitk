#!/bin/bash 

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

#SBATCH --job-name=dtitk-rigid
#SBATCH --mem-per-cpu=2G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-00:10:00
#SBATCH --nice=2000
##disabled##SBATCH --array=1-4%2
#SBATCH -o reg_rigid_%A_%a.log


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

#Usage: dti_rigid_reg template subject SMOption xsep ysep zsep ftol [useInTrans]
if test ${coarse} -eq 1; then 
dti_rigid_reg ${template} ${subj} ${smoption} ${sep_coarse} ${sep_coarse} ${sep_coarse} ${ftol} ${useInTrans}
else 
dti_rigid_reg ${template} ${subj} ${smoption} ${sep_fine} ${sep_fine} ${sep_fine} ${ftol} ${useInTrans}
fi 
