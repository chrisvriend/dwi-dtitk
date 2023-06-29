#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 05-DTITK_TBSS.sh
    merges subject-specific diffusion maps to all_[diff].nii.gz in preparation of TBSS,
    skeletonizes the maps using the mean_FA and projects the all_[diff].nii.gz back to subject-specific skeletonized diffusion maps
   
    Usage: ./05-DTITK_TBSS.sh diffmaps
    Obligatory: diffmaps = full path to diffusion maps produced by previous 04-DTITK_makediffmaps.sh script
    
EOF
    exit 1
}

[ _$1 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.6.5

diffdir=${1}

cd ${diffdir}

if [ ! -f mean_FA.nii.gz ]; then

    # Generate the FA map of the high-resolution population-specific DTI template
    TVtool -in mean_final_high_res.nii.gz -fa

    # Rename the FA map to be consistent with the TBSS pipeline
    mv mean_final_high_res_fa.nii.gz mean_FA.nii.gz
fi

# Generate the white matter skeleton from the high-resolution FA map of the DTI template
if [ ! -f mean_FA_skeleton.nii.gz ]; then
    tbss_skeleton -i mean_FA -o mean_FA_skeleton

fi

# restructure diff maps and merge (AD FA MD RD OD ND FW)
rm -f subjects.list
ndiffvols=$(fslnvols $(ls -1 *space-template_desc-diffmaps_res-?mm_dtitk.nii.gz | head -1))
if ((ndiffvols == 7)); then
    diffs=(AD FA MD RD OD ND FW)
elif ((ndiffvols == 4)); then
    diffs=(AD FA MD RD)
else
    echo "ERROR! diffmaps do not have the correct number of volumes"
    exit
fi

for diffscan in $(ls -1 *space-template_desc-diffmaps_res-?mm_dtitk.nii.gz); do

    subj_session=${diffscan%_space-template_desc-diffmaps*}

    echo ${subj_session} >> subjects.list
done

echo "merge diffusion maps together"

for diff in ${diffs[@]}; do
    if [ ! -f all_${diff}.nii.gz ]; then

        echo " | ${diff} | "
        for diffscan in $(ls -1 *space-template_desc-diffmaps_res-?mm_dtitk.nii.gz); do

            subj_session=${diffscan%_space-template_desc-diffmaps*}

            if [[ ${diff} == "AD" ]]; then
                vol=0
            elif [[ ${diff} == "FA" ]]; then
                vol=1
            elif [[ ${diff} == "MD" ]]; then
                vol=2
            elif [[ ${diff} == "RD" ]]; then
                vol=3
            elif [[ ${diff} == "OD" ]]; then
                vol=4
            elif [[ ${diff} == "ND" ]]; then
                vol=5
            elif [[ ${diff} == "FW" ]]; then
                vol=6
            else
                echo "${diff} not recognized"
                break
            fi

            fslroi ${diffscan} DWI_${subj_session}_${diff}.nii.gz ${vol} 1

        done
        fslmerge -t all_${diff} $(ls DWI_*_${diff}.nii.gz)
        rm DWI_*_${diff}.nii.gz

    fi
done
echo
echo "merging complete"
echo
# apply fslmaths to all_FA to create a combined binary mask volume called mean_FA_mask
if [ ! -f mean_FA_mask.nii.gz ]; then
    echo "create masks of diff images"
    fslmaths all_FA -max 0 -Tmin -bin mean_FA_mask -odt char
fi
if [ ! -f mean_FA_skeleton_mskd.nii.gz ]; then
    echo "mask skeleton"
    fslmaths mean_FA_skeleton -mas mean_FA_mask mean_FA_skeleton_mskd
fi
for diff in ${diffs[@]}; do
    if [ ${diff} == FA ]; then continue; fi
    fslmaths all_${diff} -mas mean_FA_mask all_${diff}
done

mkdir -p tbss tbss/stats
cp mean_FA.nii.gz mean_FA_skeleton_mskd.nii.gz mean_FA_mask.nii.gz tbss/stats

cd tbss/stats

for diff in ${diffs[@]}; do
    ln -sf ../../all_${diff}.nii.gz all_${diff}.nii.gz
done

mv mean_FA_skeleton_mskd.nii.gz mean_FA_skeleton.nii.gz

cd ..

#############################################
# final tbss steps
#############################################

thresh=0.2
if [ ! -f stats/all_FA_skeletonised.nii.gz ]; then
    # on FA image
    tbss_4_prestats ${thresh}
fi
cd stats

# non-FA processing
for diff in ${diffs[@]}; do
    if [ ${diff} == FA ]; then continue; fi
    cd ${diffdir}/tbss/stats
    if [ ! -f all_${diff}_skeletonised.nii.gz ]; then

        echo "projecting all_${diff} onto mean FA skeleton"

        tbss_skeleton -i mean_FA -p ${thresh} mean_FA_skeleton_mask_dst \
            ${FSLDIR}/data/standard/LowerCingulum_1mm all_FA all_${diff}_skeletonised \
            -a all_${diff}.nii.gz
    fi

    mkdir -p temp
    cd temp
    fslsplit ../all_${diff}_skeletonised
    echo "convert skeletonized all_${diff} maps --> subject-specific maps"

    counter=1

    for vol in $(ls -1 vol*.nii.gz); do
        subjid=$(awk -v myvar=${counter} 'NR==myvar' ${diffdir}/subjects.list)
        mv ${vol} ${subjid}_${diff}_skeleton.nii.gz
        counter=$(($counter + 1))
        unset subjid
    done
    ls -1 vol*.nii.gz >vols.txt 2>/dev/null

    if test $(cat vols.txt | wc -l) -gt 0; then
        echo "WARNING!!! something went wrong with renaming the skeletonized volumes"
        exit
    else
        rm -f vols.txt
    fi

done

# still need to do it for FA
cd ${diffdir}/tbss/stats/temp

fslsplit ../all_FA_skeletonised
counter=1
echo "convert skeletonized all_FA --> subject-specific maps"

for vol in $(ls -1 vol*.nii.gz); do
    subjid=$(awk -v myvar=${counter} 'NR==myvar' ${diffdir}/subjects.list)
    mv ${vol} ${subjid}_FA_skeleton.nii.gz
    counter=$(($counter + 1))
    unset subjid
done
ls -1 vol*.nii.gz >vols.txt 2>/dev/null

if test $(cat vols.txt | wc -l) -gt 0; then
    echo "WARNING!!! something went wrong with renaming the skeletonized volumes"
    exit
else
    rm -f vols.txt
fi

# merge skeletonized maps back to subject-specific 4D image
for subjid in $(cat ${diffdir}/subjects.list); do

    rm -f ${subjid}.tmp
    for diff in ${diffs[@]}; do
        echo ${subjid}_${diff}_skeleton.nii.gz >> ${subjid}.tmp
    done
    fslmerge -t ${diffdir}/${subjid}_space-template_desc-skldiffmaps_res-1mm_dtitk.nii.gz \
        $(cat ${subjid}.tmp)
    rm ${subjid}.tmp
done

#rm -r ${diffdir}/tbss/stats/temp
