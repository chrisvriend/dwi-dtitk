#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# wrapper script for DTI-TK template creation
# run this script from within an interactive slurm session.
# Expect between 8-12 hours of processing time
# change slurm partition acccordingly

# Assumed data structure

# HEAD-DIRECTORY/
# ├── sub-XXX1
# │   └── ses-Tx
# ├── sub-XXX2
# │   ├── ses-Tx
# │   │    ├── dwi/sub-XXX1_ses-Tx_dwi-space_desc-preproc_dwi|.nii.gz/.bvec/.bval
# │   │    ├── optional: dwi/sub-XXX1_ses-Tx_dwi-space_desc-desc-[isovf/odi/ndi]_noddi.nii.gz
# │   └── ses-Tx
# │   │    ├── dwi/sub-XXX2_ses-Tx_dwi-space_desc-preproc_dwi|.nii.gz/.bvec/.bval
# │   │    ├── optional: dwi/sub-XXX2_ses-Tx_dwi-space_desc-desc-[isovf/odi/ndi]_noddi.nii.gz
# ------------
#    - OR -
# ------------
# ├── sub-XXX3
#          ├──dwi/sub-XXX3_dwi-space_desc-preproc_dwi|.nii.gz/.bvec/.bval
# │   │    ├── optional: dwi/sub-XXX3_dwi-space_desc-desc-[isovf/odi/ndi]_noddi.nii.gz
# ├── sub-XXX4
#          ├──dwi/sub-XXX4_dwi-space_desc-preproc_dwi|.nii.gz/.bvec/.bval
# │   │    ├── optional: dwi/sub-XXX4_dwi-space_desc-desc-[isovf/odi/ndi]_noddi.nii.gz
# │
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

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 000-DTITK_wrapper_sbatch.sh
	Wrapper script to perform all steps from splitting the eddy-corrected DWI data
    to a single shell, perform intra and inter-person registration.

    Usage: ./000-DTITK_wrapper_sbatch.sh preprocdir workdir outputdir
    Obligatory: 
    preprocdir = full path to dwi preprocessed (e.g. eddy) output (e.g. /derivatives/dwi-preproc)
    workdir = full path to (head) working directory directory where all files will be processed, 
	including the subject folders
    
EOF
    exit 1
}

[ _$2 = _ ] && Usage


###############################
## input variables to change ##
###############################
preprocdir=${1}
workdir=${2}
outputdir=${3}
scriptdir=${PWD} # assuming that all scripts are alongside this one
ixitemplate=/data/anw/anw-gold/NP/doorgeefluik/ixi_aging_template_v3.0/template/ixi_aging_template.nii.gz

simul=7 # number of subjects to process simultaneously
Niter=5 # number of iterations for affine registration to template (default = 5)
bshell=1000

## locate data ##
cd ${preprocdir}
# change this if you want to proces only a subset of the data
ls -d sub-300?/ | sed 's:/.*::' > subjects.txt
nsubj=$(cat subjects.txt | wc -l)
#################

mkdir -p ${workdir}
cd ${workdir}
# split DWI scans, extract b1000, make DTITK compatible and perform intra-subject registration
sbatch --wait --array="01a-${nsubj}%${simul}" ${scriptdir}/01-DTITK_fit+intrareg.sh ${preprocdir} ${workdir} ${preprocdir}/subjects.txt
mkdir -p ${workdir}/logs
mv 1-DTITK*.log ${workdir}/logs
##########################################################################################
# check if all files have been converted before continuing and find subjs with 1 timepoint
##########################################################################################

${scriptdir}/01b-DTITK_checkfit.sh ${workdir}

############################################################################################
# inter-subject registration steps

if [ -z ${templatedir} ]; then 
# prepare for inter-subject registration by making a new folder and symbolic links
${scriptdir}/02a-DTITK_prepinterreg.sh ${workdir}

# perform rigid/affine inter-subject registration to make initial template
${scriptdir}/02b-DTITK_interreg-rigid.sh ${workdir}/interreg ${scriptdir} ${ixitemplate} inter_subjects.txt ${simul}

# perform affine inter-subject registration to make affine template
${scriptdir}/02c-DTITK_interreg-affine.sh ${workdir}/interreg ${scriptdir} inter_subjects.txt ${Niter} ${simul}

cd ${workdir}/interreg ; mv *.log ./logs ; ls -1 sub-*_aff.nii.gz >inter_subjects_aff.txt

# perform diffeomorphic inter-subject registration to make diffeo template
${scriptdir}/02d-DTITK_interreg-diffeo.sh ${workdir}/interreg ${scriptdir} mean_affine${Niter}.nii.gz mask.nii.gz inter_subjects_aff.txt ${simul}

# warp dtitk files from subject space to group template for each timepoint
${scriptdir}/03a-DTITK_warp2template.sh ${workdir} ${bshell}

else 
echo "using existing template in ${templatedir}"
${scriptdir}/03z-DTITK_reg-warp2template.sh ${workdir} ${templatedir} ${bshell}

fi 


# make QC figures of warped scans
${scriptdir}/03b-DTITK_warpqc.sh ${workdir}/warps
#############################################################################################

# extract diffusion/NODDI maps
${scriptdir}/004-DTITK_makediffmaps.sh ${workdir} ${bshell}

# make skeleton image and skeletonized diffusion maps
ln -sf ${workdir}/warps/mean_final_high_res.nii.gz ${workdir}/diffmaps/mean_final_high_res.nii.gz
${scriptdir}/005-DTITK_TBSS.sh ${workdir}/diffmaps 

# warp JHU-ICBM atlas tracts to group template and extract several tracts
sbatch --wait ${scriptdir}/006-DTITK_warpatlas2template.sh ${workdir} ${scriptdir}/JHU-ICBM.labels

# produce tractfile that contains all tracts.
# manually adjust if you  only want to consider a specific set of tracts.
cd ${workdir}/tracts
ls -1 JHU*.nii.gz > tractfile.txt
sed -i '/JHU-ICBM-labels_templatespace.nii.gz/d' ./tractfile.txt
sed -e s/.nii.gz//g -i * ./tractfile.txt

cd ${workdir}
###########################################################################################
# extract median diff values
${scriptdir}/007-DTITK_extract-diffvalues.sh ${workdir} ${workdir}/tracts/tractfile.txt ${scriptdir}

###########################################################################################
# write to output directory

${scriptdir}/008-DTITK_write-output.sh ${workdir} ${outputdir}

#############
### DONE ####
#############
echo "DONE"
echo "final output for statistical analysis can be found in ${workdir}/diffvalues"
echo "do not forget to visual inspect the registrations to the templates and skeletonization"
