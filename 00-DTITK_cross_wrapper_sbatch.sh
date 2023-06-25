#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# wrapper script for DTI-TK template creation
# Run time scales with sample size.
# 50 subject:s ~ 8-12 hours of processing time
# change slurm partition acccordingly

# Assumed data structure according bids

# BIDS-DIRECTORY/
# ├── sub-XXX1
#            ├──dwi/sub-XXX1_dwi-space_desc-preproc_dwi|.nii.gz/.bvec/.bval
# ├── sub-XXX2
# ├── sub-XXX3
# ├── sub-XXX4
# ├── sub-XXX5
# │
# │── scripts # contains this script and all subscripts
# │
# │
## folders created when running the script ##
# ├── diffmaps
# ├── diffvalues == FINAL OUTPUT of csv files with median diffusivity in the tracts of interest
# ├── interreg
# ├── QC
# ├── tracts
# └── warps
#
# other inputs (located at other places)
# ── NODDIarchive - folder with the NODDI processed data (on archive)
# ── ixitemplate - path to template for initial rigid/affine registration to group template

#####################SLURM INPUTS#########################################
#SBATCH --job-name=dtitk-wrapper
#SBATCH --mem=4G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-8:00:00
#SBATCH --nice=2000
#SBATCH -o dtitk_wrapper_%a.log

###############################
## input variables to change ##
###############################
preprocdir=${1}
workdir=${2}
scriptdir=/home/anw/cvriend/my-scratch/gitrepo/DTITK_template-diffvalues
ixitemplate=/data/anw/anw-gold/NP/doorgeefluik/ixi_aging_template_v3.0/template/ixi_aging_template.nii.gz
#NODDIarchive=/data/anw/anw-archive/NP/projects/archive_OBS/analysis/DWI2022/NODDI_output

simul=2 # number of subjects to process simultaneously
Niter=5 # number of iteratiosn for affine registration to template (default = 5)
bshell=1000
cd ${preprocdir}
nsubj=$(ls -d sub-300?/ | wc -l)
ls -d sub-300?/ | sed 's:/.*::' > subjects.txt
cd ${workdir}

# split DWI scans, extract b1000, make DTITK compatible and perform intra-subject registration
sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/01-DTITK_cross_fit.sh ${preprocdir} ${workdir} ${preprocdir}/subjects.txt
mkdir -p ${workdir}/logs
mv 1-DTITK*.log ${workdir}/logs
##########################################################################################
# check if all files have been converted before continuing and find subjs with 1 timepoint
##########################################################################################
subjfolders=$(ls -d sub-*/ | sed 's:/.*::')
rm -f ${workdir}/failed.check
touch ${workdir}/failed.check

for subj in ${subjfolders}; do
    cd ${workdir}/${subj}/dwi

    if test $(ls -1 *dtitk.nii.gz | wc -l) -ne 1 ; then
        echo "${subj} was not processed correctly"
        echo "${subj}" >>${workdir}/failed.check
    fi
done

cd ${workdir}
if test $(cat ${workdir}/failed.check | wc -l) -gt 0; then
    echo "processing has STOPPED; \
some scans were not converted to DTITK-format \
check failed.check file"
    exit
else
    rm ${workdir}/failed.check
fi

## clean up ## - still needs a better look
for subj in ${subjfolders}; do
        if [ -f ${workdir}/${subj}/dwi/${subj}_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz ]; then
        rm -f ${workdir}/${subj}/dwi/${subj}_space-dwi_desc-preproc_dwi.* \
        ${workdir}/${subj}/dwi/*.mif ${workdir}/${subj}/dwi/${subj}_space-dwi_desc-preproc-b${bshell}_??.nii.gz \
        ${workdir}/${subj}/dwi/${subj}_space-dwi_desc-brain-uncorrected_mask.nii.gz \
        ${workdir}/${subj}/dwi/${subj}_space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz \
        ${workdir}/${subj}/dwi/${subj}_space-dwi_label-WM_mask.nii.gz
        fi
done

############################################################################################
# inter-subject registration steps

# prepare for inter-subject registration by making a new folder and symbolic links
${scriptdir}/2a-DTITK_cross_prepinterreg.sh ${workdir}

# perform rigid/affine inter-subject registration to make initial template
${scriptdir}/2b-DTITK_interreg-rigid.sh ${workdir}/interreg ${scriptdir} ${ixitemplate} inter_subjects.txt ${simul}

# perform affine inter-subject registration to make affine template
${scriptdir}/2c-DTITK_interreg-affine.sh ${workdir}/interreg ${scriptdir} inter_subjects.txt ${Niter} ${simul}

cd ${workdir}/interreg
ls -1 sub-*_aff.nii.gz >inter_subjects_aff.txt
mv *.log ./logs
# perform diffeomorphic inter-subject registration to make diffeo template
${scriptdir}/2d-DTITK_interreg-diffeo.sh ${workdir} mean_affine${Niter}.nii.gz mask.nii.gz \
    inter_subjects_aff.txt ${simul}

#############################################################################################
# warp images to template

# warp dtitk files from subject space to group template
${scriptdir}/03-DTITK_warp2template.sh ${workdir}

# make QC figures of warped scans
${scriptdir}/3c-DTITK_warpqc.sh ${workdir}/warps

# extract diffusion/NODDI maps

# needs complete revision!!

${scriptdir}/04-DTITK_makediffmaps.sh ${workdir} ${preprocdir}

# make skeleton image and skeletonized diffusion maps
ln -sf ${workdir}/warps/mean_final_high_res.nii.gz ${workdir}/diffmaps/mean_final_high_res.nii.gz
${scriptdir}/05-DTITK_TBSS.sh ${workdir}/diffmaps

# warp JHU-ICBM atlas tracts to group template and extract several tracts
sbatch --wait ${scriptdir}/06-DTITK_warpatlas2template.sh ${workdir} ${scriptdir}/JHU-ICBM.labels

# produce tractfile that contains all tracts.
# manually adjust if you  only want to consider a specific set of tracts.
cd ${workdir}/tracts
ls -1 JHU*.nii.gz >tractfile.txt
sed -i '/JHU-ICBM-labels_templatespace.nii.gz/d' ./tractfile.txt
sed -e s/.nii.gz//g -i * ./tractfile.txt

cd ${workdir}
###########################################################################################
# extract median diff values
${scriptdir}/07-DTITK_extract-diffvalues.sh ${workdir} ${workdir}/tracts/tractfile.txt

#############
### DONE ####
#############

echo "DONE"
echo "final output for statistical analysis can be found in ${workdir}/diffvalues"
echo "do not forget to visual inspect the registrations to the templates and skeletonization "
