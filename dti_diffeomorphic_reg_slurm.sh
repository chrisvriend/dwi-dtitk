#!/bin/bash 
# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

#SBATCH --job-name=dtitk-diffeo
#SBATCH --mem-per-cpu=3G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-00:30:00
#SBATCH --nice=2000
#SBATCH --output=reg_diffeo_%A_%a.log

#disabled##SBATCH --array=1-4%4

module load dtitk/2.3.1

. ${DTITK_ROOT}/scripts/dtitk_common.sh

export DTITK_USE_QSUB=0

# inputs
template=${1}
subjects=${2}
mask=${3}
initial=${4}
no_of_iter=${5}
ftol=${6}

subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" ${subjects})

# random delay
duration=$((RANDOM % 20 + 2))
echo "INITIALIZING..."
sleep ${duration}


# Deformable alignment of a DTI volume (the subject) to a DTI template
#Usage: dti_diffeomorphic_reg template subject mask initial no_of_iter ftol
dti_diffeomorphic_reg ${template} ${subj} ${mask} ${initial} ${no_of_iter} ${ftol}
