#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# safer loops, input validation, output existence checks,
# fixed garbled rm line, scriptdir from env with fallback

#SBATCH --job-name=dtitk-dtifit
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-1:15:00
#SBATCH --nice=2000
#SBATCH -o 1-DTITK_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 01a-DTITK_fit+intrareg.sh
    Per-subject SLURM array worker:
      1. Splits DWI to b${bshell} shell
      2. Creates brain mask (synthstrip)
      3. Bias corrects (ANTs)
      4. Runs dtifit
      5. Converts to DTI-TK format (fsl_to_dtitk)
      6. Performs intra-subject registration (longitudinal only)

    Usage: sbatch --array=1-N%simul ./01a-DTITK_fit+intrareg.sh preprocdir workdir subjects
      preprocdir  full path to preprocessed DWI derivatives
      workdir     full path to working (head) directory
      subjects    full path to subjects.txt (one subject per line)

EOF
    exit 1
}

[ _${3:-} = _ ] && Usage

preprocdir=${1}
workdir=${2}
subjects=${3}

# use scriptdir exported from wrapper; fall back to BASH_SOURCE for interactive use
scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load Anaconda3/${ANACONDA_VERSION}
conda activate "${MRTRIX_ENV}"
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}
module load ANTs/${ANTS_VERSION}
export DTITK_RIGID_FINE=${DTITK_RIGID_FINE:-0}
export DTITK_AFFINE_FINE=${DTITK_AFFINE_FINE:-0}
export DTITK_SPECIES=${DTITK_SPECIES:-human}
. ${DTITK_ROOT}/scripts/dtitk_common.sh

export DTITK_USE_QSUB=0
Niter=5
threads=${SLURM_CPUS_PER_TASK:-1}

# resolve subject from array task ID
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

QCdir=${workdir}/QC
mkdir -p "${QCdir}"

echo "-------"
echo "${subj}"
echo "-------"

###############################################################################
# Per-session: shell split, brain mask, bias correction, dtifit, fsl_to_dtitk
###############################################################################
for dwidir in "${preprocdir}/${subj}/"{,ses*/}dwi; do
    [ -d "${dwidir}" ] || continue

    sessiondir=$(dirname "${dwidir}")
    session=$(echo "${sessiondir}" | grep -oP "(?<=${subj}/).*")

    if [ -z "${session}" ]; then
        sessionpath=/
        sessionfile=_
    else
        sessionpath=/${session}/
        sessionfile=_${session}_
    fi

    mkdir -p "${workdir}/${subj}${sessionpath}"
    rsync -a "${preprocdir}/${subj}${sessionpath}dwi" "${workdir}/${subj}${sessionpath}"
    mkdir -p "${workdir}/${subj}${sessionpath}figures"

    cd "${workdir}/${subj}${sessionpath}dwi"

    # ── Brain mask ────────────────────────────────────────────────────────────
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz" ]; then
        echo "Creating brain mask for ${subj}${sessionfile}"

        dwiextract -nthreads "${threads}" \
            "${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz" - -bzero \
            -fslgrad "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec" \
                     "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval" \
            | mrmath - mean \
                "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" -axis 3 -force

        apptainer run --cleanenv "${SYNTHSTRIP_SIF}" \
            -i "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" \
            -o "${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz" \
            --mask "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz"

        # fix header after synthstrip
        fslcpgeom \
            "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" \
            "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz"

        slicer \
            "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" \
            "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz" \
            -a "${workdir}/${subj}${sessionpath}figures/${subj}${sessionfile}maskQC.png"
    fi

    # ── Shell split + bias correction ─────────────────────────────────────────
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz" ]; then
        echo "Shell split + bias correction for ${subj}${sessionfile}"

        mrconvert \
            "${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz" \
            -fslgrad \
                "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec" \
                "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval" \
            "${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif"

        dwibiascorrect ants \
            "${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif" \
            "${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif" \
            -nthreads "${threads}" \
            -bias "${subj}${sessionfile}space-dwi_desc-biasest_dwi.mif" \
            -scratch "${workdir}/${subj}${sessionpath}tempbiascorrect"

        dwiextract \
            "${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif" \
            b0b${bshell}.mif -shells 0,${bshell}

        mrconvert b0b${bshell}.mif \
            "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz" \
            -export_grad_fsl b${bshell}.bvec b${bshell}.bval -force

        rm -f b0b${bshell}.mif \
              "${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif" \
              "${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif"
    fi

    # ── dtifit ────────────────────────────────────────────────────────────────
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_FA.nii.gz" ]; then
        echo "dtifit on b${bshell} shell for ${subj}${sessionfile}"
        dtifit \
            -k "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz" \
            -m "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz" \
            -r b${bshell}.bvec -b b${bshell}.bval \
            -o "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}" --sse
        rm -f b${bshell}.bvec b${bshell}.bval
    fi

    # ── fsl_to_dtitk ─────────────────────────────────────────────────────────
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" ]; then
        echo "fsl_to_dtitk for ${subj}${sessionfile}"
        fsl_to_dtitk "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}"
        rm -f *nonSPD.nii.gz *norm.nii.gz *norm_non_outliers.nii.gz
    fi

    echo
    echo "Done with timepoint = ${session:-cross-sectional}"
    echo

    # clean up intermediate files
    rm -f \
        "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_??.nii.gz" \
        "${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz" \
        "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec" \
        "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval" \
        "${subj}${sessionfile}space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz"

    # symlink into intra dir for registration step
    mkdir -p "${workdir}/${subj}/intra"
    ln -sf \
        "..${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" \
        "${workdir}/${subj}/intra/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz"

done

echo
echo "DONE converting data to DTI-TK format"
echo

###############################################################################
# Intra-subject registration (longitudinal only — skip if single timepoint)
###############################################################################
cd "${workdir}/${subj}/intra"

ls -1 *desc-preproc-b${bshell}_dtitk.nii.gz > "${subj}.txt"
ntimepoints=$(wc -l < "${subj}.txt")

if [ "${ntimepoints}" -le 1 ]; then
    echo "${subj} has only a single timepoint — skipping intra-subject registration"
    rm -rf "${workdir}/${subj}/intra"
    echo
    echo "DONE — ${subj}"
    exit 0
fi

echo "Continuing with intra-subject registration (${ntimepoints} timepoints)"
echo

# ── Bootstrap initial intra-subject template ─────────────────────────────────
if [ ! -f "${subj}_mean_initial.nii.gz" ]; then
    echo "Running initial template construction"
    dti_template_bootstrap \
        "${IXITEMPLATE}/ixi_aging_template.nii.gz" \
        "${subj}.txt" EDS
    mv mean_initial.nii.gz "${subj}_mean_initial.nii.gz"
else
    echo "Template bootstrapping already done"
fi

# ── Affine registration to intra-subject template ────────────────────────────
if [ ! -f "${subj}_mean_affine${Niter}.nii.gz" ]; then
    echo "Running affine registration to initial template"
    dti_affine_population \
        "${subj}_mean_initial.nii.gz" \
        "${subj}.txt" EDS "${Niter}"
    mv "mean_affine${Niter}.nii.gz" "${subj}_mean_affine${Niter}.nii.gz"
else
    echo "Affine registration already done"
fi

# ── Binary mask of affine template ───────────────────────────────────────────
if [ ! -f "${subj}_mask.nii.gz" ]; then
    echo "Making binary mask"
    TVtool -in "${subj}_mean_affine${Niter}.nii.gz" -tr
    BinaryThresholdImageFilter \
        "${subj}_mean_affine${Niter}_tr.nii.gz" \
        "${subj}_mask.nii.gz" 0.01 100 1 0
else
    echo "Binary mask already exists"
fi

# ── Diffeomorphic registration ───────────────────────────────────────────────
if [ ! -f "${subj}_diffeomorphic.nii.gz" ]; then
    echo "Running diffeomorphic registration"

    # build affine list
    ls -1 *_aff.nii.gz > "${subj}_aff.txt"

    dti_diffeomorphic_population \
        "${subj}_mean_affine${Niter}.nii.gz" \
        "${subj}_aff.txt" \
        "${subj}_mask.nii.gz" 0.002

    mv mean_diffeomorphic_initial6.nii.gz "${subj}_diffeomorphic.nii.gz"
else
    echo "Diffeomorphic registration already done"
fi

# ── Compose warp fields and warp each timepoint to intra-subject template ────
echo "Composing warp fields and warping timepoints to intra-subject template"

while IFS= read -r dtitkscan; do
    dtitkbase=$(remove_ext "${dtitkscan}")

    # extract sub-XXX_ses-YY from filename
    if [[ "${dtitkbase}" =~ (sub-[^_]+(_ses-[^_]+)?) ]]; then
        subj_session=${BASH_REMATCH[1]}
    else
        echo "ERROR: cannot determine subject/session from ${dtitkbase}" >&2
        exit 1
    fi

    # compose affine + diffeomorphic warp
    if [ ! -f "${dtitkbase}_dwi-2-intra.df.nii.gz" ]; then
        dfRightComposeAffine \
            -aff "${dtitkbase}.aff" \
            -df  "${dtitkbase}_aff_diffeo.df.nii.gz" \
            -out "${dtitkbase}_dwi-2-intra.df.nii.gz"
    else
        echo "Warp already composed for ${subj_session}"
    fi

    # warp timepoint to intra-subject template
    if [ ! -f "${subj_session}_space-intra_dtitk.nii.gz" ]; then
        echo "Warping ${subj_session} to intra-subject template"
        deformationSymTensor3DVolume \
            -in     "${dtitkscan}" \
            -trans  "${dtitkbase}_dwi-2-intra.df.nii.gz" \
            -target "${subj}_mean_initial.nii.gz" \
            -out    "${subj_session}_space-intra_dtitk.nii.gz"
    else
        echo "Warped image already exists for ${subj_session}"
    fi

done < "${subj}.txt"

# ── Mean image across timepoints in intra-subject template space ──────────────
if [ ! -f "${subj}_space-intra_template.nii.gz" ]; then
    echo
    echo "Creating mean image across timepoints in intra-subject template space"
    ls -1 *_space-intra_dtitk.nii.gz > "${subj}_intra_reg_volumes.txt"
    TVMean \
        -in  "${subj}_intra_reg_volumes.txt" \
        -out "${subj}_space-intra_template.nii.gz"
else
    echo "Mean intra-subject template already exists"
fi

# ── Clean up ─────────────────────────────────────────────────────────────────
if [ -f "${subj}_space-intra_template.nii.gz" ]; then
    rm -f mean_affine*.nii.gz \
          mean_diffeomorphic_initial*.nii.gz \
          "${subj}_mean_affine${Niter}_tr.nii.gz" \
          "${subj}_intra_reg_volumes.txt"
fi

echo
echo "DONE with intra-subject registration for ${subj}"
