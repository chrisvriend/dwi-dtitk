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
	Perform DWI split to b${bshell} and convert to DTITK compatible format for subsequent
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
bshell=${bshell}
Niter=5
export DTITK_USE_QSUB=0

echo "-------"
echo ${subj}
echo "-------"

# transfer to workdir 
mkdir -p ${workdir}/${subj}
rsync -av ${bidsdir}/${subj}/dwi ${workdir}/${subj}

#########################################
# DWI split
#########################################
cd ${workdir}/${subj}/dwi

if [ ! -f ${headdir}/${subj}/dwi/${subj}_space-dwi_desc-b${bshell}_dtitk.nii.gz ]; then

if [ -f ${subj}_space-dwi_desc-brain_mask.nii.gz ]; then
    # create brainmask
        dwiextract -nthreads ${threads} \
            ${subj}_space-dwi_desc-preproc_dwi.nii.gz - -bzero \
            -fslgrad ${subj}_space-dwi_desc-preproc_dwi.bvec \
            ${subj}_space-dwi_desc-preproc_dwi.bval | mrmath - mean ${subj}_space-dwi_desc-nodif_dwi.nii.gz -axis 3
        # skullstrip mean b0 (nodif_brain)
        apptainer run --cleanenv ${synthstrippath} \
            -i ${subj}_space-dwi_desc-nodif_dwi.nii.gz \
            -o ${subj}_space-dwi_desc-nodif-brain_dwi.nii.gz \
            --mask ${subj}_space-dwi_desc-brain_mask.nii.gz

        # synthstrip does something weird to the header that leads to
        # warning messages in the next step. Therefore we clone the header
        # from the input image
        fslcpgeom ${subj}_space-dwi_desc-nodif_dwi.nii.gz  \
            ${subj}_space-dwi_desc-brain_mask.nii.gz   
        slicer ${subj}_space-dwi_desc-nodif_dwi.nii.gz \
        ${subj}_space-dwi_desc-brain_mask.nii.gz \
        -a ${headdir}/${subj}/figures/${subj}_maskQC.png
fi

 mrconvert ${subj}_space-dwi_desc-preproc_dwi.nii.gz \
    -fslgrad ${subj}_space-dwi_desc-preproc_dwi.bvec \
    ${subj}_space-dwi_desc-preproc_dwi.bval \
    ${subj}_space-dwi_desc-preproc_dwi.mif

 dwibiascorrect ants ${subj}_space-dwi_desc-preproc_dwi.mif \
      ${subj}_space-dwi_desc-preproc-biascor_dwi.mif -nthreads ${threads} \
      -bias ${subj}_space-dwi_desc-biasest_dwi.mif \
      -scratch ${workdir}/${subj}/tempbiascorrect

    # extract b0 and b${bshell} shell
    dwiextract ${subj}space-dwi_desc-preproc-biascor_dwi.mif \
		b0b${bshell}.mif -shells 0,${bshell}
	mrconvert b0b${bshell}.mif ${subj}_space-dwi_desc-preproc-b${bshell}_dwi.nii.gz \
		-export_grad_fsl b${bshell}.bvec b${bshell}.bval -force



        #########################################
        # dtifit
        #########################################

if [ ! -f ${subj}_space-dwi_desc-preproc-b${bshell}_FA.nii.gz ]; then
	echo -e "${BLUE}dtifit on b${bshell} shell${NC}"

        dtifit -k ${subj}_space-dwi_desc-preproc-b${bshell}_dwi.nii.gz \
		-m ${subj}_space-dwi_desc-brain_mask.nii.gz \
		-r b${bshell}.bvec -b b${bshell}.bval \
		-o ${subj}_space-dwi_desc-preproc-b${bshell} --sse
	    rm b${bshell}.bv* b0b${bshell}.mif
fi
       
        #########################################
        # Make dtifit’s dti_V{123} and dti_L{123} compatible with DTI-TK
        #########################################
        if [ ! -f ${workdir}/${subj}/dwi/${subj}_space-dwi_desc-b${bshell}_dtitk.nii.gz ]; then 
            fsl_to_dtitk ${subj}_space-dwi_desc-preproc-b${bshell}
            rm -f *nonSPD.nii.gz *norm.nii.gz
        fi
fi

echo
echo "DONE converting data to DTITK format"
echo "for subject = ${subj}"
echo

##########################################################################
