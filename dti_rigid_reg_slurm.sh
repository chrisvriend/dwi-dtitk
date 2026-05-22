#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# input validation, fixed log naming

#SBATCH --job-name=dtitk-rigid
#SBATCH --mem=500M
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-00:10:00
#SBATCH --nice=2000
#SBATCH -o reg_rigid_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - dti_rigid_reg_slurm.sh
    SLURM array worker: performs rigid registration of one subject
    to a DTI template using dti_rigid_reg.

    Usage: sbatch --array=1-N%simul ./dti_rigid_reg_slurm.sh template subjects ftol [useInTrans] [coarse]
      template     DTI template image (.nii.gz)
      subjects     subjects list file (one subject per line)
      ftol         convergence tolerance (e.g. 0.01)
      useInTrans   use existing transform as initialisation (1) or not (empty)
      coarse       use coarse voxel spacing (1) or fine (0/empty)

EOF
    exit 1
}

[ _${3:-} = _ ] && Usage

scriptdir=${1}
template=${2}
subjects=${3}
ftol=${4}
useInTrans=${5:-}
coarse=${6:-0}

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

sep_coarse=$(echo "${lengthscale}*4" | bc -l)
sep_fine=$(echo "${lengthscale}*2" | bc -l)
smoption=EDS

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

echo "Rigid registration: ${subj} -> $(basename ${template})"
echo "  ftol=${ftol}  coarse=${coarse}  useInTrans=${useInTrans:-none}"

# Usage: dti_rigid_reg template subject SMOption xsep ysep zsep ftol [useInTrans]
if [ "${coarse}" -eq 1 ]; then
    dti_rigid_reg "${template}" "${subj}" "${smoption}" \
        "${sep_coarse}" "${sep_coarse}" "${sep_coarse}" \
        "${ftol}" ${useInTrans}
else
    dti_rigid_reg "${template}" "${subj}" "${smoption}" \
        "${sep_fine}" "${sep_fine}" "${sep_fine}" \
        "${ftol}" ${useInTrans}
fi

echo "DONE rigid registration for ${subj}"
