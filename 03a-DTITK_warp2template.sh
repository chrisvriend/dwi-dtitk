#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
	cat <<EOF

    (C) C.Vriend - 2/3/2023 - 03-DTITK_warp2template.sh
	warp dtitk image from each timepoint in subject-space to template-space and reslice to 1mm3 voxels.

    Usage: ./03-DTITK_warp2template.sh workdir
    Obligatory: workdir = full path to working (head) directory where all folders are situated, 
	including the subject folders (see wrapper script)
    
EOF
	exit 1
}

[ _$2 = _ ] && Usage

module load dtitk/2.3.1
module load fsl/6.0.6.5

# perform cleanup of files in interreg folder yes (1) no (0)
cleanup=0
# shell
# warp native DTITK scans to group template
workdir=${1}
# workdir
bshell=${2}
# bshell

warpdir=${workdir}/warps
regdir=${workdir}/interreg
mkdir -p ${warpdir}

cd ${regdir}

if [ -f long_subjects.txt ]; then
	echo
	echo "Warping longitudinal images from native space to group-template space"
	echo
	for inter_subj in $(cat long_subjects.txt); do

		subj=${inter_subj%_space-intra_template.nii.gz*}
		echo "----------"
		echo "${subj}"
		echo "----------"


		if [ ! -f ${warpdir}/${subj}_intra-2-dtitktemplate.df.nii.gz ]; then
			# Combine affine and diffeomorphic warp fields from intra-subject space -> inter-subject template space
			dfRightComposeAffine -aff ${regdir}/${subj}_space-intra_template.aff \
				-df ${regdir}/${subj}_space-intra_template_aff_diffeo.df.nii.gz \
				-out ${warpdir}/${subj}_intra-2-dtitktemplate.df.nii.gz
		fi

		cd ${workdir}/${subj}
		for session in $(ls -d ses*); do

			if [ -f ${workdir}/${subj}/intra/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk_dwi-2-intra.df.nii.gz ]; then
			
				if [ -f ${warpdir}/${subj}_intra-2-dtitktemplate.df.nii.gz ]; then

					if [ ! -f ${warpdir}/${subj}_${session}_dwi-2-dtitktemplate.df.nii.gz ]; then

						# Combine warp fields from intra-subject space -> inter-subject template space
						dfComposition \
							-df1 ${workdir}/${subj}/intra/${subj}_${session}_space-dwi_desc-preproc-b1000_dtitk_dwi-2-intra.df.nii.gz \
							-df2 ${warpdir}/${subj}_intra-2-dtitktemplate.df.nii.gz \
							-out ${warpdir}/${subj}_${session}_dwi-2-dtitktemplate.df.nii.gz
					fi
				else 
					echo
					echo "ERROR! ${subj} has no intra to template deformation field"
					echo
					continue

				fi
			else
					echo
					echo "ERROR! ${subj} - ${session} has no dwi-to-intra deformation field"
					echo
					continue
			fi

			
			#############################################
			# Generate the spatially normalized DTI data
			# with the isotropic 1mm3 resolution
			#############################################
			if [ ! -f ${warpdir}/${subj}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz ]; then
				# Warp image for  from dwi -> inter-subjecte space
				deformationSymTensor3DVolume \
					-in ${workdir}/${subj}/${session}/dwi/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz \
					-trans ${warpdir}/${subj}_${session}_dwi-2-dtitktemplate.df.nii.gz \
					-target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
					-out ${warpdir}/${subj}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz \
					-vsize 1 1 1

			fi

		done
	done
unset subj

cd ${regdir}
	# same for cross-sectional subjects
	if [ -f ${regdir}/cross_subjects.txt ]; then
		echo
		echo "Warping subjects w/ 1 time-point from dwi space to group-template space"
		echo
		for scan in $(cat ${regdir}/cross_subjects.txt); do

			subj_session=${scan%_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz*}
			base=$(remove_ext ${scan})
			subj=${subj_session%_ses-*}
			session=${subj_session#${subj}_*}
			echo "----------"
			echo "${subj}"
			echo "----------"

			if [ ! -f ${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz ]; then
				# Combine affine and diffeomorphic warp fields

				dfRightComposeAffine -aff ${regdir}/${base}.aff \
					-df ${regdir}/${base}_aff_diffeo.df.nii.gz \
					-out ${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz
			fi
			#############################################
			# Generate the spatially normalized DTI data
			# with the isotropic 1mm3 resolution
			#############################################

			if [ ! -f ${warpdir}/${subj}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz ]; then

				# Warp image for T0 from native -> inter-subjecte space
				deformationSymTensor3DVolume \
					-in ${workdir}/${subj}/${session}/dwi/${subj}_${session}_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz \
					-trans ${warpdir}/${subj_session}_dwi-2-dtitktemplate.df.nii.gz \
					-target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
					-out ${warpdir}/${subj}_${session}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz \
					-vsize 1 1 1
			fi
		unset base subj_session session
		done

	fi
fi

cd ${regdir}

if [ ! -f long_subjects.txt ] &&
	[ -f inter_subjects.txt ]; then
	echo
	echo "Warping cross-sectional images from native space to group-template space"
	echo
	for scan in $(cat ${regdir}/inter_subjects.txt); do

		subj=${scan%_space-dwi_desc-preproc-b${bshell}_dtitk.nii.gz*}
		base=$(remove_ext ${scan})
		echo "----------"
		echo "${subj}"
		echo "----------"
		

		if [ ! -f ${warpdir}/${subj}_dwi-2-dtitk.df.nii.gz ]; then
			# Combine affine and diffeomorphic warp fields

			dfRightComposeAffine -aff ${regdir}/${base}.aff \
				-df ${regdir}/${base}_aff_diffeo.df.nii.gz \
				-out ${warpdir}/${subj}_dwi-2-dtitktemplate.df.nii.gz
		fi

		#############################################
		# Generate the spatially normalized DTI data
		# with the isotropic 1mm3 resolution
		#############################################

		if [ ! -f ${warpdir}/${subj}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz ]; then

			# Warp image for T0 from native -> inter-subjecte space
			deformationSymTensor3DVolume \
				-in ${regdir}/${scan} \
				-trans ${warpdir}/${subj}_dwi-2-dtitktemplate.df.nii.gz \
				-target ${regdir}/mean_diffeomorphic_initial6.nii.gz \
				-out ${warpdir}/${subj}_space-template_desc-b${bshell}_res-1mm_dtitk.nii.gz -vsize 1 1 1
		fi

	done

fi

if test ${cleanup} -eq 1; then
	# clean up
	cd ${workdir}/interreg
	rm *.aff *diffeo.df.nii.gz *_diffeo.nii.gz \
		mean_affine[0-4].nii.gz mean_diffeomorphic_initial[0-5].nii.gz

fi
