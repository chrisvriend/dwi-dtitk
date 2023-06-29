#!/bin/bash 

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 3c-DTITK_warpqc.sh
   
   WIP
   

    Usage: ./3c-DTITK_warpqc.sh warpdir
    Obligatory: 
    warpdit = full path to directory with subject/time-point specific files warped
    to the group template (with 1x1x1 mm voxels)
    
EOF
    exit 1
}

[ _$1 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.6.5

warpdir=${1}

echo "make overlays for quality inspection"
cd ${warpdir}

ls -1 *res-?mm_dtitk.nii.gz > subjs_warped.txt
TVMean -in subjs_warped.txt -out mean_final_high_res.nii.gz
TVEigenSystem -in mean_final_high_res.nii.gz -type FSL 
mv mean_final_high_res_L3.nii.gz mean_final_high_res_regcheck.nii.gz
rm mean_final_high_res_??.nii.gz
# make pngs of overlay with slicer for QC
mkdir -p ${warpdir}/QC

for subj in $(cat subjs_warped.txt); do
  stem=${subj%_space-template_desc-b1000*}
  stam=${subj%.nii.gz*}
  echo "--------"
  echo ${stem}
  echo "--------"

  TVEigenSystem -in ${subj} -type FSL
  slicer mean_final_high_res_regcheck.nii.gz ${stam}_L3 -a ${warpdir}/QC/${stem}_overlay.png
  rm ${stam}_??.nii.gz
done
