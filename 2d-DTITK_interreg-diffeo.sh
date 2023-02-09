#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl


# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 2d-DTITK_interreg_diffeo.sh
   
   WIP
   

    Usage: ./2d-DTITK_interreg-diffeo.sh headdir
    Obligatory: 
    headdir = full path to (head) directory where all folders are stored, 
	including the subject folders and scripts directory (that includes this script)
    
EOF
    exit 1
}

[ _$5 = _ ] && Usage


#########################################
# Setup relevant software and variables
#########################################
module load dtitk/2.3.1
module load fsl/6.0.5.1

. ${DTITK_ROOT}/scripts/dtitk_common.sh

# Sets up variables for folder with tensor images from all subjects
headdir=${1}
workdir=${headdir}/interreg
scriptdir=${headdir}/scripts
template=${2} # mean_affine${Niter}.nii.gz
mask=${3}     # mask.nii.gz
subjects=${4} # inter_subjects_aff.txt
simul=${5}

mkdir -p ${workdir}/QC

ftol=0.002 # default

export DTITK_USE_QSUB=0

cd ${workdir}
# for slurm array
nsubj=$(cat ${subjects} | wc -l)


if [ ! -f ${workdir}/mean_diffeomorphic_initial6.nii.gz ]; then

	cp ${template} mean_diffeomorphic_initial0.nii.gz
	subjects_diffeo=$(echo ${subjects} | sed -e 's/.txt/_diffeo.txt/')
	rm -fr ${subjects_diffeo}
	rm -fr diffeo.txt

	for subj in $(cat ${subjects}); do
		pref=$(remove_ext ${subj})
		echo ${pref}_diffeo.nii.gz >>${subjects_diffeo}
		echo ${pref}_diffeo.df.nii.gz >>diffeo.txt
	done

	count=1
	template_current=mean_diffeomorphic_initial.nii.gz
	while [ ${count} -le 6 ]; do

		echo "dti_diffeomorphic_population_initial iteration" $count
		let level=count
		let oldcount=count-1
		ln -sf mean_diffeomorphic_initial${oldcount}.nii.gz ${template_current}

		sbatch --wait --array="1-${nsubj}%${simul}" \
			${scriptdir}/dti_diffeomorphic_reg_slurm.sh ${template_current} ${subjects} ${mask} 1 ${level} ${ftol}

		echo "update template"
		template_new=mean_diffeomorphic_initial${count}.nii.gz
		TVMean -in ${subjects_diffeo} -out ${template_new}
		VVMean -in diffeo.txt -out mean_df.nii.gz
		dfToInverse -in mean_df.nii.gz
		# cp ${template_new} b${template_new}
		deformationSymTensor3DVolume -in ${template_new} -out ${template_new} \
			-trans mean_df_inv.nii.gz
		# clear up the temporary files
		rm -fr ${template_current}
		let count=count+1

	done

else
	echo "diffeomorphic warps already made"
fi

# make pngs of overlay with slicer for QC
fslroi mean_diffeomorphic_initial6.nii.gz mean_diffeomorphic_initial6_vslicer 0 1
for subj in $(ls *_aff_diffeo.nii.gz); do
	echo ${subj}
	base=${subj%_aff_diffeo.nii.gz*}_diffeo
	fslroi ${subj} diffeo 0 1
	slicer mean_diffeomorphic_initial6_vslicer diffeo -a ${workdir}/QC/${base}_overlay.png
	rm diffeo.nii.gz
done
