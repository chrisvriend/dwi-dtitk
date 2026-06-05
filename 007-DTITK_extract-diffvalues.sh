#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: converted to SLURM array (one task per subject), set -euo pipefail,
# source config, removed sbatch --wait, input validation, safer loops

#SBATCH --job-name=dtitk-extractdiff
#SBATCH --mem=500M
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-0:15:00
#SBATCH --nice=2000
#SBATCH -o 7-DTITK_%A_%a.log

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 007-DTITK_extract-diffvalues.sh
    Skeletonises tract masks against the mean FA skeleton, then
    extracts median diffusion values per tract per subject and
    writes subject-specific CSV output via diff_txt2csv.py.
    Run as a SLURM array job (one task per subject).

    Usage: sbatch --array=1-N%simul ./007-DTITK_extract-diffvalues.sh workdir tractfile scriptdir subjects
      workdir    full path to working (head) directory
      tractfile  full path to tractfile.txt (one tract name per line, no extension)
      scriptdir  full path to scripts directory
      subjects   full path to subjects.txt (one subject per line)

EOF
    exit 1
}

[ _${4:-} = _ ] && Usage

workdir=${1}
tractfile=${2}
scriptdir=${3}
subjects=${4}

# source site config
source "${scriptdir}/config.sh"

# load software
module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}
module load Anaconda3/${ANACONDA_VERSION}
conda activate "${MRTRIX_ENV}"


# resolve subject from array task ID
subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d" "${subjects}")
if [ -z "${subj}" ]; then
    echo "ERROR: could not resolve subject for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

diffdir=${workdir}/diffmaps
tractdir=${workdir}/tracts
outputdir=${workdir}/diffvalues
mkdir -p "${outputdir}"

echo "----------"
echo "${subj}"
echo "----------"

# validate inputs
if [ ! -f "${tractfile}" ]; then
    echo "ERROR: tractfile not found: ${tractfile}" >&2
    exit 1
fi
if [ ! -f "${diffdir}/mean_FA_skeleton_mask.nii.gz" ]; then
    echo "ERROR: mean_FA_skeleton_mask.nii.gz not found in ${diffdir}" >&2
    exit 1
fi

###############################################################################
# Extract median diffusion values per tract for this subject
###############################################################################
cd "${diffdir}"

# find this subject's skeletonised diffmap
scan="${subj}_space-template_desc-skldiffmaps_res-1mm_dtitk.nii.gz"

if [ ! -f "${scan}" ]; then
    echo "ERROR: skeletonised diffmap not found for ${subj}: ${diffdir}/${scan}" >&2
    exit 1
fi

echo "Extracting median diffusion values"

while IFS= read -r tract; do
    if [ -z "${tract}" ]; then continue; fi

    skl_mask="${tractdir}/${tract}_skl.nii.gz"
    if [ ! -f "${skl_mask}" ]; then
        echo "ERROR: skeletonised tract mask not found: ${skl_mask}" >&2
        exit 1
    fi

    echo "  ....${tract}"
    fslstats -t "${scan}" \
        -k "${skl_mask}" \
        -p 50 > "${diffdir}/${subj}_${tract}_diffvalues.txt"

done < "${tractfile}"

###############################################################################
# Convert per-tract txt files to a single subject CSV
###############################################################################
mkdir -p "${outputdir}"

"${scriptdir}/diff_txt2csv.py" \
    --workdir "${diffdir}" \
    --outdir  "${outputdir}" \
    --subjid  "${subj}"

# verify output and clean up txt files
if [ -f "${outputdir}/${subj}_diffvalues.csv" ]; then
    rm -f "${diffdir}/${subj}"*_diffvalues.txt
    echo "CSV written: ${outputdir}/${subj}_diffvalues.csv"
else
    echo "ERROR: diff_txt2csv.py did not produce ${outputdir}/${subj}_diffvalues.csv" >&2
    exit 1
fi

echo
echo "DONE extracting diffusion values for ${subj}"
