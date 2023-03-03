#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 07-DTITK_extract-diffvalues.sh
   
    Usage: ./07-DTITK_extract-diffvalues.sh diffdir tractdir
    Obligatory: 
    diffdir = full path to diffusion maps folder produced by previous 04-DTITK_makediffmaps.sh script
    tractdir = full path to folder with tracts in templatespace, produced by previous 06-DTITK_warpatlas2template.sh script
    
EOF
    exit 1
}

[ _$2 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.5.1

headdir=${1}
tractfile=${2}
diffdir=${headdir}/diffmaps
tractdir=${headdir}/tracts
scriptdir=${headdir}/scripts
outputdir=${headdir}/diffvalues
simul=8

cd ${tractdir}
# skeletonize tracts 
if [ ! -f ${tractfile} ]; then 

echo "tractfile not found - exiting script"
exit

fi 

for tract in $(cat ${tractfile}); do 

if [ ! -f ${tract}_skl.nii.gz ]; then 
echo "skeletonize ${tract}"
fslmaths ${tract} -mul ${diffdir}/mean_FA_skeleton_mskd.nii.gz -bin ${tract}_skl

fi
done

cd ${diffdir}

## non-skeletonized ##

# not yet implemented


# skeletonized 

echo "extract median diffusion measures from skeletonized diffusion maps"
rm -f subjects.txt
for subjskl in $(ls -1 sub-*sklt.nii.gz); do 
subj=${subjskl%_dtitk_diffusion_sklt.nii.gz*}
echo ${subj} >> subjects.txt
done 
nsubj=$(cat subjects.txt | wc -l)

sbatch --wait --array="1-${nsubj}%${simul}" \
${scriptdir}/extract_diffmeasures_slurm.sh \
${diffdir} subjects.txt ${tractdir} ${tractfile} ${outputdir} ${scriptdir}

echo "DONE with ${subj}"


##################################################################



# doesnt seem to work in combination with fslstats -K preoption
# cd ${tractdir}
# multiplier=1
# for tract in $(cat ${tractfile}); do 
# if test ${multiplier} -eq 1; then 
# echo "create base image for tracts"
# fslmaths ${tract}.nii.gz -mul 0 temp.nii.gz 

# fi 
# echo "add ${tract} to base image"
# fslmaths ${tract}.nii.gz -mul ${multiplier} temp2.nii.gz 
# fslmaths temp.nii.gz -add temp2.nii.gz temp.nii.gz
# multiplier=$(($multiplier + 1))

# rm temp2.nii.gz 
# done 
# mv temp.nii.gz tracts-of-interest.nii.gz 
