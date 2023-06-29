#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 07-DTITK_extract-diffvalues.sh
   
    Usage: ./07-DTITK_extract-diffvalues.sh workdir tractfile
    Obligatory: 
    workdir = full path to working (head) directory where all folders are situated, including the subject folders (see wrapper script)
    tractdir = full path to folder with tracts in templatespace, produced by previous 06-DTITK_warpatlas2template.sh script
    scriptdir
EOF
    exit 1
}

[ _$3 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.6.5

workdir=${1}
tractfile=${2}
scriptdir=${3}
diffdir=${workdir}/diffmaps
tractdir=${workdir}/tracts
outputdir=${workdir}/diffvalues
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
for subjskl in $(ls -1 sub-*skldiffmaps*.nii.gz); do 
subj_session=${subjskl%_space-template_desc-skldiffmaps*}
echo ${subj_session} >> subjects.txt
done 
nsubj=$(cat subjects.txt | wc -l)

sbatch --wait --array="1-${nsubj}%${simul}" \
 ${scriptdir}/extract_diffmeasures_slurm.sh \
 ${diffdir} subjects.txt ${tractdir} ${tractfile} ${outputdir} ${scriptdir}

mkdir -p ${diffdir}/logs
mv ${diffdir}/*.log ${diffdir}/logs
echo "DONE"

##################################################################