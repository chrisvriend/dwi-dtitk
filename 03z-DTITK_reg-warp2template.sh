#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, SLURM array conversion,
# input validation, completed incomplete logic, safer variable handling
#
# NOTE: This script is the alternative to 02b-02d + 03a when an existing
# group template is already available (templatedir is set). It registers
# each subject directly to the existing template and warps to template space.

#SBATCH --job-name=dtitk-regtemp
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:45:00
#SBATCH --nice=2000
#SBATCH -o 3z-DTITK_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 03z-DTITK_reg-warp2template.sh
    Register subjects directly to an existing group template (skipping
    template construction) and warp to template space. Used when
    templatedir is already available (alternative to stages 02b-02d + 03a).
    Run as a SLURM array job (one task per subject).

    Usage: sbatch --array=1-N%simul ./03z-DTITK_reg-warp2template.sh workdir templatedir subjects
      workdir      full path to working (head) directory
      templatedir  full path to existing group template directory
                   (must contain mean_diffeomorphic_initial6.nii.gz and mask.nii.gz)
      subjects     full path to subjects.txt (one subject per line)

EOF
    exit 1
}

[ _${3:-} = _ ] && Usage

workdir=${1}
templatedir=${2}
subjects=${3}

# source site config
scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}
export DTITK_RIGID_FINE=${DTITK_RIGID_FINE:-0}
export DTITK_AFFINE_FINE=${DTITK_AFFINE_FINE:-0}
export DTITK_SPECIES=${DTITK_SPECIES:-human}
export DTITK_USE_QSUB=0
. ${DTITK_ROOT}/scripts/dtitk_common.sh

# resolve subject from array task ID
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

# validate inputs
if [ ! -f "${templatedir}/mean_diffeomorphic_initial6.nii.gz" ]; then
    echo "ERROR: template not found: ${templatedir}/mean_diffeomorphic_initial6.nii.gz" >&2
    exit 1
fi
if [ ! -f "${templatedir}/mask.nii.gz" ]; then
    echo "ERROR: mask not found: ${templatedir}/mask.nii.gz" >&2
    exit 1
fi

warpdir=${workdir}/warps
regdir=${workdir}/interreg
mkdir -p "${warpdir}"
mkdir -p "${regdir}"

echo "----------"
echo "${subj}"
echo "----------"

template="${templatedir}/mean_diffeomorphic_initial6.nii.gz"
mask="${templatedir}/mask.nii.gz"

###############################################################################
# Collect subject scans (longitudinal or cross-sectional)
###############################################################################
# Build a per-subject scan list in the interreg directory
subj_scanlist="${regdir}/${subj}_scans.txt"
rm -f "${subj_scanlist}"

if [ -d "${workdir}/${subj}/intra" ]; then
    # longitudinal: use intra-subject template
    intra_template="${workdir}/${subj}/intra/${subj}_space-intra_template.nii.gz"
    if [ ! -f "${intra_template}" ]; then
        echo "ERROR: intra-subject template not found: ${intra_template}" >&2
        exit 1
    fi
    echo "${intra_template}" > "${subj_scanlist}"
    is_longitudinal=1
else
    # cross-sectional or single timepoint: use dtitk scan directly
    mapfile -t dtitk_scans < <(find "${workdir}/${subj}" \
        -path '*/dwi/*' -name "*desc-preproc-b${bshell}_dtitk.nii.gz" 2>/dev/null)
    if [ ${#dtitk_scans[@]} -eq 0 ]; then
        echo "ERROR: no dtitk scan found for ${subj}" >&2
        exit 1
    fi
    printf '%s\n' "${dtitk_scans[@]}" > "${subj_scanlist}"
    is_longitudinal=0
fi

###############################################################################
# Register to existing template: rigid -> affine -> diffeomorphic
###############################################################################
cd "${regdir}"

# symlink scans into interreg dir so DTITK tools can find them
while IFS= read -r scan; do
    base=$(basename "${scan}")
    [ -L "${base}" ] || ln -sf "${scan}" "${base}"
done < "${subj_scanlist}"

# rigid registration
echo "Rigid registration to existing template"
dti_rigid_sn "${template}" "${subj_scanlist}" EDS

# affine registration
echo "Affine registration to existing template"
dti_affine_sn "${template}" "${subj_scanlist}" EDS 1

# build affine scan list
subj_aff_list="${regdir}/${subj}_aff.txt"
ls -1 "${subj}"*_aff.nii.gz > "${subj_aff_list}" 2>/dev/null || {
    echo "ERROR: no affine-registered files found for ${subj}" >&2
    exit 1
}

# diffeomorphic registration
echo "Diffeomorphic registration to existing template"
dti_diffeomorphic_sn \
    "${template}" \
    "${subj_aff_list}" \
    "${mask}" 6 0.002

###############################################################################
# Warp to template space and reslice to 1mm isotropic
###############################################################################
echo "Warping to template space"

if [ "${is_longitudinal}" -eq 1 ]; then
    # longitudinal: compose intra->template warp, then compose with
    # each session's dwi->intra warp before applying
    intra_aff="${regdir}/${subj}_space-intra_template.aff"
    intra_diffeo_df="${regdir}/${subj}_space-intra_template_aff_diffeo.df.nii.gz"
    intra2template_df="${warpdir}/${subj}_intra-2-dtitktemplate.df.nii.gz"

    if [ ! -f "${intra2template_df}" ]; then
        dfRightComposeAffine \
            -aff "${intra_aff}" \
            -df  "${intra_diffeo_df}" \
            -out "${intra2template_df}"
    fi

    for sesdir in "${workdir}/${subj}"/ses*/; do
        [ -d "${sesdir}" ] || continue
        session=$(basename "${sesdir}")

        dwi2intra_df="${workdir}/${subj}/intra/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk_dwi-2-intra.df.nii.gz"
        composed_df="${warpdir}/${subj}_${session}_dwi-2-dtitktemplate.df.nii.gz"
        input_scan="${workdir}/${subj}/${session}/dwi/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz"
        output_scan="${warpdir}/${subj}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz"

        if [ ! -f "${dwi2intra_df}" ]; then
            echo "WARNING: no dwi-to-intra df for ${subj} ${session} — skipping"
            continue
        fi

        if [ ! -f "${composed_df}" ]; then
            dfComposition \
                -df1 "${dwi2intra_df}" \
                -df2 "${intra2template_df}" \
                -out "${composed_df}"
        fi

        if [ ! -f "${output_scan}" ]; then
            deformationSymTensor3DVolume \
                -in     "${input_scan}" \
                -trans  "${composed_df}" \
                -target "${template}" \
                -out    "${output_scan}" \
                -vsize 1 1 1
        else
            echo "Warped image already exists for ${subj} ${session}"
        fi
    done

else
    # cross-sectional: use dti_warp_to_template_group directly
    dti_warp_to_template_group \
        "${subj_scanlist}" \
        "${template}" 1 1 1

    # move output to warpdir with correct BIDS-style naming
    while IFS= read -r scan; do
        base=$(remove_ext "$(basename "${scan}")")
        warped_src="${regdir}/${base}_warped.nii.gz"
        warped_dst="${warpdir}/${subj}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz"
        if [ -f "${warped_src}" ] && [ ! -f "${warped_dst}" ]; then
            mv "${warped_src}" "${warped_dst}"
        fi
    done < "${subj_scanlist}"
fi

# clean up per-subject scan lists
rm -f "${subj_scanlist}" "${subj_aff_list}"

echo
echo "DONE registering and warping ${subj} to existing template"
