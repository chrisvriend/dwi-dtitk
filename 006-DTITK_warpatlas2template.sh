#!/bin/bash 

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

#SBATCH --job-name=atlas2template
#SBATCH --mem=16G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=16
#SBATCH --time=00-0:30:00
#SBATCH --nice=2000
#SBATCH -o atlas2template_%a.log


# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 06-DTITK_warpatlas2template.sh
	warp atlas of WM tracts (default = JHU ICBM 1mm) to group template

    Usage: ./06-DTITK_warpatlas2template.sh workdir labelfile
    Obligatory: 
    workdir = full path to working (head) directory where all folders are situated, 
	including the subject folders (see wrapper script)
    labelfile = full path to file that contains the names of the tracts and the intensity values in the atlas image
    
EOF
    exit 1
}

[ _$2 = _ ] && Usage


threads=16

# source software
module load fsl/6.0.6.5
module load ANTs/2.4.1

workdir=${1}
labelfile=${2}

diffdir=${workdir}/diffmaps
tractdir=${workdir}/tracts
mkdir -p ${tractdir}

cd ${diffdir}
if [ ! -f ICBM2FA1Warp.nii.gz ]; then 
antsRegistrationSyN.sh -d 3 -f ${diffdir}/mean_FA.nii.gz \
-m ${FSLDIR}/data/atlases/JHU/JHU-ICBM-FA-1mm.nii.gz -n ${threads} -t s -o ICBM2FA
fi

antsApplyTransforms -d 3 -e 1 \
-i ${FSLDIR}/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz \
-r ${diffdir}/mean_FA.nii.gz \
-o ${tractdir}/JHU-ICBM-labels_templatespace.nii.gz -n GenericLabel \
-t ICBM2FA1Warp.nii.gz -t ICBM2FA0GenericAffine.mat -v -u int


minR=$(fslstats ${tractdir}/JHU-ICBM-labels_templatespace.nii.gz -R | awk '{ print $1 }' | bc -l)
minint=${minR%.*}

if test ${minint} -lt 0; then
echo "inverting JHU atlas"
 fslmaths ${tractdir}/JHU-ICBM-labels_templatespace.nii.gz -mul -1 temp
 mv temp.nii.gz ${tractdir}/JHU-ICBM-labels_templatespace.nii.gz
fi 

for tract in CCg CCb CCs aLIC_R aLIC_L PTR_R PTR_L SagS_R SagS_L CingCG_R CingCG_L CingHIPP_R CingHIPP_L SLF_R SLF_L UncF_R UncF_L; do 

tractID=$(cat ${labelfile} | grep ${tract} | awk '{print $1}' )
echo "${tract} == ${tractID}"
fslmaths ${tractdir}/JHU-ICBM-labels_templatespace.nii.gz -uthr ${tractID} -thr ${tractID} -bin ${tractdir}/JHU-${tract}
unset tractID
done
