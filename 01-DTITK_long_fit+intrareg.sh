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
   

    Usage: ./01-DTITK_long_fit+intrareg.sh headdir
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

for time in $(ls -d T?); do

    if [ ! -f ${headdir}/${subj}/DWI_${subj}_${time}_b0_b1000_dtitk.nii.gz ]; then

        cd ${headdir}/${subj}/${time}

        echo "...${time}"
        for d in vol_b0 b0_b1000; do

            mkdir -p ${d}
        done

        # create brainmask
        if [ ! -f nodif_brainmask.nii.gz ]; then
            echo "create brain mask"
            fslroi data dwinodif 0 2
            fslmaths dwinodif -Tmean nodif
            ${synthstrip} -i ${headdir}/${subj}/${time}/nodif.nii.gz \
                -m ${headdir}/${subj}/${time}/nodif_brainmask.nii.gz

            # synthstrip does something weird to the header that leads to
            # warning messages in the next step. Therefore we clone the header
            # from the input image
            fslcpgeom ${headdir}/${subj}/${time}/nodif.nii.gz \
                ${headdir}/${subj}/${time}/nodif_brainmask.nii.gz

        fi
        slicer nodif nodif_brainmask -a ${headdir}/QC/${subj}_${time}_maskQC.png

        echo "split DWI nifti"
        fslsplit data.nii.gz

        columns_b0=$(${scriptdir}/get_column_idx_in_range.py bvals 0 10)
        for i in ${columns_b0}; do
            mv vol$(printf "%04d\n" ${i}).nii.gz vol_b0
        done
        ${scriptdir}/copy_columns.py bvals bvecs_0 ${columns_b0}
        ${scriptdir}/copy_columns.py bvecs bvecs_0 ${columns_b0}

        for l in 1000; do

            echo "b${l}:"
            columns=$(${scriptdir}/get_column_idx_in_range.py bvals $((l - 20)) $((l + 20)))

            for i in ${columns}; do
                mv vol$(printf "%04d\n" $i).nii.gz b0_b${l}
            done
            sorted_columns=$(for i in ${columns_b0} ${columns}; do echo $i; done | sort -n)

            #echo ${sorted_columns}

            ${scriptdir}/copy_columns.py bvals bvals_${l} ${sorted_columns}
            ${scriptdir}/copy_columns.py bvecs bvecs_${l} ${sorted_columns}

            mv bvals_${l} b0_b${l}
            mv bvecs_${l} b0_b${l}

            cp nodif_brainmask.nii.gz b0_b${l}
            cp vol_b0/* b0_b${l}

            cd b0_b${l}

            fslmerge -a b0_b${l} vol*
            rm -f vol*

            #########################################
            # dtifit
            #########################################
            # run dtifit for each of the combinations

            echo "commence dtifit on b0_b${l}"
            dtifit -k b0_b${l} -m *mask* -r *bvec* -b *bvals* -o DWI_${subj}_${time}_b0_b${l} --sse
            cd ..

            #########################################
            # Make dtifit’s dti_V{123} and dti_L{123} compatible with DTI-TK
            #########################################
            cd ${headdir}/${subj}/${time}/b0_b${l}

            if [ ! -f ${headdir}/${subj}/DWI_${subj}_${time}_b0_b${l}_dtitk.nii.gz ]; then

                fsl_to_dtitk DWI_${subj}_${time}_b0_b${l}
                mv DWI_${subj}_${time}_b0_b${l}_dtitk.nii.gz ${headdir}/${subj}
                rm -f *nonSPD.nii.gz *norm.nii.gz
            fi
            rm ${headdir}/${subj}/${time}/vol*.nii.gz
        done

    fi
    echo
    echo "done with timepoint = ${time} "
    echo
done
echo
echo "DONE converting data to DTITK format"
echo "for subject = ${subj}"
echo


##########################################################################
echo
echo "continue with intra-subject registration"
echo

cd ${headdir}/${subj}

ls -1 *dtitk.nii.gz > ${subj}.txt

# only necessary to perform these steps if there is more than 1 timepoint
if test $(cat ${subj}.txt | wc -l) -gt 1; then

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
    cd ${headdir}/${subj}
    for session in $(ls -d T?); do
        if [ ! -f DWI_${subj}_${session}_combined.df.nii.gz ]; then
            echo "Making non-linear transform for timepoint ${session}"

            dfRightComposeAffine -aff DWI_${subj}_${session}_b0_b1000_dtitk.aff \
                -df DWI_${subj}_${session}_b0_b1000_dtitk_aff_diffeo.df.nii.gz \
                -out DWI_${subj}_${session}_combined.df.nii.gz

        else
            echo "Transform to subject-specific template already exists"
        fi

        #########################################
        # Warps individual timepoint to subject-specific template
        #########################################

        if [ ! -f ${subj}_${session}_combined.nii.gz ]; then
            echo "warping ${session} timepoint to subject-specific template"
            deformationSymTensor3DVolume -in DWI_${subj}_${session}_b0_b1000_dtitk.nii.gz \
                -trans DWI_${subj}_${session}_combined.df.nii.gz -target ${subj}_mean_initial.nii.gz \
                -out ${subj}_${session}_combined.nii.gz
        else
            echo "Warped timepoint to subject-specific template already exists for ${session}"
        fi

    done

    #########################################
    # Calculates mean image for both time points in subject-template space
    #########################################

    if [ ! -f ${subj}_mean_intra_template.nii.gz ]; then
        echo
        echo "creating mean image of time points in subject-specific template space"
        echo
        ls -1 ${subj}_T*_combined.nii.gz > ${subj}_intra_reg_volumes.txt
        TVMean -in ${subj}_intra_reg_volumes.txt -out ${subj}_mean_intra_template.nii.gz
    else
        echo "mean image of timepoints in subject-specific template space already exists"
    fi

# clean up
if [ -f ${subj}_mean_intra_template.nii.gz ]; then 
rm -f mean_affine*.nii.gz mean_diffeomorphic_initial*.nii.gz \
${subj}_mean_affine${Niter}_tr.nii.gz

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
	cd ${headdir}

else

    echo "${subj} has only a single timepoint; skipping intra-subject registration"
fi

echo
echo "DONE with intra-subject registration"
echo "of subject = ${subj}"

