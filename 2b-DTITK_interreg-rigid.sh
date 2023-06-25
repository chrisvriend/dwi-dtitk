#!/bin/bash

# update usage info
# run this script from within interactive session as ./2b-DTITK_interreg-rigid.sh path-to-interreg-folder

# works but might be too fast to use sbatch for: takes longer to schedule than run

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl


# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 2b-DTITK_interreg_rigid.sh
   
   WIP
   

    Usage: ./2b-DTITK_interreg-rigid.sh workdir scriptdir template subjects simultaneous
    Obligatory: 
    headdir = full path to (head) directory where all folders are stored, 
	including the subject folders and scripts directory (that includes this script)
    
EOF
    exit 1
}

[ _$4 = _ ] && Usage



#########################################
# Setup relevant software and variables
#########################################
module load dtitk/2.3.1
module load fsl/6.0.5.1
. ${DTITK_ROOT}/scripts/dtitk_common.sh




# Sets up variables for folder with tensor images from all subjects and recommended template from DTI-TK
workdir=${1}
scriptdir=${2}
template=${3} # ixi template
subjects=${4} # inter_subjects.txt
simul=${5}


#########################################
# Creates intial group template from within-subject templates
#########################################
# lengthscale is defined in dtitk_common.sh
sep_coarse=$(echo ${lengthscale}*4 | bc -l)
sep_fine=$(echo ${lengthscale}*2 | bc -l)
smoption=EDS # default
export DTITK_USE_QSUB=0


if [ "${DTITK_RIGID_FINE}" -eq 1 ]; then
    countMax=2
else
    countMax=1
fi

cd ${workdir}

nsubj=$(cat ${subjects} | wc -l)

coarse=1
######################################################
# first run rigid alignment to the existing template
######################################################
if [ ! -f ${workdir}/mean_initial.nii.gz ]; then
    count=1
    while [ $count -le $countMax ]; do

        if [ $count -lt 2 ]; then
           
            echo "dti_rigid_reg - count = ${count}"
            sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_rigid_reg_slurm.sh ${template} ${subjects} 0.01 ${coarse} 

        else
            echo "dti_rigid_reg - count = ${count}"
            sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_rigid_reg_slurm.sh ${template} ${subjects} 0.005 1 ${coarse}
         
        fi
        let count=count+1
    done


    # next run affine alignment using the rigid alignment output as initialization
    count=1
    while [ $count -le $countMax ]; do

        if [ $count -lt 2 ]; then
            echo "dti_affine_reg - count = ${count}"
            sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_affine_reg_slurm.sh ${template} ${subjects} 0.01

        else
            echo "dti_affine_reg - count = ${count}"
            sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/dti_affine_reg_slurm.sh ${template} ${subjects} 0.001 1
        fi

        let count=count+1

    done

 # create the subject list file of the affine aligned subjects
    subjects_aff=dti_template_bootstrap_${RANDOM}
    for file in $(cat ${subjects}); do
        echo ${file} | sed -e 's/.nii.gz/_aff.nii.gz/'
    done >${subjects_aff}

    # compute the initial template
    TVMean -in ${subjects_aff} -out mean_initial.nii.gz
    echo "Initial bootstrapped template is computed and saved as mean_initial.nii.gz"

    # clean up
    rm -fr ${subjects_aff}



   
else
    echo "bootstrapped template already exists"

fi