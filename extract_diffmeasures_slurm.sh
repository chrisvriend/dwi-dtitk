#!/bin/bash 
# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

#SBATCH --job-name=dtitk-extdiff
#SBATCH --mem-per-cpu=1G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:15:00
#SBATCH --nice=2000
#SBATCH --output=ext_diff_%A_%a.log

#disabled##SBATCH --array=1-4%4

module load fsl/6.0.6.5

workdir=${1}
subjects=${2}
tractdir=${3}
tractfile=${4}
outputdir=${5}
scriptdir=${6}


subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" ${subjects})
# random delay
duration=$((RANDOM % 10 + 2))
echo "INITIALIZING..."
sleep ${duration}

scan=${subj}_space-template_desc-diffmaps_res-1mm_dtitk.nii.gz
echo ${subj}

for tract in $(cat ${tractfile}); do 
echo "....${tract}"
fslstats -t ${scan} \
-k ${tractdir}/${tract}_skl.nii.gz -p 50 > ${subj}_${tract}_diffvalues.txt
done 

# concatenate files 
mkdir -p ${outputdir}
${scriptdir}/diff_txt2csv.py --workdir ${workdir} --outdir ${outputdir} --subjid ${subj}

if [ -f ${outputdir}/${subj}_diffvalues.csv ]; then 

rm ${workdir}/${subj}*_diffvalues.txt
else 
echo "something went wrong with converting the txt files to a csv table!"

fi 