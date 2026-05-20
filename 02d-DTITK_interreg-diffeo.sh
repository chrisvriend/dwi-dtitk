#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# --parsable job tracking, safer loops, input validation, trap cleanup

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 02d-DTITK_interreg-diffeo.sh
    Perform iterative diffeomorphic inter-subject registration to build
    the final group diffeomorphic template (6 iterations).
    Also generates QC overlay PNGs for each subject.

    Usage: bash ./02d-DTITK_interreg-diffeo.sh workdir scriptdir template mask subjects simul
      workdir    full path to interreg directory
      scriptdir  full path to scripts directory
      template   affine template (e.g. mean_affine5.nii.gz)
      mask       binary brain mask (mask.nii.gz)
      subjects   affine subjects list (inter_subjects_aff.txt)
      simul      max simultaneous SLURM array tasks

EOF
    exit 1
}

[ _${6:-} = _ ] && Usage

workdir=${1}
scriptdir=${2}
template=${3}
mask=${4}
subjects=${5}
simul=${6}

# source site config
scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}
export DTITK_RIGID_FINE=${DTITK_RIGID_FINE:-0}
. ${DTITK_ROOT}/scripts/dtitk_common.sh

export DTITK_USE_QSUB=0
ftol=0.002   # default diffeomorphic tolerance

mkdir -p "${workdir}/QC"
mkdir -p "${workdir}/logs"
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
if [ ! -f "${mask}" ]; then
    echo "ERROR: mask not found: ${mask}" >&2
    exit 1
fi

nsubj=$(wc -l < "${subjects}")
if [ "${nsubj}" -eq 0 ]; then
    echo "ERROR: subjects file is empty: ${subjects}" >&2
    exit 1
fi

echo "Running diffeomorphic registration (6 iterations) for ${nsubj} subjects"

###############################################################################
# Iterative diffeomorphic registration (6 levels)
###############################################################################
if [ -f "${workdir}/mean_diffeomorphic_initial6.nii.gz" ]; then
    echo "mean_diffeomorphic_initial6.nii.gz already exists — skipping diffeomorphic registration"
else
    cp "${template}" mean_diffeomorphic_initial0.nii.gz

    # build diffeo and df lists
    subjects_diffeo=$(echo "${subjects}" | sed -e 's/.txt/_diffeo.txt/')
    rm -f "${subjects_diffeo}" diffeo.txt

    while IFS= read -r subj; do
        pref=$(remove_ext "${subj}")
        echo "${pref}_diffeo.nii.gz"    >> "${subjects_diffeo}"
        echo "${pref}_diffeo.df.nii.gz" >> diffeo.txt
    done < "${subjects}"

    template_current=mean_diffeomorphic_initial.nii.gz
    count=1
    while [ ${count} -le 6 ]; do
        echo "Diffeomorphic iteration ${count}/6"
        let oldcount=count-1
        ln -sf "mean_diffeomorphic_initial${oldcount}.nii.gz" "${template_current}"

        jid=$(sbatch --parsable \
            --wait \
            --array="1-${nsubj}%${simul}" \
            --job-name=dtitk-diffeo \
            --output="${workdir}/logs/reg_diffeo_%A_%a.log" \
            "${scriptdir}/dti_diffeomorphic_reg_slurm.sh" \
                "${template_current}" "${subjects}" "${mask}" 1 ${count} "${ftol}")
        echo "  -> diffeomorphic iteration ${count} job ${jid} complete"

        echo "Updating template"
        template_new=mean_diffeomorphic_initial${count}.nii.gz
        TVMean  -in "${subjects_diffeo}" -out "${template_new}"
        VVMean  -in diffeo.txt           -out mean_df.nii.gz
        dfToInverse -in mean_df.nii.gz
        deformationSymTensor3DVolume \
            -in    "${template_new}" \
            -out   "${template_new}" \
            -trans mean_df_inv.nii.gz

        rm -f "${template_current}" mean_df.nii.gz mean_df_inv.nii.gz
        let count=count+1
    done

    if [ ! -f mean_diffeomorphic_initial6.nii.gz ]; then
        echo "ERROR: mean_diffeomorphic_initial6.nii.gz was not created" >&2
        exit 1
    fi
    echo "Final diffeomorphic template: mean_diffeomorphic_initial6.nii.gz"
fi

###############################################################################
# QC: overlay each subject's diffeo image on the group template
###############################################################################
echo
echo "Generating QC overlay PNGs"

fslroi mean_diffeomorphic_initial6.nii.gz \
       mean_diffeomorphic_initial6_vslicer.nii.gz 0 1

for subj in $(ls *_aff_diffeo.nii.gz 2>/dev/null); do
    base=${subj%_aff_diffeo.nii.gz}_diffeo
    fslroi "${subj}" diffeo_tmp.nii.gz 0 1
    slicer mean_diffeomorphic_initial6_vslicer.nii.gz \
           diffeo_tmp.nii.gz \
           -a "${workdir}/QC/${base}_overlay.png"
    rm -f diffeo_tmp.nii.gz
done

rm -f mean_diffeomorphic_initial6_vslicer.nii.gz

echo
echo "DONE"
