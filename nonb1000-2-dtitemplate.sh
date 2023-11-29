#!/bin/bash

dwipreprocdir=/home/anw/cvriend/my-scratch/dwi-preproc
dwidtitkdir=/home/anw/cvriend/my-scratch/dwi-dtitk

module load dtitk/2.3.1
module load fsl/6.0.6.5
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python-env/mrtrix

cd ${dwipreprocdir}
for subj in $(ls -d sub-*); do
    echo ${subj}
    for shell in 2000 3000; do
        if [ ! -f ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_dtitk.nii.gz ]; then
            echo "shell = ${shell}"
            cd ${dwipreprocdir}/${subj}/dwi
            dwiextract ${subj}_space-dwi_desc-preproc_dwi.nii.gz \
                b0b${shell}.nii.gz -fslgrad ${subj}_space-dwi_desc-preproc_dwi.bvec \
                ${subj}_space-dwi_desc-preproc_dwi.bval -shells 0,${shell} \
                -export_grad_fsl b${shell}.bvec b${shell}.bval

            dtifit -k b0b${shell} -m *mask* -r b${shell}.bvec -b b${shell}.bval -o DWI_${subj}_b0_b${shell} --sse
            rm b0b${shell}.nii.gz b${shell}.bvec b${shell}.bval

            fsl_to_dtitk DWI_${subj}_b0_b${shell}
            rm -f *nonSPD.nii.gz *norm.nii.gz

            deformationSymTensor3DVolume \
                -in DWI_${subj}_b0_b${shell}_dtitk.nii.gz \
                -trans ${dwidtitkdir}/${subj}/xfms/${subj}_dwi-2-dtitktemplate.df.nii.gz \
                -target ${dwidtitkdir}/templates/mean_diffeomorphic_initial6.nii.gz \
                -out ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_dtitk.nii.gz -vsize 1 1 1
            rm DWI_*
        fi
                cd ${dwidtitkdir}/${subj}/dtitk/

        base=$(remove_ext ${subj}_space-template_desc-b${shell}_res-1mm_dtitk.nii.gz)

        for diff in fa ad rd tr; do
            echo " | ${diff} | "
            TVtool -in ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_dtitk.nii.gz -${diff}
            mv ${base}_${diff}.nii.gz ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_${diff^^}.nii.gz
        done
        fslmaths ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_TR.nii.gz \
            -div 3 ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_MD.nii.gz
        rm ${dwidtitkdir}/${subj}/dtitk/${subj}_space-template_desc-b${shell}_res-1mm_TR.nii.gz

        diffs=(*b${shell}_res-1mm_AD.nii.gz *b${shell}_res-1mm_FA.nii.gz *b${shell}_res-1mm_MD.nii.gz *b${shell}_res-1mm_RD.nii.gz)
        fslmerge -t ${subj}_space-template_desc-b${shell}-diffmaps_res-1mm_dtitk $(echo ${diffs[@]})
        rm $(echo ${diffs[@]})
    done

done
