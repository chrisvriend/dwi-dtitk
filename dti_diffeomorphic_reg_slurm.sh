#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# input validation, fixed log naming

#SBATCH --job-name=dtitk-diffeo
#SBATCH --mem=3G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-00:30:00
#SBATCH --nice=2000
#SBATCH --output=reg_diffeo_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - dti_diffeomorphic_reg_slurm.sh
    SLURM array worker: performs diffeomorphic registration of one
    subject to a DTI template using dti_diffeomorphic_reg.

    Usage: sbatch --array=1-N%simul ./dti_diffeomorphic_reg_slurm.sh template subjects mask initial no_of_iter ftol
      template    DTI template image (.nii.gz)
      subjects    subjects list file (one subject per line)
      mask        binary brain mask (.nii.gz)
      initial     use initial transform (1) or not (0)
      no_of_iter  number of iterations (e.g. 6)
      ftol        convergence tolerance (e.g. 0.002)

EOF
    exit 1
}

[ _${6:-} = _ ] && Usage

scriptdir=${1}
template=${2}
subjects=${3}
mask=${4}
initial=${5}
no_of_iter=${6}
ftol=${7}


# source site config
#scriptdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
export DTITK_RIGID_FINE=${DTITK_RIGID_FINE:-0}
export DTITK_AFFINE_FINE=${DTITK_AFFINE_FINE:-0}
export DTITK_SPECIES=${DTITK_SPECIES:-human}
export DTITK_USE_QSUB=0
. ${DTITK_ROOT}/scripts/dtitk_common.sh


export DTITK_USE_QSUB=0

# resolve subject from array task ID
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

# validate inputs
if [ ! -f "${template}" ]; then
    echo "ERROR: template not found: ${template}" >&2
    exit 1
fi
if [ ! -f "${subj}" ]; then
    echo "ERROR: subject file not found: ${subj}" >&2
    exit 1
fi
if [ ! -f "${mask}" ]; then
    echo "ERROR: mask not found: ${mask}" >&2
    exit 1
fi

echo "Diffeomorphic registration: ${subj} -> $(basename ${template})"
echo "  initial=${initial}  no_of_iter=${no_of_iter}  ftol=${ftol}"

# Usage: dti_diffeomorphic_reg template subject mask initial no_of_iter ftol
dti_diffeomorphic_reg \
    "${template}" \
    "${subj}" \
    "${mask}" \
    "${initial}" \
    "${no_of_iter}" \
    "${ftol}"

echo "DONE diffeomorphic registration for ${subj}"
