#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 008-DTITK_write-output.sh
   
    Usage: ./008-DTITK_write-output.sh workdir outputdir bshell keep
    Obligatory: 
    workdir = full path to working (head) directory where all folders are situated, including the subject folders (see wrapper script)
    outputdir = 
    bshell = shell of dMRI scan (e.g. 1000)

EOF
    exit 1
}

[ _$3 = _ ] && Usage

workdir=${1}
outputdir=${2}
bshell=${3}


cd ${workdir}

# perform some checks before transfering files.
if [ ! -f ${workdir}/diffmaps/mean_final_high_res.nii.gz ] \
|| [ ! -f ${workdir}/diffmaps/all_FA.nii.gz ] \
|| [ ! -f ${workdir}/ICBM2FAWarped.nii.gz ] \ 
|| [ ! -f ${workdir}/tracts/JHU-ICBM-labels_templatespace.nii.gz ] \
|| (($(ls -1 ${workdir}/diffvalues/*.csv | wc -l ) < 1 )); then 
echo
echo "ERROR! not all previous processes have been executed cleanly"
echo "check the workdir and log files"
exit
fi

for subj in $(ls -d sub-*); do

    for dwidir in ${preprocdir}/${subj}/{,ses*/}dwi; do
        if [ ! -d ${dwidir} ]; then
            continue
        fi
        sessiondir=$(dirname ${dwidir})
        session=$(echo "${sessiondir}" | grep -oP "(?<=${subj}/).*")
        if [ -z ${session} ]; then
            sessionpath=/
            sessionfile=_
        else
            sessionpath=/${session}/
            sessionfile=_${session}_

        fi

        mkdir -p ${outputdir}/${subj}${sessionpath}
        for fold in xfms tbss dtitk figures; do
            mkdir -p ${outputdir}/${subj}${sessionpath}/${fold}
        done
        rsync -a ${workdir}/diffmaps/${subj}${sessionfile}space-template_desc*_dtitk.nii.gz ${outputdir}/${subj}${sessionpath}tbss
        rsync -a ${workdir}/diffvalues/${subj}${sessionfile}diffvalues.csv ${outputdir}/${subj}${sessionpath}dtitk
        rsync -a ${workdir}/warps/${subj}${sessionfile}dwi-2-dtitktemplate.df.nii.gz ${outputdir}/${subj}${sessionpath}xfms
        rsync -a ${workdir}/warps/${subj}${sessionfile}space-template_desc-b${bshell}_res*_dtitk.nii.gz \
            ${outputdir}/${subj}${sessionpath}dtitk
        rsync -a ${workdir}/${subj}${sessionpath}figures/*.png ${workdir}/warps/QC/${subj}${sessionfile}overlay.png \
            ${workdir}/interreg/QC/${subj}*.png ${outputdir}/${subj}${sessionpath}figures

    done

done
cd ${workdir}
find -name "*.log" -exec rsync -a {} ${outputdir}/logs/ \;
rsync -a ${workdir}/tracts ${outputdir}
# turned off because these can be reproduced from the subjec-specific file
#rsync -a ${workdir}/diffmaps/all*.nii.gz ${workdir}/diffmaps/tbss/stats/*skeletonised.nii.gz ${outputdir}/tbss
rsync -a ${workdir}/diffmaps/tbss/stats/mean* ${outputdir}/templates
rsync -a ${workdir}/warps/mean_final_high_res.nii.gz ${workdir}/interreg/mask.nii.gz \
 ${workdir}/interreg/mean_diffeomorphic_initial6* ${outputdir}/templates

##################################################################
