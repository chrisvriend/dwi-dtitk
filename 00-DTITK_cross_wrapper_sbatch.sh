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
#            ├── data.nii.gz, bvecs, bvals
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
headdir=${1}
scriptdir=${headdir}/scripts
ixitemplate=/data/anw/anw-gold/NP/doorgeefluik/ixi_aging_template_v3.0/template/ixi_aging_template.nii.gz
NODDIarchive=/data/anw/anw-archive/NP/projects/archive_OBS/analysis/DWI2022/NODDI_output

simul=12 # number of subjects to process simultaneously
Niter=5 # number of iteratiosn for affine registration to template (default = 5)

cd ${headdir}
nsubj=$(ls -d sub-*/ | wc -l)

# split DWI scans, extract b1000, make DTITK compatible and perform intra-subject registration
sbatch --wait --array="1-${nsubj}%${simul}" ${scriptdir}/01-DTITK_cross_fit.sh ${headdir}
mkdir -p ${headdir}/logs
mv 1-DTITK*.log ${headdir}/logs
##########################################################################################
# check if all files have been converted before continuing and find subjs with 1 timepoint
##########################################################################################
subjfolders=$(ls -d sub-*/ | sed 's:/.*::')
rm -f ${headdir}/failed.check
touch ${headdir}/failed.check

for subj in ${subjfolders}; do
    cd ${headdir}/${subj}

    if test $(ls -1 *dtitk.nii.gz | wc -l) -ne 1 ; then
        echo "${subj} was not processed correctly"
        echo "${subj}" >>${headdir}/failed.check
    fi
done

cd ${headdir}
if test $(cat ${headdir}/failed.check | wc -l) -gt 0; then
    echo "processing has STOPPED; \
some scans were not converted to DTITK-format \
check failed.check file"
    exit
else
    rm ${headdir}/failed.check
fi

## clean up ## - still needs a better look
for subj in ${subjfolders}; do


        cd ${headdir}/${subj}
        find -type d -name "b0_b1000" -exec rm -r {} \;
        find -type d -name "vol_b0" -exec rm -r {} \;
        if [ -f ${headdir}/${subj}/DWI_${subj}_b0_b1000_dtitk.nii.gz ]; then
            find -type f -name "data.nii.gz" -exec rm {} \;
        fi
done

############################################################################################
# inter-subject registration steps

# prepare for inter-subject registration by making a new folder and symbolic links
${scriptdir}/2a-DTITK_cross_prepinterreg.sh ${headdir}

# perform rigid/affine inter-subject registration to make initial template
${scriptdir}/2b-DTITK_interreg-rigid.sh ${headdir} ${ixitemplate} inter_subjects.txt ${simul}

# perform affine inter-subject registration to make affine template
${scriptdir}/2c-DTITK_interreg-affine.sh ${headdir} inter_subjects.txt ${Niter} ${simul}

cd ${headdir}/interreg
ls -1 sub-*_aff.nii.gz >inter_subjects_aff.txt
mv *.log ./logs
# perform diffeomorphic inter-subject registration to make diffeo template
${scriptdir}/2d-DTITK_interreg-diffeo.sh ${headdir} mean_affine${Niter}.nii.gz mask.nii.gz \
    inter_subjects_aff.txt ${simul}

#############################################################################################
# warp images to template

# warp dtitk files from subject space to group template for each timepoint
${scriptdir}/03-DTITK_warp2template_v2.sh ${headdir}

# make QC figures of warped scans
${scriptdir}/3c-DTITK_warpqc.sh ${headdir}/warps

# extract diffusion/NODDI maps
${scriptdir}/04-DTITK_makediffmaps.sh ${headdir} ${NODDIarchive}

# make skeleton image and skeletonized diffusion maps
ln -sf ${headdir}/warps/mean_final_high_res.nii.gz ${headdir}/diffmaps/mean_final_high_res.nii.gz
${scriptdir}/05-DTITK_TBSS.sh ${headdir}/diffmaps

# warp JHU-ICBM atlas tracts to group template and extract several tracts
sbatch --wait ${scriptdir}/06-DTITK_warpatlas2template.sh ${headdir} ${scriptdir}/JHU-ICBM.labels

# produce tractfile that contains all tracts.
# manually adjust if you  only want to consider a specific set of tracts.
cd ${headdir}/tracts
ls -1 JHU*.nii.gz >tractfile.txt
sed -i '/JHU-ICBM-labels_templatespace.nii.gz/d' ./tractfile.txt
sed -e s/.nii.gz//g -i * ./tractfile.txt

cd ${headdir}
###########################################################################################
# extract median diff values
${scriptdir}/07-DTITK_extract-diffvalues.sh ${headdir} ${headdir}/tracts/tractfile.txt

#############
### DONE ####
#############

echo "DONE"
echo "final output for statistical analysis can be found in ${headdir}/diffvalues"
echo "do not forget to visual inspect the registrations to the templates and skeletonization "

# junk code  - leave for now  #-------

# # doesn work  !!!

# # # (OPTIONALLY) register additional subjects with 1 timepoint to template
# if [ -f ${headdir}/subjs1timepoint.txt ] \
# && [ $(cat ${headdir}/subjs1timepoint.txt | wc -l) != 0 ]; then
# nsinglesubj=$(cat ${headdir}/subjs1timepoint.txt | wc -l)

# mkdir -p ${headdir}/single_interreg
# cd ${headdir}/single_interreg
# rm -f scans.txt
# for scan in $(cat ${headdir}/subjs1timepoint.txt); do
# 	# make symbolic link
# 	find .. -maxdepth 2 -name "${scan}"  >> scans.txt
# done
# for scan in $(cat scans.txt); do
# 	base=$(echo ${scan} | sed 's:.*/::')
# 	ln -sf ${scan} ${base}
# done
# ls -1 *_dtitk.nii.gz > single_inter_subjects.txt

# if test ${simul} -gt ${nsinglesubj}; then simul2=${nsinglesubj} ; else simul2=${simul} ; fi

# ${scriptdir}/3b-DTITK_warpindivid2template.sh ${headdir}/single_interreg \
# ${headdir}/interreg/mean_diffeomorphic_initial6.nii.gz \
# ${headdir}/single_interreg/single_inter_subjects.txt ${headdir}/interreg/mask.nii.gz ${simul2}

# mv ${headdir}/single_interreg/*2templatespace.dtitk.nii.gz \
# ${headdir}/single_interreg/*native2template_combined.df.nii.gz ${headdir}/warps
#fi
