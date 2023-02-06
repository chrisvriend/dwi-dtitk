#!/bin/bash 

module load dtitk/2.3.1
module load fsl/6.0.5.1


warpdir=${1}

echo "make overlays for quality checks"
cd ${warpdir}

ls -1 *2templatespace.dtitk.nii.gz > subjs_warped.txt
TVMean -in subjs_warped.txt -out mean_final_high_res.nii.gz
TVEigenSystem -in mean_final_high_res.nii.gz -type FSL 
mv mean_final_high_res_L3.nii.gz mean_final_high_res_regcheck.nii.gz
rm mean_final_high_res_??.nii.gz
# make pngs of overlay with slicer for QC
mkdir -p ${warpdir}/QC

for subj in $(cat subjs_warped.txt); do
  stem=${subj%_2templatespace.dtitk.nii.gz*}
  stam=${subj%.nii.gz*}
  echo ${stem}
  TVEigenSystem -in ${subj} -type FSL
  slicer mean_final_high_res_regcheck.nii.gz ${stam}_L3 -a ${warpdir}/QC/${stem}_overlay.png
  rm ${stam}_??.nii.gz
done
