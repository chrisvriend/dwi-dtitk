#!/bin/bash 

echo "prepare inter-subject registration pipeline"
workdir=${1}

mkdir -p ${workdir}/interreg
cd ${workdir}/interreg

# DTITK can't handle having these files in separate folders.
# these files therefore need to be combined into one folder
find .. -maxdepth 2 -name "*dtitk.nii.gz"  > scans.txt


for scan in `cat scans.txt`; do
	base=$(echo ${scan} | sed 's:.*/::')
	base2=${base#DWI_*}
	# make symbolic link
	ln -s ${scan} ${base2}
	# alternatively use move
	#mv ${scan} .

done
# create lists for DTI-TK registration
ls -1 sub-*.nii.gz > inter_subjects.txt