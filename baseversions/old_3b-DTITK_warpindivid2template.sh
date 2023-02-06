#!/bin/bash 

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

module load dtitk/2.3.1
export DTITK_USE_QSUB=0
scriptdir=/home/anw/cvriend/my-scratch/DTITK_TIPICCO/scripts

cleanup=0

workdir=${1}
template=${2}
subjects=${3}
nsubj=$(cat ${subjects} | wc -l)
#subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" ${3})
mask=${4}
simul=${5}

cd ${workdir}
mkdir -p ${workdir}/logs

#dti_rigid_sn ${template} ${subj} EDS
#dti_affine_sn ${template} ${subj} EDS 1
#dti_diffeomorphic_sn ${template} ${subj_aff} \
#${mask} 6 0.002
speed=slow

if [[ ${speed} == "fast" ]]; then 

# fast
# in case of existing diffeomorphic template use ftol = 0.005 and useTrans = 1
echo "perform rigid registration"
sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_rigid_reg_slurm.sh ${template} ${subjects} 0.005 1 0
# in case of existing diffeomorphic template use ftol = 0.001, useTrans = 1, coarse = 0
echo "perform affine registration"
sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_affine_reg_slurm.sh ${template} ${subjects} 0.001 1 0
# same settings as for inter reg

base=${subjects%.txt*}
ls -1 *dtitk_aff.nii.gz > ${base}_aff.txt

subjects_aff=${base}_aff.txt 
echo "perform diffeomorphic registration"
sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_diffeomorphic_reg_slurm.sh ${template} ${subjects_aff} ${mask} 1 6 0.002

mv ${workdir}/*.log ${workdir}/logs

elif [[ ${speed} == "slow" ]]; then
## slow 
dti_rigid_sn ${template} # mean_initial.nii.gz ??? ${subjects} EDS
dti_affine_sn ${template} ${subjects} EDS 1
ls -1 DWI_*_dtitk_aff.nii.gz > subjects_aff.txt
dti_diffeomorphic_sn \
${template} subjects_aff \
${mask} 6 0.002
fi



for scan in $(cat ${subjects}); do 
base=${scan%.nii.gz*}
temp=${scan%_b0_b1000_dtitk.nii.gz*}
subj=${temp#DWI_*}
dfRightComposeAffine -aff ${base}.aff  -df ${base}_aff_diffeo.df.nii.gz -out ${subj}_native2template_combined.df.nii.gz
deformationSymTensor3DVolume -in ${scan} 
-target ${template} -trans ${subj}_native2template_combined.df.nii.gz \
-out ${subj}_2templatespace.dtitk.nii.gz \
-vsize 1 1 1
done 

# clean up 
if test ${cleanup} -eq 1; then 
# clean up 
 rm *.aff *diffeo.df.nii.gz *_diffeo.nii.gz

fi

