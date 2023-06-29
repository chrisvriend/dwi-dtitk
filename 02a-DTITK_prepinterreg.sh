#!/bin/bash

echo "prepare inter-subject registration pipeline"
workdir=${1}

mkdir -p ${workdir}/interreg
cd ${workdir}/interreg

# DTITK can't handle having these files in separate folders.
# these files therefore need to be combined into one folder
find .. -maxdepth 3 -not -path "*/interreg/*" -name "*_space-intra_template.nii.gz" >scans.txt

if (($(cat scans.txt | wc -l) > 0)); then
	echo
	echo "LONGITUDINAL data"
	echo
	for scan in $(cat scans.txt); do
		base=$(echo ${scan} | sed 's:.*/::')
		# make symbolic link
		ln -sf ${scan} ${base}
		# alternatively use move
		#mv ${scan} .

	done
	ls -1 *_space-intra_template.nii.gz >long_subjects.txt
else
	rm scans.txt
fi

if [ -f ../subjs1timepoint.txt ]; then
	for singlesub in $(cat ../subjs1timepoint.txt); do
		find .. -maxdepth 4 -not -path "*/interreg/*" -path '*/dwi/*' -name "${singlesub}" >>singlescans.txt
	done

	for scan in $(cat singlescans.txt); do
		base=$(echo ${scan} | sed 's:.*/::')
		# make symbolic link
		ln -sf ${scan} ${base}
		# alternatively use move
		#mv ${scan} .

	done
	# create lists for DTI-TK registration
	ls -1 *desc-preproc*_dtitk.nii.gz >cross_subjects.txt
	rm singlescans.txt
else
	echo "no subjects with only one session"
	echo

fi

# in case of bids format without sessions

find .. -maxdepth 3 -not -path "*/interreg/*" -path '*/dwi/*' -name "*desc-preproc*_dtitk.nii.gz" >scans.txt
if (($(cat scans.txt | wc -l) > 0)); then

	echo "CROSS-SECTIONAL data"
	echo
	for scan in $(cat scans.txt); do
		base=$(echo ${scan} | sed 's:.*/::')
		# make symbolic link
		ln -sf ${scan} ${base}
		# alternatively use move
		#mv ${scan} .

	done
else
	rm scans.txt
fi
ls -1 sub-*.nii.gz >inter_subjects.txt

echo
if [ -f long_subjects.txt ]; then
	echo "there are $(cat long_subjects.txt | wc -l) subjects with longitudinal data"
	echo "there are $(cat cross_subjects.txt | wc -l) subjects with data at a single time-point"
	echo "--------+"
fi
echo "there are a total of $(cat inter_subjects.txt | wc -l) to process"
