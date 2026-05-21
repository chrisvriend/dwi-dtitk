#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# --parsable job tracking, safer loops, input validation

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 02c-DTITK_interreg-affine.sh
    Perform iterative affine inter-subject registration to build a
    group affine template, then create a binary brain mask.

    Usage: bash ./02c-DTITK_interreg-affine.sh workdir scriptdir subjects Niter simul
      workdir    full path to interreg directory
      scriptdir  full path to scripts directory
      subjects   subjects list file (inter_subjects.txt)
      Niter      number of affine iterations (default: 5)
      simul      max simultaneous SLURM array tasks

EOF
    exit 1
}

[ _${5:-} = _ ] && Usage

workdir=${1}
scriptdir=${2}
subjects=${3}
Niter=${4}
simul=${5}

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
if [ ! -f "${workdir}/mean_initial.nii.gz" ]; then
    echo "ERROR: mean_initial.nii.gz not found — run 02b first" >&2
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

echo "Running iterative affine registration (${Niter} iterations) for ${nsubj} subjects"

###############################################################################
# Iterative affine registration to build group affine template
###############################################################################
log=dti_affine_population.log
echo "command: $*" | tee "${log}"
date | tee -a "${log}"
mkdir -p "${workdir}/logs"

if [ -f "mean_affine${Niter}.nii.gz" ]; then
    echo "mean_affine${Niter}.nii.gz already exists — skipping affine registration"
else
    echo "Running affine registration to initial template"
    cp "${workdir}/mean_initial.nii.gz" mean_affine0.nii.gz

    # build affine and subject_aff lists
    subjects_aff=$(echo "${subjects}" | sed -e 's/.txt/_aff.txt/')
    rm -f "${subjects_aff}" affine.txt

    while IFS= read -r subjid; do
        pref=$(remove_ext "${subjid}")
        echo "${pref}_aff.nii.gz" >> "${subjects_aff}"
        echo "${pref}.aff"        >> affine.txt
    done < "${subjects}"


    count=1
    while [ ${count} -le ${Niter} ]; do
        echo "Affine iteration ${count}/${Niter}" | tee -a "${log}"
        oldcount=$((count - 1))

        template=mean_affine${oldcount}.nii.gz

        jid=$(sbatch --parsable \
            --wait \
            --array="1-${nsubj}%${simul}" \
            --job-name=dtitk-aff \
            --output="${workdir}/logs/inter_affine_%A_%a.log" \
            "${scriptdir}/dti_affine_reg_slurm.sh" "${scriptdir}" \
                "${template}" "${subjects}" 0.01 1 1)
        echo "  -> affine iteration ${count} job ${jid} complete" | tee -a "${log}"

        affine3DShapeAverage affine.txt "mean_affine${oldcount}.nii.gz" average_inv.aff 1

        while IFS= read -r aff; do
            affine3Dtool -in "${aff}" -compose average_inv.aff -out "${aff}"
            subjid=$(echo "${aff}" | sed -e 's/.aff//')
            affineSymTensor3DVolume \
                -in "${subjid}.nii.gz" \
                -trans "${aff}" \
                -target "mean_affine${oldcount}.nii.gz" \
                -out "${subjid}_aff.nii.gz"
        done < affine.txt

        rm -f average_inv.aff

        TVMean -in "${subjects_aff}" -out "mean_affine${count}.nii.gz"
        TVtool -in "mean_affine${oldcount}.nii.gz" \
               -sm "mean_affine${count}.nii.gz" \
               -SMOption "${smoption}" | grep Similarity | tee -a "${log}"

        count=$((count + 1))
    done

    mv inter_affine*.log "${workdir}/logs/" 2>/dev/null || true
fi

###############################################################################
# Binary mask of affine template
###############################################################################
if [ -f mask.nii.gz ]; then
    echo "Binary mask already exists — skipping"
else
    echo "Creating binary mask of mean_affine${Niter} template"
    TVtool -in "mean_affine${Niter}.nii.gz" -tr
    BinaryThresholdImageFilter \
        "mean_affine${Niter}_tr.nii.gz" \
        mask.nii.gz 0.01 100 1 0

    if [ ! -f mask.nii.gz ]; then
        echo "ERROR: mask.nii.gz was not created" >&2
        exit 1
    fi
    echo "Binary mask created"
fi

echo
echo "DONE"
