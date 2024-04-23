#!/bin/bash

workdir=${1}

cd ${workdir}

rm -f ${workdir}/subjs1timepoint.txt
for subj in $(ls -d sub-*); do

    cd ${workdir}/${subj}

    if [ ! -d ${workdir}/${subj}/intra ]; then

        if [ $(find -path '*/dwi/*' -name "*desc-preproc*_dtitk.nii.gz" | wc -l 2>/dev/null) == 1 ]; then

            echo "${subj} has a single timepoint"
            echo ${subj} >>${workdir}/subjs1timepoint.txt

        else
            echo "ERROR! fsl-2-dtitk conversion failed for ${subj}"

        fi

    else

        if [ $(find -path '*/intra/*' -name "*_space-intra_template.nii.gz" | wc -l 2>/dev/null) != 1 ]; then

            echo "ERROR! intra-subject reg failed for ${subj}"

        fi

    fi

done
