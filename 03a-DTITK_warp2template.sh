#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: converted to SLURM array (one task per subject), set -euo pipefail,
# source config, input validation, removed serial subject loop

#SBATCH --job-name=dtitk-warp2template
#SBATCH --mem-per-cpu=4G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:30:00
#SBATCH --nice=2000
#SBATCH -o 3a-DTITK_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 03a-DTITK_warp2template.sh
    Warp each subject's DTI image from native/intra-subject space to
    group template space and reslice to 1mm isotropic resolution.
    Run as a SLURM array job (one task per subject).

    Usage: sbatch --array=1-N%simul ./03a-DTITK_warp2template.sh workdir bshell subjects
      workdir   full path to working (head) directory
      bshell    b-value shell (e.g. 1000)
      subjects  full path to subjects.txt (one subject per line)

EOF
    exit 1
}

[ _${3:-} = _ ] && Usage

workdir=${1}
bshell=${2}
subjects=${3}

# source site config
scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}

# resolve subject from array task ID
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

warpdir=${workdir}/warps
regdir=${workdir}/interreg
mkdir -p "${warpdir}"

echo "----------"
echo "${subj}"
echo "----------"

# validate that the group template exists
if [ ! -f "${regdir}/mean_diffeomorphic_initial6.nii.gz" ]; then
    echo "ERROR: group template not found: ${regdir}/mean_diffeomorphic_initial6.nii.gz" >&2
    exit 1
fi

###############################################################################
# Helper function: compose warp fields and apply to DTI volume
###############################################################################
warp_to_template() {
    local scan=${1}          # input DTI scan (native space)
    local df=${2}            # composed deformation field (output path)
    local aff=${3}           # affine transform (.aff)
    local diffeo_df=${4}     # diffeomorphic deformation field
    local out=${5}           # output warped image

    # compose affine + diffeomorphic warp if not already done
    if [ ! -f "${df}" ]; then
        dfRightComposeAffine \
            -aff "${aff}" \
            -df  "${diffeo_df}" \
            -out "${df}"
    else
        echo "Composed warp already exists: $(basename ${df})"
    fi

    # apply warp and reslice to 1mm isotropic
    if [ ! -f "${out}" ]; then
        deformationSymTensor3DVolume \
            -in     "${scan}" \
            -trans  "${df}" \
            -target "${regdir}/mean_diffeomorphic_initial6.nii.gz" \
            -out    "${out}" \
            -vsize 1 1 1
    else
        echo "Warped image already exists: $(basename ${out})"
    fi
}

###############################################################################
# Longitudinal subjects
###############################################################################
if [ -f "${regdir}/long_subjects.txt" ]; then

    # check if this subject is in the longitudinal list
    subj_intra_template="${subj}_space-intra_template.nii.gz"

    if grep -q "${subj_intra_template}" "${regdir}/long_subjects.txt" 2>/dev/null; then
        echo "Processing as LONGITUDINAL subject"

        # compose intra-to-template warp
        intra2template_df="${warpdir}/${subj}_intra-2-dtitktemplate.df.nii.gz"
        if [ ! -f "${intra2template_df}" ]; then
            dfRightComposeAffine \
                -aff "${regdir}/${subj}_space-intra_template.aff" \
                -df  "${regdir}/${subj}_space-intra_template_aff_diffeo.df.nii.gz" \
                -out "${intra2template_df}"
        else
            echo "Intra-to-template warp already exists"
        fi

        if [ ! -f "${intra2template_df}" ]; then
            echo "ERROR: ${subj} has no intra-to-template deformation field" >&2
            exit 1
        fi

        # process each session
        for sesdir in "${workdir}/${subj}"/ses*/; do
            [ -d "${sesdir}" ] || continue
            session=$(basename "${sesdir}")

            dwi2intra_df="${workdir}/${subj}/intra/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk_dwi-2-intra.df.nii.gz"
            composed_df="${warpdir}/${subj}_${session}_dwi-2-dtitktemplate.df.nii.gz"
            input_scan="${workdir}/${subj}/${session}/dwi/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz"
            output_scan="${warpdir}/${subj}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz"

            if [ ! -f "${dwi2intra_df}" ]; then
                echo "WARNING: ${subj} ${session} has no dwi-to-intra deformation field — skipping"
                continue
            fi

            # compose dwi->intra + intra->template
            if [ ! -f "${composed_df}" ]; then
                dfComposition \
                    -df1 "${dwi2intra_df}" \
                    -df2 "${intra2template_df}" \
                    -out "${composed_df}"
            else
                echo "Composed warp already exists for ${subj} ${session}"
            fi

            # warp to template
            if [ ! -f "${output_scan}" ]; then
                deformationSymTensor3DVolume \
                    -in     "${input_scan}" \
                    -trans  "${composed_df}" \
                    -target "${regdir}/mean_diffeomorphic_initial6.nii.gz" \
                    -out    "${output_scan}" \
                    -vsize 1 1 1
            else
                echo "Warped image already exists for ${subj} ${session}"
            fi
        done

    fi
fi

###############################################################################
# Cross-sectional subjects (single timepoint in longitudinal dataset)
###############################################################################
if [ -f "${regdir}/cross_subjects.txt" ]; then
    while IFS= read -r scan; do
        subj_session=${scan%_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz*}
        # only process if this scan belongs to our subject
        if [[ "${subj_session}" != ${subj}* ]]; then
            continue
        fi

        base=$(remove_ext "${scan}")
        s=${subj_session%_ses-*}
        session=${subj_session#${s}_}

        composed_df="${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz"
        output_scan="${warpdir}/${s}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz"
        input_scan="${workdir}/${s}/${session}/dwi/${subj_session}_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz"

        warp_to_template \
            "${input_scan}" \
            "${composed_df}" \
            "${regdir}/${base}.aff" \
            "${regdir}/${base}_aff_diffeo.df.nii.gz" \
            "${output_scan}"

    done < "${regdir}/cross_subjects.txt"
fi

###############################################################################
# Pure cross-sectional dataset (no sessions, no long_subjects.txt)
###############################################################################
if [ ! -f "${regdir}/long_subjects.txt" ] && [ -f "${regdir}/inter_subjects.txt" ]; then

    while IFS= read -r scan; do
        subj_from_scan=${scan%_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz*}
        # only process if this scan belongs to our subject
        if [ "${subj_from_scan}" != "${subj}" ]; then
            continue
        fi

        base=$(remove_ext "${scan}")
        composed_df="${warpdir}/${subj}_dwi-2-dtitktemplate.df.nii.gz"
        output_scan="${warpdir}/${subj}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz"
        input_scan="${regdir}/${scan}"

        warp_to_template \
            "${input_scan}" \
            "${composed_df}" \
            "${regdir}/${base}.aff" \
            "${regdir}/${base}_aff_diffeo.df.nii.gz" \
            "${output_scan}"

    done < "${regdir}/inter_subjects.txt"
fi

echo
echo "DONE warping ${subj} to group template"
