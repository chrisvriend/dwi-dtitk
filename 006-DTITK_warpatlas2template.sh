#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, input validation,
# output existence checks, safer variable handling, fixed log naming

#SBATCH --job-name=dtitk-atlas2template
#SBATCH --mem=16G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=16
#SBATCH --time=00-0:30:00
#SBATCH --nice=2000
#SBATCH -o atlas2template_%j.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 006-DTITK_warpatlas2template.sh
    Registers the JHU-ICBM atlas to the group mean FA map using ANTs
    SyN registration, then extracts individual WM tract masks.

    Usage: sbatch ./006-DTITK_warpatlas2template.sh workdir labelfile
      workdir    full path to working (head) directory
      labelfile  full path to JHU-ICBM.labels file

EOF
    exit 1
}

[ _${2:-} = _ ] && Usage

workdir=${1}
labelfile=${2}

# source site config
scriptdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${scriptdir}/config.sh"

# load software
module load fsl/${FSL_VERSION}
module load ANTs/${ANTS_VERSION}

threads=${SLURM_CPUS_PER_TASK:-16}

# validate inputs
if [ ! -d "${workdir}" ]; then
    echo "ERROR: workdir not found: ${workdir}" >&2
    exit 1
fi
if [ ! -f "${labelfile}" ]; then
    echo "ERROR: labelfile not found: ${labelfile}" >&2
    exit 1
fi

diffdir=${workdir}/diffmaps
tractdir=${workdir}/tracts
mkdir -p "${tractdir}"

if [ ! -f "${diffdir}/mean_FA.nii.gz" ]; then
    echo "ERROR: mean_FA.nii.gz not found in ${diffdir}" >&2
    exit 1
fi

if [ ! -f "${FSLDIR}/data/atlases/JHU/JHU-ICBM-FA-1mm.nii.gz" ]; then
    echo "ERROR: JHU-ICBM-FA-1mm.nii.gz not found in FSL atlas directory" >&2
    exit 1
fi

if [ ! -f "${FSLDIR}/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz" ]; then
    echo "ERROR: JHU-ICBM-labels-1mm.nii.gz not found in FSL atlas directory" >&2
    exit 1
fi

cd "${diffdir}"

###############################################################################
# Register JHU-ICBM FA to group mean FA (ANTs SyN)
###############################################################################
if [ ! -f ICBM2FA1Warp.nii.gz ]; then
    echo "Running ANTs SyN registration: JHU-ICBM FA -> group mean FA"
    antsRegistrationSyN.sh \
        -d 3 \
        -f "${diffdir}/mean_FA.nii.gz" \
        -m "${FSLDIR}/data/atlases/JHU/JHU-ICBM-FA-1mm.nii.gz" \
        -n "${threads}" \
        -t s \
        -o ICBM2FA

    if [ ! -f ICBM2FA1Warp.nii.gz ]; then
        echo "ERROR: ANTs registration failed — ICBM2FA1Warp.nii.gz not created" >&2
        exit 1
    fi
    echo "ANTs registration complete"
else
    echo "ICBM2FA1Warp.nii.gz already exists — skipping registration"
fi

###############################################################################
# Apply warp to JHU-ICBM label atlas
###############################################################################
if [ ! -f "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz" ]; then
    echo "Warping JHU-ICBM label atlas to template space"
    antsApplyTransforms \
        -d 3 \
        -e 1 \
        -i "${FSLDIR}/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz" \
        -r "${diffdir}/mean_FA.nii.gz" \
        -o "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz" \
        -n GenericLabel \
        -t ICBM2FA1Warp.nii.gz \
        -t ICBM2FA0GenericAffine.mat \
        -v \
        -u int

    if [ ! -f "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz" ]; then
        echo "ERROR: atlas warp failed — JHU-ICBM-labels_templatespace.nii.gz not created" >&2
        exit 1
    fi
    echo "Atlas warped to template space"
else
    echo "JHU-ICBM-labels_templatespace.nii.gz already exists — skipping"
fi

###############################################################################
# Fix label polarity if needed (invert negative values)
###############################################################################
minR=$(fslstats "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz" -R | awk '{print $1}')
minint=${minR%.*}

if [ "${minint}" -lt 0 ]; then
    echo "Inverting JHU atlas (negative values detected)"
    fslmaths "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz" \
        -mul -1 "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz"
fi

###############################################################################
# Extract individual tract masks
###############################################################################
echo "Extracting individual tract masks"

tracts=(CCg CCb CCs aLIC_R aLIC_L PTR_R PTR_L SagS_R SagS_L \
        CingCG_R CingCG_L CingHIPP_R CingHIPP_L SLF_R SLF_L UncF_R UncF_L)

n_ok=0
n_failed=0

for tract in "${tracts[@]}"; do

    output="${tractdir}/JHU-${tract}.nii.gz"

    if [ -f "${output}" ]; then
        echo "  ${tract}: already exists — skipping"
        n_ok=$((n_ok + 1))
        continue
    fi

    tractID=$(awk -v t="${tract}" '$0 ~ t {print $1; exit}' "${labelfile}")

    if [ -z "${tractID}" ]; then
        echo "  WARNING: tract '${tract}' not found in ${labelfile} — skipping" >&2
        n_failed=$((n_failed + 1))
        continue
    fi

    echo "  ${tract} == label ${tractID}"
    fslmaths "${tractdir}/JHU-ICBM-labels_templatespace.nii.gz" \
        -uthr "${tractID}" -thr "${tractID}" -bin "${output}"

    if [ ! -f "${output}" ]; then
        echo "  ERROR: failed to create ${output}" >&2
        n_failed=$((n_failed + 1))
    else
        n_ok=$((n_ok + 1))
    fi
done

echo
echo "Tract extraction complete: ${n_ok} OK, ${n_failed} failed/skipped"

if [ "${n_failed}" -gt 0 ]; then
    echo "WARNING: ${n_failed} tract(s) could not be extracted — check labelfile and atlas" >&2
fi

echo
echo "DONE"
