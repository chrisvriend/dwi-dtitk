#!/bin/bash

#SBATCH --job-name=dtitk-regtemp
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:45:00
#SBATCH --nice=2000
#SBATCH -o 1-DTITK_%A_%a.log

workdir=${1}
templatedir=${2}
subjects=${3}

module load dtitk/2.3.1
module load fsl/6.0.6.5
export DTITK_USE_QSUB=0


if [ -f long_subjects.txt ]; then
:

fi
# rigid registration
dti_rigid_sn ${templatedir}/mean_diffeomorphic_initial6.nii.gz \
    ${subj}.txt EDS
# affine registration
dti_affine_sn ${templatedir}/mean_diffeomorphic_initial6.nii.gz \
    ${subj}.txt EDS 1

# needed?
ls -1 ${subj}*aff.nii.gz > ${subj}_aff.txt 

# diffeomorphic registration
dti_diffeomorphic_sn \
    ${templatedir}/mean_diffeomorphic_initial6.nii.gz ${subj}_aff.txt \
    ${templatedir}/mask.nii.gz 6 0.002


#warp to template space and reslice to 1mm3 voxels

# in case of longitudinal data the warping files first needs to be combined

# probably better to use the inner workings of this script ?
dti_warp_to_template_group ${subj}.txt \
    ${templatedir}/mean_diffeomorphic_initial6.nii.gz 1 1 1
