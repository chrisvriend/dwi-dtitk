#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
  cat <<EOF

    (C) C.Vriend - 2/3/2023 - 04-DTITK_makediffmaps.sh
    extract AD,FA,MD,RD diffusion maps from the DTITK images in templatespace and warps NODDI maps (OD,ND,FW) to template space 
    and adds those maps to one subject-specific 4D diffusion image with all 7 maps.
    
   
    Usage: ./04-DTITK_makediffmaps.sh headdir NODDIdir
    Obligatory: 
    headdir = full path to working (head) directory where all folders are situated, including the subject folders (see wrapper script)
    NODDIdir = full path to directory with the NODDI (Watson) processed files 
    (can be on archive disk; they are temporarily synced to working directory for processing)
    
EOF
  exit 1
}

[ _$2 = _ ] && Usage

module load dtitk/2.3.1
module load fsl

echo "extract diffusion measures"

headdir=${1}
NODDIdir=${2}
warpdir=${headdir}/warps
regdir=${headdir}/interreg
diffdir=${headdir}/diffmaps
mkdir -p ${diffdir}
tempdir=${headdir}/NODDItemp
mkdir -p ${tempdir}

cd ${warpdir}

for scan in $(ls -1 *2templatespace.dtitk.nii.gz); do

  subj=${scan%_2templatespace.dtitk.nii.gz*}

  if [ ! -f ${diffdir}/${subj}_dtitk_diffusion.nii.gz ]; then

    base=$(remove_ext ${scan})
    echo ${subj}

    for diff in fa ad rd tr; do
      TVtool -in ${warpdir}/${scan} -${diff}
      mv ${warpdir}/${base}_${diff}.nii.gz ${diffdir}/${subj}_${diff^^}.nii.gz
    done
    fslmaths ${diffdir}/${subj}_TR.nii.gz -div 3 ${diffdir}/${subj}_MD.nii.gz
    rm ${diffdir}/${subj}_TR.nii.gz

    # #############################################
    # Warp individual NODDI maps to same template
    # #############################################
    # http://dti-tk.sourceforge.net/pmwiki/pmwiki.php?n=Documentation.OptionspostReg
    
    if [ ! -d ${NODDIdir}/${subj}.NODDI_Watson ]; then 
      subjbase=${subj#sub-*}

      if [ ! -d ${NODDIdir}/${subjbase}.NODDI_Watson ]; then 
      echo "ERROR! NODDI output not found for ${subj} or ${subj} in ${NODDIdir}"
      echo "exiting"
      exit 
      fi 
      else 
      subjbase=${subj}
    fi


    rsync -av --exclude "Dtifit" --exclude "FitFractions" --exclude "GridSeach" \
      --exclude "logs" ${NODDIdir}/${subjbase}.NODDI_Watson ${tempdir}
    # make DTI-TK compatible
    cd ${tempdir}
    # check and change names
    SVAdjustVoxelspace -in ${tempdir}/${subjbase}.NODDI_Watson/OD.nii.gz -out ${subj}_OD_dtitk.nii.gz -origin 0 0 0
    SVAdjustVoxelspace -in ${tempdir}/${subjbase}.NODDI_Watson/mean_fiso.nii.gz -out ${subj}_FW_dtitk.nii.gz -origin 0 0 0
    SVAdjustVoxelspace -in ${tempdir}/${subjbase}.NODDI_Watson/mean_fintra.nii.gz -out ${subj}_ND_dtitk.nii.gz -origin 0 0 0

    # warp NODDI to dtitk template and reslice to 1mm3
    if [ -f ${warpdir}/${subj}_native2template_combined.df.nii.gz ]; then
      warpfile=${warpdir}/${subj}_native2template_combined.df.nii.gz
    elif [ -f ${warpdir}/${subj}_inter_subject_combined.df.nii.gz ]; then
      warpfile=${warpdir}/${subj}_inter_subject_combined.df.nii.gz
    else
      echo "ERROR! no warp file found for ${subj}"
      exit
    fi

    for NODDI in OD ND FW; do

      deformationScalarVolume -in ${subj}_${NODDI}_dtitk.nii.gz \
        -trans ${warpfile} \
        -target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
        -out ${subj}_${NODDI}.nii.gz -vsize 1 1 1
      mv ${subj}_${NODDI}.nii.gz ${diffdir}
      rm ${subj}_${NODDI}_dtitk.nii.gz
    done
    unset warpfile

    # AD FA MD RD OD ND FW
    echo "merge diffusion maps"
    cd ${diffdir}
    fslmerge -t ${diffdir}/${subj}_dtitk_diffusion.nii.gz \
      ${subj}_AD.nii.gz \
      ${subj}_FA.nii.gz \
      ${subj}_MD.nii.gz \
      ${subj}_RD.nii.gz \
      ${subj}_OD.nii.gz \
      ${subj}_ND.nii.gz \
      ${subj}_FW.nii.gz

    rm ${diffdir}/${subj}_??.nii.gz
    rm -r ${tempdir}/${subjbase}.NODDI_Watson
  else
    echo "${subj} | diffusion already extracted"
  fi
  cd
done
rm -r ${tempdir}
