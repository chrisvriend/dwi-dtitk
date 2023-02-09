#!/bin/bash 

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl


#########################################
# Setup relevant software and variables
#########################################
module load dtitk/2.3.1
module load fsl/6.0.5.1

. ${DTITK_ROOT}/scripts/dtitk_common.sh

# Sets up variables for folder with tensor images from all subjects and recommended template from DTI-TK
headdir=${1}
workdir=${headdir}/interreg
scriptdir=${headdir}/scripts
subjects=${2} # inter_subjects.txt
Niter=${3}
simul=${4}

export DTITK_USE_QSUB=0

#########################################
# Creates intial group template from within-subject templates
#########################################
# defined in dtitk_common.sh
sep_coarse=$(echo ${lengthscale}*4 | bc -l)
sep_fine=$(echo ${lengthscale}*2 | bc -l)
smoption=EDS

if [ "${DTITK_RIGID_FINE}" -eq 1 ]; then
    countMax=2
else
    countMax=1
fi

cd ${workdir}

nsubj=$(cat ${subjects} | wc -l)

#########################################
# Create affine (linear) warps for each subject to group template
#########################################
log=dti_affine_population.log
echo "command: " $* | tee ${log}
date | tee -a ${log}

if [ ! -f mean_affine${Niter}.nii.gz ]; then

    echo "Running affine registration to initial template"
    cp ${workdir}/mean_initial.nii.gz mean_affine0.nii.gz
    subjects_aff=$(echo ${subjects} | sed -e 's/.txt/_aff.txt/')
    rm -fr ${subjects_aff}
    rm -fr affine.txt
    for subjid in $(cat ${subjects}); do
	pref=$(remove_ext ${subjid})
	echo ${pref}_aff.nii.gz >> ${subjects_aff}
	echo ${pref}.aff >> affine.txt
    done


    count=1
    while [ $count -le $Niter ]; do
        echo "dti_affine_population iteration" ${count} | tee -a ${log}
        let oldcount=count-1

        template=mean_affine${oldcount}.nii.gz
        sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_affine_reg_slurm.sh ${template} ${subjects} 0.01 1

        affine3DShapeAverage affine.txt mean_affine${oldcount}.nii.gz average_inv.aff 1

        for aff in $(cat affine.txt); do
            affine3Dtool -in ${aff} -compose average_inv.aff -out ${aff}
            subjid=$(echo ${aff} | sed -e 's/.aff//')

         	affineSymTensor3DVolume -in ${subjid}.nii.gz -trans ${aff} \
            -target mean_affine${oldcount}.nii.gz -out ${subj}_aff.nii.gz

        done
	    rm -fr average_inv.aff
		
        TVMean -in ${subjects_aff} -out mean_affine${count}.nii.gz
	    TVtool -in mean_affine${oldcount}.nii.gz -sm mean_affine${count}.nii.gz \
        -SMOption ${smoption} | grep Similarity | tee -a ${log}

        let count=count+1

    done
mkdir -p ${workdir}/logs
mv inter_affine*.log ${workdir}/logs


else

    echo "Affine registrations and mean_affine${Niter} already exists"
fi


#########################################
# Create mask of initial template to exclude voxels outside the brain
#########################################

if [ ! -f mask.nii.gz ]; then
	echo "Creating binary mask of mean_affine template"
	TVtool -in mean_affine${Niter}.nii.gz -tr
	BinaryThresholdImageFilter mean_affine${Niter}_tr.nii.gz mask.nii.gz 0.01 100 1 0
else
	echo "Binary mask already exists"
fi