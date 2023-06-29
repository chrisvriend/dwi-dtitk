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

    (C) C.Vriend - 2/3/2023 - 01-DTITK_long_fit+intrareg.sh
    THIS SCRIPT IS FOR SAMPLES WITH LONGITUDINAL DATA (I.E. >2 TIMEPOINTS)
	Perform DWI split to b1000, convert to DTITK compatible format and register 
    DWI data from >2 timepoints to one common intra-subject template. 

    note that if the sample also contains subjects with data at one timepoint 
    (due to missing data) then all steps except intra-subject registration will
    still be performed.
   

    Usage: ./01-DTITK_long_fit+intrareg.sh workdir
    Obligatory: 
    workdir = full path to (head) directory where all folders are stored, 
	including the subject folders and scripts directory (that includes this script)
    
EOF
    exit 1
}

[ _$3 = _ ] && Usage

preprocdir=${1}
workdir=${2}
subjects=${3}
threads=2
bshell=1000

QCdir=${workdir}/QC
mkdir -p ${QCdir}
cd ${bidsdir}
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" ${subjects})
# random delay
duration=$((RANDOM % 40 + 2))
echo "INITIALIZING..."
sleep ${duration}

#########################################
# Setup relevant software and variables
#########################################
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python-env/mrtrix
module load dtitk/2.3.1
module load fsl/6.0.6.5
module load ANTs/2.4.1
synthstrip=/data/anw/anw-gold/NP/doorgeefluik/container_apps/synthstrip.1.2.sif
ixitemplate=/data/anw/anw-gold/NP/doorgeefluik/ixi_aging_template_v3.0/template

###

# Sets up variables for folder with tensor images from all subjects and recommended template from DTI-TK
Niter=5
export DTITK_USE_QSUB=0

echo "-------"
echo ${subj}
echo "-------"

for dwidir in ${preprocdir}/${subj}/{,ses*/}dwi; do
    if [ ! -d ${dwidir} ]; then
        continue
    fi
    sessiondir=$(dirname ${dwidir})

    # if [[ $(ls ${sessiondir}/dwi/*dwi.nii.gz | wc -l) -gt 1 ]]; then
    #     echo -e "${RED}ERROR! this script cannot handle >1 dwi scan per session${NC}"
    #     echo -e "${RED}exiting script${NC}"
    #     exit
    # fi

    session=$(echo "${sessiondir}" | grep -oP "(?<=${subj}/).*")
    if [ -z ${session} ]; then
        sessionpath=/
        sessionfile=_
    else
        sessionpath=/${session}/
        sessionfile=_${session}_

    fi

    mkdir -p ${workdir}/${subj}${sessionpath}
    rsync -av ${preprocdir}/${subj}${sessionpath}dwi ${workdir}/${subj}${sessionpath}

    mkdir -p ${workdir}/${subj}${sessionpath}figures

    cd ${workdir}/${subj}${sessionpath}dwi

    #########################################
    # DWI shell split
    #########################################

    if [ ! -f ${subj}${sessionfile}space-dwi_desc-b${bshell}_dtitk.nii.gz ]; then

        if [ ! -f ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz ]; then
            echo "creating brain mask"
            # create brainmask
            dwiextract -nthreads ${threads} \
                ${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz - -bzero \
                -fslgrad ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec \
                ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval | mrmath - mean ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz -axis 3 -force
            # skullstrip mean b0 (nodif_brain)
            apptainer run --cleanenv ${synthstrip} \
                -i ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
                -o ${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz \
                --mask ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz

            # synthstrip does something weird to the header that leads to
            # warning messages in the next step. Therefore we clone the header
            # from the input image
            fslcpgeom ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
                ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz
            slicer ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
                ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
                -a ${workdir}/${subj}${sessionpath}figures/${subj}${sessionfile}maskQC.png
        fi

        mrconvert ${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz \
            -fslgrad ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec \
            ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval \
            ${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif

        dwibiascorrect ants ${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif \
            ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif -nthreads ${threads} \
            -bias ${subj}${sessionfile}space-dwi_desc-biasest_dwi.mif \
            -scratch ${workdir}/${subj}${sessionpath}tempbiascorrect

        # extract b0 and b${bshell} shell
        dwiextract ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif \
            b0b${bshell}.mif -shells 0,${bshell}
        mrconvert b0b${bshell}.mif ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz \
            -export_grad_fsl b${bshell}.bvec b${bshell}.bval -force

        #########################################
        # dtifit
        #########################################

        if [ ! -f ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_FA.nii.gz ]; then
            echo -e "${BLUE}dtifit on b${bshell} shell${NC}"

            dtifit -k ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dwi.nii.gz \
                -m ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
                -r b${bshell}.bvec -b b${bshell}.bval \
                -o ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell} --sse
            rm b${bshell}.bv* b0b${bshell}.mif
        fi

        #########################################
        # Make dtifit’s dti_V{123} and dti_L{123} compatible with DTI-TK
        #########################################
        if [ ! -f ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz ]; then
            fsl_to_dtitk ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}
            rm -f *nonSPD.nii.gz *norm.niisub-TIPICCO002_ses-T0_space-dwi_desc-b1000_dtitk.nii.gz.gz *norm_non_outliers.nii.gz
        fi

    fi
    echo
    echo "done with timepoint = ${session} "
    echo

    # clean up
    rm -f ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_??.nii.gz *.mif \
        ${subj}${sessionfile}space-dwi_desc-preproc_dwi.* ${subj}${sessionfile}space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz

    mkdir -p ${workdir}/${subj}/intra
    cd ${workdir}/${subj}/intra

    ln -sf ..${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz \
        ${subj}${sessionfile}space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz
done
echo
echo "DONE converting data to DTITK format"
echo

# cd ${workdir}/${subj}/intra
# ls -1 *space-dwi_desc-b${bshell}_dtitk.nii.gz  > singlescans.txt
# done

##########################################################################

cd ${workdir}/${subj}/intra

ls -1 *desc-preproc-b${bshell}_dtitk.nii.gz >${subj}.txt

# only necessary to perform these steps if there is more than 1 timepoint
if test $(cat ${subj}.txt | wc -l) -gt 1; then
    echo
    echo "continue with intra-subject registration"
    echo

    #########################################
    # Performs initial construction of the subject-specific template
    #########################################

    if [ ! -f ${subj}_mean_initial.nii.gz ]; then
        echo "running intial template construction"
        dti_template_bootstrap ${ixitemplate}/ixi_aging_template.nii.gz ${subj}.txt EDS
        mv mean_initial.nii.gz ${subj}_mean_initial.nii.gz
    else
        echo "template bootstrapping has already been run"
    fi

    #########################################
    # Performs first affine (linear) registration of subject images to subject-specific template (named ${subj}_mean_affine3.nii.gz)
    #########################################
    Nitermin=$(expr ${Niter} - 1)

    if [ ! -f ${subj}_mean_affine${Niter}.nii.gz ]; then
        echo "running affine registration to initial template"
        dti_affine_population ${subj}_mean_initial.nii.gz ${subj}.txt EDS ${Niter}
        mv mean_affine${Niter}.nii.gz ${subj}_mean_affine${Niter}.nii.gz
    else
        echo "affine registration has already been run"
    fi

    # Creates a binary mask of the affine subject-specific template
    if [ ! -f ${subj}_mask.nii.gz ]; then
        echo "making binary mask for intial template construction"
        TVtool -in ${subj}_mean_affine${Niter}.nii.gz -tr
        BinaryThresholdImageFilter ${subj}_mean_affine${Niter}_tr.nii.gz \
            ${subj}_mask.nii.gz 0.01 100 1 0
    else
        echo "binary mask has already been made"
    fi

    #########################################
    # Improves the subject-specific template
    # and creates deformation field,
    # stores aligned volumes and puts their filenames in "{subj}_aff_diffeo.txt"
    #########################################

    if [ ! -f ${subj}_diffeomorphic.nii.gz ]; then
        echo "making diffeomorphic warps"
        dti_diffeomorphic_population ${subj}_mean_affine${Niter}.nii.gz \
            ${subj}_aff.txt ${subj}_mask.nii.gz 0.002

        mv mean_diffeomorphic_initial6.nii.gz ${subj}_diffeomorphic.nii.gz
    else
        echo "diffeomorphic warps already made"
    fi

    ##########################################
    # Creates non-linear transform from
    #individual timepoint to subject-specific template
    #########################################
    echo "Making non-linear transform for each timepoint"

    for dtitkscan in $(cat ${subj}.txt); do

        dtitkbase=$(remove_ext ${dtitkscan})

        if [[ $dtitkbase =~ sub-([[:alnum:]_-]+)_space ]]; then
            subj_session=${BASH_REMATCH[1]}
        else
            echo "ERROR! cannot determine subjID or session"
        #exit
        fi
    echo $subj_session
    echo
        if [ ! -f ${dtitkbase}_dwi-2-intra.df.nii.gz ]; then

            dfRightComposeAffine -aff ${dtitkbase}.aff \
                -df ${dtitkbase}_aff_diffeo.df.nii.gz \
                -out ${dtitkbase}_dwi-2-intra.df.nii.gz
        else
            echo "Transform to subject-specific template already exists"
        fi

        #########################################
        # Warps individual timepoint to subject-specific template
        #########################################

        if [ ! -f sub-${subj_session}_space-intra_dtitk.nii.gz ]; then
            echo "warping sub-${subj_session} timepoint to subject-specific template"
            deformationSymTensor3DVolume -in ${dtitkscan} \
                -trans ${dtitkbase}_dwi-2-intra.df.nii.gz \
                -target ${subj}_mean_initial.nii.gz \
                -out sub-${subj_session}_space-intra_dtitk.nii.gz
        else
            echo "Warped timepoint to subject-specific template already exists for sub-${subj_session}"
        fi

    done

    #########################################
    # Calculates mean image for both time points in subject-template space
    #########################################

    if [ ! -f ${subj}_mean_intra_template.nii.gz ]; then
        echo
        echo "creating mean image of time points in subject-specific template space"
        echo
        ls -1 *_space-intra_dtitk.nii.gz >${subj}_intra_reg_volumes.txt
        TVMean -in ${subj}_intra_reg_volumes.txt -out ${subj}_space-intra_template.nii.gz
    else
        echo "mean image of timepoints in subject-specific template space already exists"
    fi
    
    # clean up
    if [ -f ${subj}_space-intra_template.nii.gz ]; then
        rm -f mean_affine*.nii.gz mean_diffeomorphic_initial*.nii.gz \
            ${subj}_mean_affine${Niter}_tr.nii.gz ${subj}_intra_reg_volumes.txt

    fi

    #########################################
    # QC
    #########################################

    # check registration by comparing the warped images in
    # intra-subject template space (*combined.nii.gz) to the intra-subject template"

    # for session in T0 T2; do
    # 	overlay 1 0 ${subj}_mean_affine${Niter}.nii.gz \
    #     -a ${subj}_${session}_combined.nii.gz 2 5 ${subj}_intrareg_${session}.nii.gz
    # 	overlay 1 0 ${subj}_mean_affine${Niter}.nii.gz \
    #     -a ${subj}_${session}_combined.nii.gz 2 5 ${subj}_intrareg_${session}.nii.gz

    # 	slicer ${subj}_intrareg_${session}.nii.gz \
    #     -e 0 -L -t -a ${QCdir}/${subj}_${session}_overlay3D.png
    # 	slicer ${subj}_intrareg_${session}.nii.gz \
    #     -e 0 -L -t -A 2000 ${QCdir}/${subj}_${session}_overlayslices.png

    # 	rm ${subj}_intrareg_${session}.nii.gz
    # done
    cd ${workdir}

else

    echo "${subj} has only a single timepoint; skipping intra-subject registration"
    rm -r ${workdir}/${subj}/intra
fi

echo
echo "DONE with intra-subject registration"
echo "of subject = ${subj}"
