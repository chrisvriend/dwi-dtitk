#!/bin/bash 

echo "prepare inter-subject registration pipeline"
workdir=${1}

mkdir -p ${workdir}/interreg
cd ${workdir}/interreg

# DTITK can't handle having these files in separate folders.
# these files therefore need to be combined into one folder
find .. -maxdepth 2 -name "*_mean_intra_template.nii.gz"  > scans.txt

for scan in `cat scans.txt`; do
	base=$(echo ${scan} | sed 's:.*/::')
	# make symbolic link
	ln -s ${scan} ${base}
	# alternatively use move
	#mv ${scan} .

done
ls -1 *_mean_intra_template.nii.gz > long_subjects.txt

# important here to check that this went correctly

for singlesub in $(cat ../subjs1timepoint.txt); do 
find .. -maxdepth 2 -name "${singlesub}"  >> singlescans.txt
done


for scan in `cat singlescans.txt`; do
	base=$(echo ${scan} | sed 's:.*/::')
	base2=${base#DWI_*}
	# make symbolic link
	ln -s ${scan} ${base2}
	# alternatively use move
	#mv ${scan} .

done
# create lists for DTI-TK registration
ls -1 *_b0_b1000_dtitk.nii.gz > cross_subjects.txt
ls -1 sub-*.nii.gz > inter_subjects.txt