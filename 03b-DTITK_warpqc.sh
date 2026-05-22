#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, safer loops,
# input validation, hardcoded bshell replaced with config,
# temp file cleanup, fixed log naming

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 03b-DTITK_warpqc.sh
    Computes the mean warped DTI image across all subjects, extracts
    the L3 eigenvalue map for registration quality inspection, and
    generates per-subject overlay PNGs.

    Usage: bash ./03b-DTITK_warpqc.sh warpdir
      warpdir  full path to directory containing warped subject images
               (*_space-template_desc-b*_res-?mm_dtitk.nii.gz)

EOF
    exit 1
}

[ _${1:-} = _ ] && Usage

scriptdir=${1}
warpdir=${2}

# source site config
#criptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}

# validate input
if [ ! -d "${warpdir}" ]; then
    echo "ERROR: warpdir not found: ${warpdir}" >&2
    exit 1
fi

cd "${warpdir}"

echo "Making overlays for quality inspection"

# collect warped scans
mapfile -t warped_scans < <(ls -1 *res-?mm_dtitk.nii.gz 2>/dev/null)

if [ ${#warped_scans[@]} -eq 0 ]; then
    echo "ERROR: no warped scans (*res-?mm_dtitk.nii.gz) found in ${warpdir}" >&2
    exit 1
fi

echo "Found ${#warped_scans[@]} warped scans"

# write list for TVMean
printf '%s\n' "${warped_scans[@]}" > subjs_warped.txt

###############################################################################
# Compute mean image and extract L3 eigenvalue map for QC reference
###############################################################################
if [ ! -f mean_final_high_res.nii.gz ]; then
    echo "Computing mean warped image"
    TVMean -in subjs_warped.txt -out mean_final_high_res.nii.gz
else
    echo "mean_final_high_res.nii.gz already exists — skipping TVMean"
fi

if [ ! -f mean_final_high_res_regcheck.nii.gz ]; then
    echo "Extracting L3 eigenvalue map for QC reference"
    TVEigenSystem -in mean_final_high_res.nii.gz -type FSL
    mv mean_final_high_res_L3.nii.gz mean_final_high_res_regcheck.nii.gz
    rm -f mean_final_high_res_??.nii.gz
else
    echo "mean_final_high_res_regcheck.nii.gz already exists — skipping"
fi

###############################################################################
# Per-subject QC overlay PNGs
###############################################################################
mkdir -p "${warpdir}/QC"

for subj_scan in "${warped_scans[@]}"; do
    stem=${subj_scan%_space-template_desc-b${bshell}*}
    stam=${subj_scan%.nii.gz}

    echo "--------"
    echo "${stem}"
    echo "--------"

    if [ -f "${warpdir}/QC/${stem}_overlay.png" ]; then
        echo "QC overlay already exists for ${stem} — skipping"
        continue
    fi

    TVEigenSystem -in "${subj_scan}" -type FSL
    slicer mean_final_high_res_regcheck.nii.gz \
           "${stam}_L3.nii.gz" \
           -a "${warpdir}/QC/${stem}_overlay.png"
    rm -f "${stam}_??.nii.gz"
done

echo
echo "DONE — QC overlays written to ${warpdir}/QC"
