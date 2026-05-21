#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, removed sleep,
# input validation, safer loops, output existence check

#SBATCH --job-name=dtitk-extdiff
#SBATCH --mem-per-cpu=1G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:15:00
#SBATCH --nice=2000
#SBATCH --output=ext_diff_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - extract_diffmeasures_slurm.sh
    SLURM array worker: extracts median diffusion values per tract
    for one subject from skeletonised diffusion maps, then converts
    the per-tract txt files to a single CSV via diff_txt2csv.py.

    Usage: sbatch --array=1-N%simul ./extract_diffmeasures_slurm.sh workdir subjects tractdir tractfile outputdir scriptdir
      workdir    full path to diffmaps directory
      subjects   subjects list file (one subject per line)
      tractdir   full path to tracts directory
      tractfile  full path to tractfile.txt (one tract name per line, no extension)
      outputdir  full path to output directory for CSV files
      scriptdir  full path to scripts directory

EOF
    exit 1
}

[ _${6:-} = _ ] && Usage

workdir=${1}
subjects=${2}
tractdir=${3}
tractfile=${4}
outputdir=${5}
scriptdir=${6}

# source site config
source "${scriptdir}/config.sh"

# load software
module load fsl/${FSL_VERSION}

# resolve subject from array task ID
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

# validate inputs
if [ ! -f "${tractfile}" ]; then
    echo "ERROR: tractfile not found: ${tractfile}" >&2
    exit 1
fi

scan="${workdir}/${subj}_space-template_desc-skldiffmaps_res-1mm_dtitk.nii.gz"
if [ ! -f "${scan}" ]; then
    echo "ERROR: skeletonised diffmap not found: ${scan}" >&2
    exit 1
fi

mkdir -p "${outputdir}"

echo "----------"
echo "${subj}"
echo "----------"

###############################################################################
# Extract median diffusion value per tract
###############################################################################
echo "Extracting median diffusion values"

while IFS= read -r tract; do
    [ -z "${tract}" ] && continue

    skl_mask="${tractdir}/${tract}_skl.nii.gz"
    if [ ! -f "${skl_mask}" ]; then
        echo "ERROR: skeletonised tract mask not found: ${skl_mask}" >&2
        exit 1
    fi

    echo "  ....${tract}"
    fslstats -t "${scan}" \
        -k "${skl_mask}" \
        -p 50 > "${workdir}/${subj}_${tract}_diffvalues.txt"

done < "${tractfile}"

###############################################################################
# Convert per-tract txt files to a single subject CSV
###############################################################################
"${scriptdir}/diff_txt2csv.py" \
    --workdir  "${workdir}" \
    --outdir   "${outputdir}" \
    --subjid   "${subj}"

# verify output and clean up txt files
if [ -f "${outputdir}/${subj}_diffvalues.csv" ]; then
    rm -f "${workdir}/${subj}"*_diffvalues.txt
    echo "CSV written: ${outputdir}/${subj}_diffvalues.csv"
else
    echo "ERROR: diff_txt2csv.py did not produce ${outputdir}/${subj}_diffvalues.csv" >&2
    exit 1
fi

echo
echo "DONE extracting diffusion values for ${subj}"
