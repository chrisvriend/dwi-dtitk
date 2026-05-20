#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, source config, input validation,
# safer loops, pre-flight checks, fixed broken backslash in original

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 008-DTITK_write-output.sh
    Copies final pipeline outputs (diffusion maps, CSVs, transforms,
    QC figures, templates, tracts, logs) to the output directory.

    Usage: bash ./008-DTITK_write-output.sh workdir outputdir bshell
      workdir    full path to working (head) directory
      outputdir  full path to final output directory
      bshell     b-value shell (e.g. 1000)

EOF
    exit 1
}

[ _${3:-} = _ ] && Usage

workdir=${1}
outputdir=${2}
bshell=${3}

# source site config
scriptdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${scriptdir}/config.sh"

# validate inputs
if [ ! -d "${workdir}" ]; then
    echo "ERROR: workdir not found: ${workdir}" >&2
    exit 1
fi

###############################################################################
# Pre-flight checks: verify all upstream steps completed successfully
###############################################################################
echo "Running pre-flight checks"

n_errors=0

check_file() {
    if [ ! -f "${1}" ]; then
        echo "  MISSING: ${1}" >&2
        n_errors=$((n_errors + 1))
    fi
}

check_dir() {
    if [ ! -d "${1}" ]; then
        echo "  MISSING dir: ${1}" >&2
        n_errors=$((n_errors + 1))
    fi
}

check_file "${workdir}/diffmaps/mean_final_high_res.nii.gz"
check_file "${workdir}/diffmaps/all_FA.nii.gz"
check_file "${workdir}/diffmaps/ICBM2FAWarped.nii.gz"
check_file "${workdir}/tracts/JHU-ICBM-labels_templatespace.nii.gz"
check_dir  "${workdir}/diffvalues"

n_csv=$(ls -1 "${workdir}/diffvalues/"*.csv 2>/dev/null | wc -l)
if [ "${n_csv}" -lt 1 ]; then
    echo "  MISSING: no CSV files found in ${workdir}/diffvalues/" >&2
    n_errors=$((n_errors + 1))
fi

if [ "${n_errors}" -gt 0 ]; then
    echo
    echo "ERROR: ${n_errors} pre-flight check(s) failed." >&2
    echo "Check the workdir and log files before running this script." >&2
    exit 1
fi

echo "  All pre-flight checks passed"
echo

###############################################################################
# Create output directory structure
###############################################################################
mkdir -p "${outputdir}"
mkdir -p "${outputdir}/logs"
mkdir -p "${outputdir}/templates"
mkdir -p "${outputdir}/tracts"

cd "${workdir}"

###############################################################################
# Per-subject output
###############################################################################
mapfile -t subj_dirs < <(ls -d sub-*/ 2>/dev/null | sed 's:/.*::')

if [ ${#subj_dirs[@]} -eq 0 ]; then
    echo "ERROR: no subject directories found in ${workdir}" >&2
    exit 1
fi

echo "Copying per-subject outputs for ${#subj_dirs[@]} subjects"

for subj in "${subj_dirs[@]}"; do

    for dwidir in "${workdir}/${subj}/"{,ses*/}dwi; do
        [ -d "${dwidir}" ] || continue

        sessiondir=$(dirname "${dwidir}")
        session=$(echo "${sessiondir}" | grep -oP "(?<=${subj}/).*")

        if [ -z "${session}" ]; then
            sessionpath=/
            sessionfile=_
        else
            sessionpath=/${session}/
            sessionfile=_${session}_
        fi

        # create per-subject output subdirectories
        mkdir -p "${outputdir}/${subj}${sessionpath}dtitk"
        mkdir -p "${outputdir}/${subj}${sessionpath}xfms"
        mkdir -p "${outputdir}/${subj}${sessionpath}figures"

        # diffusion maps (4D diffmaps + skeletonised diffmaps)
        rsync -a --ignore-missing-args \
            "${workdir}/diffmaps/${subj}${sessionfile}space-template_desc"*"_dtitk.nii.gz" \
            "${outputdir}/${subj}${sessionpath}dtitk/"

        # per-subject diffvalues CSV
        rsync -a --ignore-missing-args \
            "${workdir}/diffvalues/${subj}${sessionfile}diffvalues.csv" \
            "${outputdir}/${subj}${sessionpath}dtitk/"

        # warp field
        rsync -a --ignore-missing-args \
            "${workdir}/warps/${subj}${sessionfile}dwi-2-dtitktemplate.df.nii.gz" \
            "${outputdir}/${subj}${sessionpath}xfms/"

        # QC figures
        rsync -a --ignore-missing-args \
            "${workdir}/${subj}${sessionpath}figures/"*.png \
            "${workdir}/warps/QC/${subj}${sessionfile}overlay.png" \
            "${workdir}/interreg/QC/${subj}"*.png \
            "${outputdir}/${subj}${sessionpath}figures/" 2>/dev/null || true

    done
done

###############################################################################
# Logs
###############################################################################
echo "Copying logs"
find "${workdir}" -name "*.log" -exec rsync -a {} "${outputdir}/logs/" \;

###############################################################################
# Tracts
###############################################################################
echo "Copying tracts"
rsync -a "${workdir}/tracts/" "${outputdir}/tracts/"

###############################################################################
# Templates and group-level images
###############################################################################
echo "Copying templates"
rsync -a --ignore-missing-args \
    "${workdir}/diffmaps/tbss/stats/mean"*.nii.gz \
    "${outputdir}/templates/"

rsync -a --ignore-missing-args \
    "${workdir}/warps/mean_final_high_res.nii.gz" \
    "${workdir}/interreg/mask.nii.gz" \
    "${workdir}/interreg/mean_diffeomorphic_initial6"*.nii.gz \
    "${outputdir}/templates/"

###############################################################################
# Summary
###############################################################################
echo
echo "Output written to: ${outputdir}"
echo
echo "Contents:"
echo "  Per-subject dtitk/  : diffusion maps + CSV"
echo "  Per-subject xfms/   : warp fields"
echo "  Per-subject figures/: QC PNGs"
echo "  templates/          : group template + skeleton stats"
echo "  tracts/             : JHU tract masks"
echo "  logs/               : all pipeline logs"
echo
echo "DONE"
