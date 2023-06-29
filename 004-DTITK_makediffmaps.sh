#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
  cat <<EOF

    (C) C.Vriend - 2/3/2023 - 04-DTITK_makediffmaps.sh
    extract AD,FA,MD,RD diffusion maps from the DTITK images in templatespace and warps NODDI maps (OD,ND,FW) to template space 
    and adds those maps to one subject-specific 4D diffusion image with all 7 maps.
    
   
    Usage: ./04-DTITK_makediffmaps.sh workdir bshell
    Obligatory: 
    workdir = full path to working (head) directory where all folders are situated, including the subject folders (see wrapper script)
    bshell = shell to process (e.g. 1000)
    
EOF
  exit 1
}

[ _$2 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.6.5

echo "extract diffusion measures"

workdir=${1}
bshell=${2}

warpdir=${workdir}/warps
regdir=${workdir}/interreg
diffdir=${workdir}/diffmaps
mkdir -p ${diffdir}
tempdir=${workdir}/NODDItemp
mkdir -p ${tempdir}

cd ${warpdir}

for scan in $(ls -1 *_res-?mm_dtitk.nii.gz); do

  subj_session=${scan%_space-template_desc-b${bshell}*}

  subj=${subj_session%_ses-*}
  session=${subj_session#${subj}_*}

  if [ -z ${session} ]; then
    sessionpath=/
    sessionfile=_
  else
    sessionpath=/${session}/
    sessionfile=_${session}_

  fi

  if [ ! -f ${diffdir}/${subj_session}_space-template_desc-diffmaps_res-1mm_dtitk.nii.gz ]; then
    echo
    echo ${subj_session}
    base=$(remove_ext ${scan})

    for diff in fa ad rd tr; do
      echo " | ${diff} | "
      TVtool -in ${warpdir}/${scan} -${diff}
      mv ${warpdir}/${base}_${diff}.nii.gz ${diffdir}/${subj_session}_${diff^^}.nii.gz
    done
    fslmaths ${diffdir}/${subj_session}_TR.nii.gz \
      -div 3 ${diffdir}/${subj_session}_MD.nii.gz
    rm ${diffdir}/${subj_session}_TR.nii.gz

    # #############################################
    # Warp individual NODDI maps to same template
    # #############################################
    # http://dti-tk.sourceforge.net/pmwiki/pmwiki.php?n=Documentation.OptionspostReg

    if [ -d ${workdir}/${subj}/${session}/dwi ]; then
      echo "longitudinal data"
      dwidir=${workdir}/${subj}/${session}/dwi

    elif [ -d ${workdir}/${subj}/dwi ]; then
      echo "cross-sectional data"
      dwidir=${workdir}/${subj}/dwi
    else
      echo "ERROR! cannot find dwi folder in either ${subj} or ${session} subfolder"
      continue

    fi

    if [ -f ${dwidir}/${subj_session}_space-dwi_desc-ndi_noddi.nii.gz ] &&
      [ -f ${dwidir}/${subj_session}_space-dwi_desc-odi_noddi.nii.gz ] &&
      [ -f ${dwidir}/${subj_session}_space-dwi_desc-isovf_noddi.nii.gz ]; then
      echo "NODDI output available"

      # make DTI-TK compatible
      for NODDI in odi isovf ndi; do 
      echo " | ${NODDI} | "

      SVAdjustVoxelspace -in ${dwidir}/${subj_session}_space-dwi_desc-${NODDI}_noddi.nii.gz \
        -out ${tempdir}/${subj_session}_${NODDI}_dtitk.nii.gz -origin 0 0 0

      # warp NODDI to dtitk template and reslice to 1mm3
      if [ -f ${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz ]; then
        warpfile=${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz
      else
        echo "ERROR! no warp file found for ${subj_session}"
        continue
      fi
     
        deformationScalarVolume \
          -in ${tempdir}/${subj_session}_${NODDI}_dtitk.nii.gz \
          -trans ${warpfile} \
          -target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
          -out ${diffdir}/${subj_session}_${NODDI}.nii.gz -vsize 1 1 1
        rm ${tempdir}/*.nii.gz
      done
      unset warpfile
    else
      echo
      echo "${subj_session} has no noddi output"
      echo

    fi
    echo
    echo "merge diffusion maps"
    cd ${diffdir}
    if [ -f ${subj_session}_odi.nii.gz ]; then
      # AD FA MD RD OD ND FW

      diffs=(${subj_session}_AD.nii.gz ${subj_session}_FA.nii.gz ${subj_session}_MD.nii.gz ${subj_session}_RD.nii.gz ${subj_session}_odi.nii.gz ${subj_session}_ndi.nii.gz ${subj_session}_isovf.nii.gz)
    else
      # AD FA MD RD
      diffs=(${subj_session}_AD.nii.gz ${subj_session}_FA.nii.gz ${subj_session}_MD.nii.gz ${subj_session}_RD.nii.gz)

    fi
    fslmerge -t ${diffdir}/${subj_session}_space-template_desc-diffmaps_res-1mm_dtitk $(echo ${diffs[@]})
    rm -f ${diffdir}/${subj_session}_??.nii.gz ${diffdir}/${subj_session}_???.nii.gz ${diffdir}/${subj_session}_?????.nii.gz
    unset diffs
  else
    echo "${subj} | diffusion already extracted"
  fi
  echo " ______________________________________ "
done

rm -r ${tempdir}
