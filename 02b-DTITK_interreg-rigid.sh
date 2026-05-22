#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# dependency-based array submission, improved error handling

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 02b-DTITK_interreg-rigid.sh
    Perform rigid and affine inter-subject registration to an initial
    group template (bootstrapped from the IXI aging template).

    Usage: bash ./02b-DTITK_interreg-rigid.sh workdir scriptdir template subjects simul
      workdir    full path to interreg directory
      scriptdir  full path to scripts directory
      template   full path to IXI aging template (.nii.gz)
      subjects   subjects list file (inter_subjects.txt)
      simul      max simultaneous SLURM array tasks

EOF
    exit 1
}

[ _${5:-} = _ ] && Usage

workdir=${1}
scriptdir=${2}
template=${3}
subjects=${4}
simul=${5}

simulreg=$(( ${simul} * 2 ))  # more simultaneous tasks for registration stages since they are faster than warping

# source site config
#scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}
export DTITK_RIGID_FINE=${DTITK_RIGID_FINE:-0}
export DTITK_AFFINE_FINE=${DTITK_AFFINE_FINE:-0}
export DTITK_SPECIES=${DTITK_SPECIES:-human}
export DTITK_USE_QSUB=0
. ${DTITK_ROOT}/scripts/dtitk_common.sh


sep_coarse=$(echo "${lengthscale}*4" | bc -l)
sep_fine=$(echo "${lengthscale}*2" | bc -l)
smoption=EDS

if [ "${DTITK_RIGID_FINE:-0}" -eq 1 ]; then
    countMax=2
else
    countMax=1
fi

cd "${workdir}"

# validate inputs
if [ ! -f "${subjects}" ]; then
    echo "ERROR: subjects file not found: ${subjects}" >&2
    exit 1
fi
if [ ! -f "${template}" ]; then
    echo "ERROR: template not found: ${template}" >&2
    exit 1
fi

nsubj=$(wc -l < "${subjects}")
if [ "${nsubj}" -eq 0 ]; then
    echo "ERROR: subjects file is empty: ${subjects}" >&2
    exit 1
fi


# Warn if subjects file already contains _aff entries
if grep -q '_aff\.nii\.gz' "${subjects}"; then
    echo "WARNING: subjects file contains _aff entries — check 02a output" >&2
fi

echo "Running rigid+affine bootstrap registration for ${nsubj} subjects"

###############################################################################
# Bootstrap initial group template via rigid then affine registration
###############################################################################
if [ -f "${workdir}/mean_initial.nii.gz" ]; then
    echo "Bootstrapped template already exists — skipping"
    exit 0
fi

# ── Rigid registration ────────────────────────────────────────────────────────
count=1
while [ ${count} -le ${countMax} ]; do
    if [ ${count} -lt 2 ]; then
        ftol=0.01
        echo "Rigid registration pass ${count} (ftol=${ftol}, coarse)"
        jid=$(sbatch --parsable \
            --wait \
            --array="1-${nsubj}%${simulreg}" \
            --job-name=dtitk-rigid \
            --output="${workdir}/logs/reg_rigid_%A_%a.log" \
            "${scriptdir}/dti_rigid_reg_slurm.sh" "${scriptdir}" \
                "${template}" "${subjects}" "${ftol}" "" 1)
        echo "  -> rigid pass ${count} job ${jid} complete"
    else
        ftol=0.005
        echo "Rigid registration pass ${count} (ftol=${ftol}, coarse)"
        jid=$(sbatch --parsable \
            --wait \
            --array="1-${nsubj}%${simul}" \
            --job-name=dtitk-rigid \
            --output="${workdir}/logs/reg_rigid_%A_%a.log" \
            "${scriptdir}/dti_rigid_reg_slurm.sh" "${scriptdir}" \
                "${template}" "${subjects}" "${ftol}" 1 1)
        echo "  -> rigid pass ${count} job ${jid} complete"
    fi
    let count=count+1
done

# ── Affine registration ───────────────────────────────────────────────────────
count=1
while [ ${count} -le ${countMax} ]; do
    if [ ${count} -lt 2 ]; then
        ftol=0.01
        echo "Affine registration pass ${count} (ftol=${ftol})"
        jid=$(sbatch --parsable \
            --wait \
            --array="1-${nsubj}%${simul}" \
            --job-name=dtitk-aff \
            --output="${workdir}/logs/inter_affine_%A_%a.log" \
            "${scriptdir}/dti_affine_reg_slurm.sh" "${scriptdir}" \
                "${template}" "${subjects}" "${ftol}" "" 1)
        echo "  -> affine pass ${count} job ${jid} complete"
    else
        ftol=0.001
        echo "Affine registration pass ${count} (ftol=${ftol})"
        jid=$(sbatch --parsable \
            --wait \
            --array="1-${nsubj}%${simul}" \
            --job-name=dtitk-aff \
            --output="${workdir}/logs/inter_affine_%A_%a.log" \
            "${scriptdir}/dti_affine_reg_slurm.sh" "${scriptdir}" \
                "${template}" "${subjects}" "${ftol}" 1 1)
        echo "  -> affine pass ${count} job ${jid} complete"
    fi
    let count=count+1
done

# ── Compute initial group template from affine-aligned subjects ───────────────
subjects_aff=$(mktemp "${workdir}/dti_template_bootstrap_XXXXXX.txt")
trap "rm -f ${subjects_aff}" EXIT

while IFS= read -r file; do
    echo "${file}" | sed -e 's/.nii.gz/_aff.nii.gz/'
done < "${subjects}" > "${subjects_aff}"

echo "Computing initial group template (TVMean)"
TVMean -in "${subjects_aff}" -out mean_initial.nii.gz

if [ ! -f mean_initial.nii.gz ]; then
    echo "ERROR: mean_initial.nii.gz was not created" >&2
    exit 1
fi

echo
echo "Initial bootstrapped template saved as mean_initial.nii.gz"
echo "DONE"
