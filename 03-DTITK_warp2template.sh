#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
	cat <<EOF

    (C) C.Vriend - 2/3/2023 - 03-DTITK_warp2template.sh
	warp dtitk image from each timepoint in subject-space to template-space and reslice to 1mm3 voxels.

    Usage: ./03-DTITK_warp2template.sh headdir
    Obligatory: headdir = full path to working (head) directory where all folders are situated, 
	including the subject folders (see wrapper script)
    
EOF
	exit 1
}

[ _$1 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.5.1

# perform cleanup of files in interreg folder yes (1) no (0)
cleanup=1
# warp native DTITK scans to group template
headdir=${1}
# headdir

warpdir=${headdir}/warps
regdir=${headdir}/interreg
mkdir -p ${warpdir}

cd ${regdir}

if [ -f long_subjects.txt ]; then
	for inter_subj in $(cat long_subjects.txt); do

		subj=${inter_subj%_mean_intra_template.nii.gz*}

		echo "Warping longitudinal images from native space to group-template space"

		if [ ! -f ${warpdir}/${subj}_inter_subject_combined.df.nii.gz ]; then
			# Combine affine and diffeomorphic warp fields from intra-subject space -> inter-subject template space

			dfRightComposeAffine -aff ${regdir}/${subj}_mean_intra_template.aff \
				-df ${regdir}/${subj}_mean_intra_template_aff_diffeo.df.nii.gz \
				-out ${warpdir}/${subj}_inter_subject_combined.df.nii.gz
		fi

		cd ${headdir}/${subj}
		for session in $(ls -d T?); do
			if [ ! -f ${warpdir}/${subj}_${session}_native2template_combined.df.nii.gz ]; then

				# Combine warp fields from T0 intra-subject space -> inter-subject template space
				dfComposition -df1 ${headdir}/${subj}/DWI_${subj}_${session}_combined.df.nii.gz \
					-df2 ${warpdir}/${subj}_inter_subject_combined.df.nii.gz \
					-out ${warpdir}/${subj}_${session}_native2template_combined.df.nii.gz
			fi

			#############################################
			# Generate the spatially normalized DTI data
			# with the isotropic 1mm3 resolution
			#############################################

			if [ ! -f ${warpdir}/${subj}_${session}_2templatespace.dtitk.nii.gz ]; then

				# Warp image for T0 from native -> inter-subjecte space
				deformationSymTensor3DVolume \
					-in ${headdir}/${subj}/DWI_${subj}_${session}_b0_b1000_dtitk.nii.gz \
					-trans ${warpdir}/${subj}_${session}_native2template_combined.df.nii.gz \
					-target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
					-out ${warpdir}/${subj}_${session}_2templatespace.dtitk.nii.gz -vsize 1 1 1
			fi

		done
	done

	# same for cross-sectional subjects

	for scan in $(cat ${regdir}/cross_subjects.txt); do

		subj=${scan%_b0_b1000_dtitk.nii.gz*}

		echo "Warping cross-sectional images from native space to group-template space"

		if [ ! -f ${warpdir}/${subj}_inter_subject_combined.df.nii.gz ]; then
			# Combine affine and diffeomorphic warp fields

			dfRightComposeAffine -aff ${regdir}/${subj}_b0_b1000_dtitk.aff \
				-df ${regdir}/${subj}_b0_b1000_dtitk_aff_diffeo.df.nii.gz \
				-out ${warpdir}/${subj}_inter_subject_combined.df.nii.gz
		fi

		#############################################
		# Generate the spatially normalized DTI data
		# with the isotropic 1mm3 resolution
		#############################################

		if [ ! -f ${warpdir}/${subj}_2templatespace.dtitk.nii.gz ]; then

			# Warp image for T0 from native -> inter-subjecte space
			deformationSymTensor3DVolume \
				-in ${regdir}/${scan} \
				-trans ${warpdir}/${subj}_inter_subject_combined.df.nii.gz \
				-target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
				-out ${warpdir}/${subj}_2templatespace.dtitk.nii.gz -vsize 1 1 1
		fi

	done

fi

cd ${regdir}

if [ ! -f long_subjects.txt ] &&
	[ -f inter_subjects.txt ]; then

	for scan in $(cat ${regdir}/inter_subjects.txt); do

		subj=${scan%_b0_b1000_dtitk.nii.gz*}

		echo "Warping cross-sectional images from native space to group-template space"

		if [ ! -f ${warpdir}/${subj}_inter_subject_combined.df.nii.gz ]; then
			# Combine affine and diffeomorphic warp fields

			dfRightComposeAffine -aff ${regdir}/${subj}_b0_b1000_dtitk.aff \
				-df ${regdir}/${subj}_b0_b1000_dtitk_aff_diffeo.df.nii.gz \
				-out ${warpdir}/${subj}_inter_subject_combined.df.nii.gz
		fi

		#############################################
		# Generate the spatially normalized DTI data
		# with the isotropic 1mm3 resolution
		#############################################

		if [ ! -f ${warpdir}/${subj}_2templatespace.dtitk.nii.gz ]; then

			# Warp image for T0 from native -> inter-subjecte space
			deformationSymTensor3DVolume \
				-in ${regdir}/${scan} \
				-trans ${warpdir}/${subj}_inter_subject_combined.df.nii.gz \
				-target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
				-out ${warpdir}/${subj}_2templatespace.dtitk.nii.gz -vsize 1 1 1
		fi

	done

fi

if test ${cleanup} -eq 1; then
	# clean up
	cd ${headdir}/interreg
	rm *.aff *diffeo.df.nii.gz *_diffeo.nii.gz
fi
