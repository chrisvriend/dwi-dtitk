#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: converted to SLURM array (one task per subject), set -euo pipefail,
# source config, input validation, safer loops, trap cleanup

#SBATCH --job-name=dtitk-diffmaps
#SBATCH --mem=1G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:30:00
#SBATCH --nice=2000
#SBATCH -o 4-DTITK_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 004-DTITK_makediffmaps.sh
    Extract AD, FA, MD, RD diffusion maps from DTITK images in template
    space, warp NODDI maps (ODI, NDI, ISOVF) to template space, and
    merge all maps into a single 4D subject-specific image.
    Run as a SLURM array job (one task per subject/session).

    Usage: sbatch --array=1-N%simul ./004-DTITK_makediffmaps.sh workdir bshell subjects
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
diffdir=${workdir}/diffmaps
tempdir=${workdir}/NODDItemp_${subj}   # per-subject temp dir avoids collisions

mkdir -p "${diffdir}"
mkdir -p "${tempdir}"
trap "rm -rf ${tempdir}" EXIT

echo "extract diffusion measures"
echo "----------"
echo "${subj}"
echo "----------"

###############################################################################
# Find all warped scans for this subject
###############################################################################
mapfile -t scans < <(ls -1 "${warpdir}/${subj}"*_res-*mm_dtitk.nii.gz 2>/dev/null)

if [ ${#scans[@]} -eq 0 ]; then
    echo "ERROR: no warped scans found for ${subj} in ${warpdir}" >&2
    exit 1
fi

for scan in "${scans[@]}"; do

    scanbase=$(basename "${scan}")
    subj_session=${scanbase%_space-template_desc-b${bshell}*}

    # parse subject and session
    subj_part=${subj_session%_ses-*}
    session=${subj_session#${subj_part}_}
    # handle cross-sectional (no session in filename)
    if [ "${session}" = "${subj_session}" ]; then
        session=""
    fi

    if [ -z "${session}" ]; then
        sessionpath=/
        sessionfile=_
    else
        sessionpath=/${session}/
        sessionfile=_${session}_
    fi

    # skip if already done
    if [ -f "${diffdir}/${subj_session}_space-template_desc-diffmaps_res-1mm_dtitk.nii.gz" ]; then
        echo "${subj_session} | diffusion maps already extracted — skipping"
        continue
    fi

    echo
    echo "${subj_session}"
    base=$(remove_ext "${scanbase}")

    ###########################################################################
    # Extract DTI scalar maps: FA, AD, RD, MD (via trace)
    ###########################################################################
    for diff in fa ad rd tr; do
        echo " | ${diff} | "
        TVtool -in "${scan}" -${diff}
        mv "${warpdir}/${base}_${diff}.nii.gz" \
           "${diffdir}/${subj_session}_${diff^^}.nii.gz"
    done

    # MD = TR / 3
    fslmaths "${diffdir}/${subj_session}_TR.nii.gz" \
        -div 3 "${diffdir}/${subj_session}_MD.nii.gz"
    rm -f "${diffdir}/${subj_session}_TR.nii.gz"

    ###########################################################################
    # Warp NODDI maps to template space (if available)
    ###########################################################################
    # locate dwi directory (longitudinal or cross-sectional)
    if [ -d "${workdir}/${subj_part}/${session}/dwi" ]; then
        dwidir="${workdir}/${subj_part}/${session}/dwi"
    elif [ -d "${workdir}/${subj_part}/dwi" ]; then
        dwidir="${workdir}/${subj_part}/dwi"
    else
        echo "WARNING: cannot find dwi folder for ${subj_session} — skipping NODDI"
        dwidir=""
    fi

    noddi_available=0
    if [ -n "${dwidir}" ] && \
       [ -f "${dwidir}/${subj_session}_space-dwi_desc-ndi_noddi.nii.gz" ] && \
       [ -f "${dwidir}/${subj_session}_space-dwi_desc-odi_noddi.nii.gz" ] && \
       [ -f "${dwidir}/${subj_session}_space-dwi_desc-isovf_noddi.nii.gz" ]; then
        echo "NODDI output available"
        noddi_available=1
    else
        echo "${subj_session} has no NODDI output"
    fi

    if [ "${noddi_available}" -eq 1 ]; then

        # resolve warp file
        if [ -f "${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz" ]; then
            warpfile="${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz"
        elif [ -f "${warpdir}/${subj_part}_dwi-2-dtitktemplate.df.nii.gz" ]; then
            warpfile="${warpdir}/${subj_part}_dwi-2-dtitktemplate.df.nii.gz"
        else
            echo "WARNING: no warp file found for ${subj_session} — skipping NODDI"
            warpfile=""
        fi

        if [ -n "${warpfile}" ]; then
            for NODDI in odi isovf ndi; do
                echo " | ${NODDI} | "
                SVAdjustVoxelspace \
                    -in  "${dwidir}/${subj_session}_space-dwi_desc-${NODDI}_noddi.nii.gz" \
                    -out "${tempdir}/${subj_session}_${NODDI}_dtitk.nii.gz" \
                    -origin 0 0 0

                deformationScalarVolume \
                    -in     "${tempdir}/${subj_session}_${NODDI}_dtitk.nii.gz" \
                    -trans  "${warpfile}" \
                    -target "${regdir}/mean_diffeomorphic_initial6.nii.gz" \
                    -out    "${diffdir}/${subj_session}_${NODDI}.nii.gz" \
                    -vsize 1 1 1
            done
        fi
    fi

    ###########################################################################
    # Merge all maps into a single 4D image
    ###########################################################################
    echo
    echo "Merging diffusion maps for ${subj_session}"
    cd "${diffdir}"

    if [ -f "${subj_session}_odi.nii.gz" ]; then
        # AD FA MD RD ODI NDI ISOVF (7 volumes)
        diffs=(
            "${subj_session}_AD.nii.gz"
            "${subj_session}_FA.nii.gz"
            "${subj_session}_MD.nii.gz"
            "${subj_session}_RD.nii.gz"
            "${subj_session}_odi.nii.gz"
            "${subj_session}_ndi.nii.gz"
            "${subj_session}_isovf.nii.gz"
        )
    else
        # AD FA MD RD (4 volumes)
        diffs=(
            "${subj_session}_AD.nii.gz"
            "${subj_session}_FA.nii.gz"
            "${subj_session}_MD.nii.gz"
            "${subj_session}_RD.nii.gz"
        )
    fi

    # verify all expected files exist before merging
    for f in "${diffs[@]}"; do
        if [ ! -f "${f}" ]; then
            echo "ERROR: expected diffusion map not found: ${f}" >&2
            exit 1
        fi
    done

    fslmerge -t \
        "${diffdir}/${subj_session}_space-template_desc-diffmaps_res-1mm_dtitk.nii.gz" \
        "${diffs[@]}"

    # clean up individual maps
    rm -f "${diffdir}/${subj_session}_??.nii.gz" \
          "${diffdir}/${subj_session}_???.nii.gz" \
          "${diffdir}/${subj_session}_?????.nii.gz"

    unset diffs

    echo " ______________________________________ "
done

echo
echo "DONE extracting diffusion maps for ${subj}"
