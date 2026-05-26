#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, input validation,
# safer loops, output existence checks, cleaner temp handling

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 005-DTITK_TBSS.sh
    Merges subject-specific diffusion maps into all_[diff].nii.gz,
    generates the mean FA skeleton, projects maps onto the skeleton,
    and splits back to subject-specific skeletonised maps.

    Usage: bash ./005-DTITK_TBSS.sh diffdir
      diffdir  full path to diffusion maps directory (workdir/diffmaps)

EOF
    exit 1
}

[ _${1:-} = _ ] && Usage

diffdir=${1}

# source site config
scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}

# validate input
if [ ! -d "${diffdir}" ]; then
    echo "ERROR: diffdir not found: ${diffdir}" >&2
    exit 1
fi

cd "${diffdir}"

###############################################################################
# Generate mean FA map from group template
###############################################################################
if [ ! -f mean_FA.nii.gz ]; then
    if [ ! -f mean_final_high_res.nii.gz ]; then
        echo "ERROR: mean_final_high_res.nii.gz not found in ${diffdir}" >&2
        exit 1
    fi
    echo "Generating mean FA from group template"
    TVtool -in mean_final_high_res.nii.gz -fa
    mv mean_final_high_res_fa.nii.gz mean_FA.nii.gz
else
    echo "mean_FA.nii.gz already exists — skipping"
fi

###############################################################################
# Generate white matter skeleton
###############################################################################
if [ ! -f mean_FA_skeleton.nii.gz ]; then
    echo "Generating WM skeleton"
    tbss_skeleton -i mean_FA -o mean_FA_skeleton
else
    echo "mean_FA_skeleton.nii.gz already exists — skipping"
fi

###############################################################################
# Determine diffusion map set from first subject file
###############################################################################
shopt -s nullglob
files=(*space-template_desc-diffmaps_res-?mm_dtitk.nii.gz)
first_scan=${files[0]:-}   # empty if no files
if [ -z "${first_scan}" ]; then
    echo "ERROR: no diffmap files found in ${diffdir}" >&2
    exit 1
fi

ndiffvols=$(fslnvols "${first_scan}")
if [ "${ndiffvols}" -eq 7 ]; then
    diffs=(AD FA MD RD OD ND FW)
elif [ "${ndiffvols}" -eq 4 ]; then
    diffs=(AD FA MD RD)
else
    echo "ERROR: unexpected number of volumes (${ndiffvols}) in ${first_scan}" >&2
    exit 1
fi
echo "Diffusion maps: ${diffs[*]} (${ndiffvols} volumes)"

###############################################################################
# Build subjects list
###############################################################################
rm -f subjects.list
while IFS= read -r diffscan; do
    subj_session=${diffscan%_space-template_desc-diffmaps*}
    echo "${subj_session}" >> subjects.list
done < <(ls -1 *space-template_desc-diffmaps_res-?mm_dtitk.nii.gz)

nsubj=$(wc -l < subjects.list)
echo "Found ${nsubj} subjects"

###############################################################################
# Merge per-subject maps into all_[diff].nii.gz
###############################################################################
echo "Merging diffusion maps"

# map diff name to volume index
declare -A vol_index=([AD]=0 [FA]=1 [MD]=2 [RD]=3 [OD]=4 [ND]=5 [FW]=6)

for diff in "${diffs[@]}"; do
    if [ -f "all_${diff}.nii.gz" ]; then
        echo "all_${diff}.nii.gz already exists — skipping"
        continue
    fi
    echo " | ${diff} | "

    tmp_list=$(mktemp /tmp/dtitk_merge_XXXXXX.txt)
    trap "rm -f ${tmp_list}" EXIT

    vol=${vol_index[${diff}]}
    while IFS= read -r diffscan; do
        subj_session=${diffscan%_space-template_desc-diffmaps*}
        fslroi "${diffscan}" "DWI_${subj_session}_${diff}.nii.gz" "${vol}" 1
        echo "DWI_${subj_session}_${diff}.nii.gz" >> "${tmp_list}"
    done < <(ls -1 *space-template_desc-diffmaps_res-?mm_dtitk.nii.gz)

    fslmerge -t "all_${diff}" $(cat "${tmp_list}")
    rm -f $(cat "${tmp_list}")
    rm -f "${tmp_list}"
done

echo
echo "Merging complete"
echo

###############################################################################
# Create mean FA mask and mask the skeleton
###############################################################################
if [ ! -f mean_FA_mask.nii.gz ]; then
    echo "Creating mean FA mask"
    fslmaths all_FA -max 0 -Tmin -bin mean_FA_mask -odt char
fi

if [ ! -f mean_FA_skeleton_mskd.nii.gz ]; then
    echo "Masking skeleton"
    fslmaths mean_FA_skeleton -mas mean_FA_mask mean_FA_skeleton_mskd
fi

# mask non-FA maps
for diff in "${diffs[@]}"; do
    [ "${diff}" = FA ] && continue
    fslmaths "all_${diff}" -mas mean_FA_mask "all_${diff}"
done

###############################################################################
# Set up tbss/stats directory structure
###############################################################################
mkdir -p tbss/stats
cp mean_FA.nii.gz mean_FA_skeleton_mskd.nii.gz mean_FA_mask.nii.gz tbss/stats/

cd tbss/stats
for diff in "${diffs[@]}"; do
    [ -L "all_${diff}.nii.gz" ] || ln -sf "../../all_${diff}.nii.gz" "all_${diff}.nii.gz"
done
mv mean_FA_skeleton_mskd.nii.gz mean_FA_skeleton.nii.gz
cd ..

###############################################################################
# TBSS skeleton projection
###############################################################################
thresh=0.2

if [ ! -f stats/all_FA_skeletonised.nii.gz ]; then
    echo "Running tbss_4_prestats (FA)"
    tbss_4_prestats ${thresh}
fi

# non-FA maps
for diff in "${diffs[@]}"; do
    [ "${diff}" = FA ] && continue
    cd "${diffdir}/tbss/stats"
    if [ ! -f "all_${diff}_skeletonised.nii.gz" ]; then
        echo "Projecting all_${diff} onto mean FA skeleton"
        tbss_skeleton -i mean_FA \
            -p ${thresh} mean_FA_skeleton_mask_dst \
            "${FSLDIR}/data/standard/LowerCingulum_1mm" \
            all_FA "all_${diff}_skeletonised" \
            -a "all_${diff}.nii.gz"
    else
        echo "all_${diff}_skeletonised.nii.gz already exists — skipping"
    fi
done

###############################################################################
# Split skeletonised 4D images back to subject-specific volumes
###############################################################################
mkdir -p "${diffdir}/tbss/stats/temp"

for diff in "${diffs[@]}"; do
    cd "${diffdir}/tbss/stats/temp"

    skl_file="${diffdir}/tbss/stats/all_${diff}_skeletonised.nii.gz"
    if [ ! -f "${skl_file}" ]; then
        echo "ERROR: ${skl_file} not found" >&2
        exit 1
    fi

    echo "Splitting all_${diff}_skeletonised into subject-specific maps"
    fslsplit "${skl_file}" vol_${diff}_

    counter=1
    while IFS= read -r subjid; do
        # zero-padded volume index to match fslsplit output
        padded=$(printf "%04d" $((counter - 1)))
        vol_file="vol_${diff}_${padded}.nii.gz"
        if [ ! -f "${vol_file}" ]; then
            echo "ERROR: expected volume ${vol_file} not found after fslsplit" >&2
            exit 1
        fi
        mv "${vol_file}" "${subjid}_${diff}_skeleton.nii.gz"
        counter=$((counter + 1))
    done < "${diffdir}/subjects.list"

    # sanity check: no unnamed volumes remain
    remaining=$(ls vol_${diff}_*.nii.gz 2>/dev/null | wc -l)
    if [ "${remaining}" -gt 0 ]; then
        echo "WARNING: ${remaining} unmatched volume(s) after splitting all_${diff}" >&2
    fi
done

###############################################################################
# Merge skeletonised maps back to subject-specific 4D image
###############################################################################
cd "${diffdir}/tbss/stats/temp"

while IFS= read -r subjid; do
    tmp_merge=$(mktemp /tmp/dtitk_sklmerge_XXXXXX.txt)
    trap "rm -f ${tmp_merge}" EXIT

    for diff in "${diffs[@]}"; do
        echo "${subjid}_${diff}_skeleton.nii.gz" >> "${tmp_merge}"
    done

    fslmerge -t \
        "${diffdir}/${subjid}_space-template_desc-skldiffmaps_res-1mm_dtitk.nii.gz" \
        $(cat "${tmp_merge}")

    rm -f "${tmp_merge}"
done < "${diffdir}/subjects.list"

echo
echo "DONE"
