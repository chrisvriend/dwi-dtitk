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

##disabled##SBATCH --array 1-11%11

workdir=${1}

cd ${workdir}
QCdir=${workdir}/QC
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

scriptdir=${workdir}/scripts
bshell=1000
Niter=5
export DTITK_USE_QSUB=0

echo "-------"
echo ${subj}
echo "-------"

#########################################
# DWI split
#########################################

cd ${workdir}/${subj}

if [ ! -f ${workdir}/${subj}/DWI_${subj}_b0_b1000_dtitk.nii.gz ]; then

    for d in vol_b0 b0_b1000; do

        mkdir -p ${d}
    done

    # create brainmask
    if [ ! -f nodif_brainmask.nii.gz ]; then
        echo "create brain mask"
        fslroi data dwinodif 0 2
        fslmaths dwinodif -Tmean nodif
        ${synthstrip} -i ${workdir}/${subj}/nodif.nii.gz \
            -m ${workdir}/${subj}/nodif_brainmask.nii.gz

        # synthstrip does something weird to the header that leads to
        # warning messages in the next step. Therefore we clone the header
        # from the input image
        fslcpgeom ${workdir}/${subj}/nodif.nii.gz \
            ${workdir}/${subj}/nodif_brainmask.nii.gz

    fi
    slicer nodif nodif_brainmask -a ${workdir}/QC/${subj}_maskQC.png

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
        dtifit -k b0_b${l} -m *mask* -r *bvec* -b *bvals* -o DWI_${subj}_b0_b${l} --sse
        cd ..

        #########################################
        # Make dtifit’s dti_V{123} and dti_L{123} compatible with DTI-TK
        #########################################
        cd ${workdir}/${subj}/b0_b${l}

        if [ ! -f ${workdir}/${subj}/DWI_${subj}_b0_b${l}_dtitk.nii.gz ]; then
            fsl_to_dtitk DWI_${subj}_b0_b${l}
            rm -f *nonSPD.nii.gz *norm.nii.gz
        mv DWI_${subj}_b0_b${l}_dtitk.nii.gz \
        ${workdir}/${subj}/DWI_${subj}_b0_b${l}_dtitk.nii.gz
        fi
        
        rm ${workdir}/${subj}/vol*.nii.gz
    done

fi

echo
echo "DONE converting data to DTITK format"
echo "for subject = ${subj}"
echo

##########################################################################
