#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

#SBATCH --job-name=dtitk-dtifit
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-1:15:00
#SBATCH --nice=2000
#SBATCH -o 1-DTITK_%A_%a.log


# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 01-DTITK_cross_fit.sh
    THIS SCRIPT IS FOR SAMPLES WITH cross-SECTIONAL DATA (I.E. 1 TIMEPOINT)
	Perform DWI split to b1000 and convert to DTITK compatible format for subsequent
    inter-subject registration 

    Usage: ./01-DTITK_cross_fit.sh headdir
    Obligatory: 
    headdir = full path to (head) directory where all folders are stored, 
	including the subject folders and scripts directory (that includes this script)
    
EOF
    exit 1
}

[ _$1 = _ ] && Usage




headdir=${1}

cd ${headdir}
QCdir=${headdir}/QC
mkdir -p ${QCdir}
ls -d sub-*/ | sed 's:/.*::' >subjects.txt
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" subjects.txt)

#########################################
# Setup relevant software and variables
#########################################
module load dtitk/2.3.1
module load fsl/6.0.5.1
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python_env/mrtrix
synthstrip=/data/anw/anw-gold/NP/doorgeefluik/container_apps/synthstrip.1.2.sif
ixitemplate=/data/anw/anw-gold/NP/doorgeefluik/ixi_aging_template_v3.0/template
###

# Sets up variables for folder with tensor images from all subjects and recommended template from DTI-TK

scriptdir=${headdir}/scripts
bshell=1000
Niter=5
export DTITK_USE_QSUB=0

echo "-------"
echo ${subj}
echo "-------"

#########################################
# DWI split
#########################################

cd ${headdir}/${subj}

if [ ! -f ${headdir}/${subj}/DWI_${subj}_b0_b1000_dtitk.nii.gz ]; then

    # create brainmask
    if [ ! -f nodif_brainmask.nii.gz ]; then
        echo "create brain mask"
        fslroi data dwinodif 0 2
        fslmaths dwinodif -Tmean nodif
        ${synthstrip} -i ${headdir}/${subj}/nodif.nii.gz \
            -m ${headdir}/${subj}/nodif_brainmask.nii.gz

        # synthstrip does something weird to the header that leads to
        # warning messages in the next step. Therefore we clone the header
        # from the input image
        fslcpgeom ${headdir}/${subj}/nodif.nii.gz \
            ${headdir}/${subj}/nodif_brainmask.nii.gz
    fi

    slicer nodif nodif_brainmask -a ${headdir}/QC/${subj}_maskQC.png
    # extract b0 and b1000 shell
    dwiextract data.nii.gz b0b1000.nii.gz -fslgrad bvecs bvals -shells 0,1000 \
    -export_grad_fsl b1000.bvec b1000.bval 

        #########################################
        # dtifit
        #########################################
        dtifit -k b0b1000 -m *mask* -r b1000.bvec -b b1000.bval -o DWI_${subj}_b0_b1000 --sse
        rm b0b1000.nii.gz b1000.bvec b1000.bval
        #########################################
        # Make dtifit’s dti_V{123} and dti_L{123} compatible with DTI-TK
        #########################################
        if [ ! -f ${headdir}/${subj}/DWI_${subj}_b0_b1000_dtitk.nii.gz ]; then
            fsl_to_dtitk DWI_${subj}_b0_b1000
            rm -f *nonSPD.nii.gz *norm.nii.gz
        mv DWI_${subj}_b0_b1000_dtitk.nii.gz \
        ${headdir}/${subj}/DWI_${subj}_b0_b1000_dtitk.nii.gz
        fi
fi

echo
echo "DONE converting data to DTITK format"
echo "for subject = ${subj}"
echo

##########################################################################
