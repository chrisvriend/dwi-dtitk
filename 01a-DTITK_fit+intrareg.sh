#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: sourced config, trap cleanup, removed sleep,
# selective rsync, set -euo pipefail

#SBATCH --job-name=dtitk-fit
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
    DWI split to b1000, DTITK conversion, intra-subject registration.

    Usage: sbatch --array=1-N%simul ./01a-DTITK_fit+intrareg.sh preprocdir workdir subjects
      preprocdir  full path to preprocessed DWI output
      workdir     full path to working directory
      subjects    full path to subjects.txt (one subject per line)
EOF
    exit 1
}

[ _${3:-} = _ ] && Usage

preprocdir=${1}
workdir=${2}
subjects=${3}
threads=${SLURM_CPUS_PER_TASK}

# source site config (paths, module versions)
scriptdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${scriptdir}/config.sh"

# resolve subject from array task ID - no sleep needed with dependency chains
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

QCdir=${workdir}/QC
mkdir -p "${QCdir}"

# load software from config variables
module load Anaconda3/${ANACONDA_VERSION}
conda activate "${PYTHON_ENV}"
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}
module load ANTs/${ANTS_VERSION}

Niter=5
export DTITK_USE_QSUB=0

echo "-------"
echo "${subj}"
echo "-------"

###############################################################################
# Per-session: brain mask, bias correction, shell split, dtifit, fsl_to_dtitk
###############################################################################
for dwidir in ${preprocdir}/${subj}/{,ses*/}dwi; do
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

    # selective rsync: only required input files, avoids duplicating full DWI data
    mkdir -p "${workdir}/${subj}${sessionpath}dwi"
    rsync -a \
        --include="*preproc_dwi.nii.gz" \
        --include="*preproc_dwi.bvec" \
        --include="*preproc_dwi.bval" \
        --include="*noddi.nii.gz" \
        --exclude="*" \
        "${preprocdir}/${subj}${sessionpath}dwi/" \
        "${workdir}/${subj}${sessionpath}dwi/"

    mkdir -p "${workdir}/${subj}${sessionpath}figures"
    cd "${workdir}/${subj}${sessionpath}dwi"

    # skip if final output already exists
    if [ -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" ]; then
        echo "DTITK file already exists for ${session:-cross-sectional} -- skipping"
        mkdir -p "${workdir}/${subj}/intra"
        ln -sf "../${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" \
            "${workdir}/${subj}/intra/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" \
            2>/dev/null || true
        continue
    fi

    # Brain mask
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz" ]; then
        echo "Creating brain mask"
        dwiextract -nthreads ${threads} \
            "${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz" - -bzero \
            -fslgrad "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec" \
                     "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval" \
            | mrmath - mean "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" -axis 3 -force

        apptainer run --cleanenv "${SYNTHSTRIP}" \
            -i "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" \
            -o "${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz" \
            --mask "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz"

        fslcpgeom "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" \
                  "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz"

        slicer "${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz" \
               "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz" \
               -a "${workdir}/${subj}${sessionpath}figures/${subj}${sessionfile}maskQC.png"
    fi

    # Bias correction - trap ensures scratch is cleaned on failure/cancel
    SCRATCH_DIR="${workdir}/${subj}${sessionpath}tempbiascorrect"
    trap "rm -rf ${SCRATCH_DIR}" EXIT

    mrconvert "${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz" \
        -fslgrad "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec" \
                 "${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval" \
        "${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif"

    dwibiascorrect ants \
        "${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif" \
        "${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif" \
        -nthreads ${threads} \
        -bias "${subj}${sessionfile}space-dwi_desc-biasest_dwi.mif" \
        -scratch "${SCRATCH_DIR}"

    # Shell split
    dwiextract "${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif" \
        b0b${bshell}.mif -shells 0,${bshell}
    mrconvert b0b${bshell}.mif \
        "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz" \
        -export_grad_fsl b${bshell}.bvec b${bshell}.bval -force

    # dtifit
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_FA.nii.gz" ]; then
        echo "Running dtifit on b${bshell} shell"
        dtifit \
            -k "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz" \
            -m "${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz" \
            -r b${bshell}.bvec -b b${bshell}.bval \
            -o "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}" --sse
        rm -f b${bshell}.bv* b0b${bshell}.mif
    fi

    # fsl_to_dtitk
    if [ ! -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" ]; then
        fsl_to_dtitk "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}"
        rm -f *nonSPD.nii.gz *norm.nii.gz *norm_non_outliers.nii.gz
    fi

    echo; echo "Done with timepoint = ${session:-cross-sectional}"; echo

    rm -f "${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_??.nii.gz" \
          *.mif \
          "${subj}${sessionfile}space-dwi_desc-preproc_dwi."* \
          "${subj}${sessionfile}space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz"

    mkdir -p "${workdir}/${subj}/intra"
    ln -sf "../${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" \
        "${workdir}/${subj}/intra/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz" \
        2>/dev/null || true
done

echo; echo "DONE converting data to DTITK format"; echo

###############################################################################
# Intra-subject registration (only if >1 timepoint)
###############################################################################
cd "${workdir}/${subj}/intra"
ls -1 *desc-preproc-b${bshell}_dtitk.nii.gz > "${subj}.txt"

if [ "$(wc -l < "${subj}.txt")" -le 1 ]; then
    echo "${subj} has only a single timepoint -- skipping intra-subject registration"
    rm -rf "${workdir}/${subj}/intra"
    exit 0
fi

echo; echo "Continuing with intra-subject registration"; echo

if [ ! -f "${subj}_mean_initial.nii.gz" ]; then
    dti_template_bootstrap "${IXITEMPLATE}" "${subj}.txt" EDS
    mv mean_initial.nii.gz "${subj}_mean_initial.nii.gz"
fi

if [ ! -f "${subj}_mean_affine${Niter}.nii.gz" ]; then
    dti_affine_population "${subj}_mean_initial.nii.gz" "${subj}.txt" EDS ${Niter}
    mv mean_affine${Niter}.nii.gz "${subj}_mean_affine${Niter}.nii.gz"
fi

if [ ! -f "${subj}_mask.nii.gz" ]; then
    TVtool -in "${subj}_mean_affine${Niter}.nii.gz" -tr
    BinaryThresholdImageFilter \
        "${subj}_mean_affine${Niter}_tr.nii.gz" "${subj}_mask.nii.gz" 0.01 100 1 0
fi

if [ ! -f "${subj}_diffeomorphic.nii.gz" ]; then
    dti_diffeomorphic_population \
        "${subj}_mean_affine${Niter}.nii.gz" "${subj}_aff.txt" "${subj}_mask.nii.gz" 0.002
    mv mean_diffeomorphic_initial6.nii.gz "${subj}_diffeomorphic.nii.gz"
fi

echo "Making non-linear transform for each timepoint"
for dtitkscan in $(cat "${subj}.txt"); do
    dtitkbase=$(remove_ext "${dtitkscan}")
    if [[ ${dtitkbase} =~ sub-([[:alnum:]_-]+)_space ]]; then
        subj_session=${BASH_REMATCH[1]}
    else
        echo "ERROR: cannot determine subjID or session from ${dtitkbase}" >&2
        continue
    fi
    echo "${subj_session}"

    if [ ! -f "${dtitkbase}_dwi-2-intra.df.nii.gz" ]; then
        dfRightComposeAffine \
            -aff "${dtitkbase}.aff" \
            -df  "${dtitkbase}_aff_diffeo.df.nii.gz" \
            -out "${dtitkbase}_dwi-2-intra.df.nii.gz"
    fi

    if [ ! -f "sub-${subj_session}_space-intra_dtitk.nii.gz" ]; then
        deformationSymTensor3DVolume \
            -in     "${dtitkscan}" \
            -trans  "${dtitkbase}_dwi-2-intra.df.nii.gz" \
            -target "${subj}_mean_initial.nii.gz" \
            -out    "sub-${subj_session}_space-intra_dtitk.nii.gz"
    fi
done

if [ ! -f "${subj}_space-intra_template.nii.gz" ]; then
    ls -1 *_space-intra_dtitk.nii.gz > "${subj}_intra_reg_volumes.txt"
    TVMean -in "${subj}_intra_reg_volumes.txt" -out "${subj}_space-intra_template.nii.gz"
fi

if [ -f "${subj}_space-intra_template.nii.gz" ]; then
    rm -f mean_affine*.nii.gz mean_diffeomorphic_initial*.nii.gz \
          "${subj}_mean_affine${Niter}_tr.nii.gz" "${subj}_intra_reg_volumes.txt"
fi

cd "${workdir}"
echo; echo "DONE with intra-subject registration for ${subj}"