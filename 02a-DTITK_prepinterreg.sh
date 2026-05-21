#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, existence checks, improved error handling

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 02a-DTITK_prepinterreg.sh
    Prepare inter-subject registration by collecting subject templates
    into a single interreg folder via symbolic links.

    Usage: bash ./02a-DTITK_prepinterreg.sh workdir
      workdir  full path to working (head) directory

EOF
    exit 1
}

[ _${1:-} = _ ] && Usage

workdir=${1}
scriptdir=${2}
#scriptdir=${scriptdir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
source "${scriptdir}/config.sh"

mkdir -p "${workdir}/interreg"
mkdir -p "${workdir}/interreg/logs"
cd "${workdir}/interreg"

echo "Preparing inter-subject registration directory"
echo

###############################################################################
# Longitudinal subjects: collect intra-subject templates
###############################################################################
find .. -maxdepth 3 -not -path "*/interreg/*" \
    -name "*_space-intra_template.nii.gz" > scans.txt

if [ "$(wc -l < scans.txt)" -gt 0 ]; then
    echo "LONGITUDINAL data found"
    echo

    while IFS= read -r scan; do
        base=$(basename "${scan}")
        if [ ! -L "${base}" ]; then
            ln -sf "${scan}" "${base}"
        fi
    done < scans.txt

    ls -1 *_space-intra_template.nii.gz > long_subjects.txt
    echo "  $(wc -l < long_subjects.txt) longitudinal subject(s) found"
    rm scans.txt
else
    echo "No longitudinal data found"
    rm scans.txt
fi

###############################################################################
# Mixed: subjects with only one timepoint (from subjs1timepoint.txt)
###############################################################################
if [ -f "${workdir}/subjs1timepoint.txt" ]; then
    echo
    echo "Processing subjects with a single timepoint"

    while IFS= read -r singlesub; do
        find .. -maxdepth 4 -not -path "*/interreg/*" \
            -path "*/dwi/*" -name "${singlesub}" >> singlescans.txt
    done < "${workdir}/subjs1timepoint.txt"

    if [ -f singlescans.txt ] && [ "$(wc -l < singlescans.txt)" -gt 0 ]; then
        while IFS= read -r scan; do
            base=$(basename "${scan}")
            if [ ! -L "${base}" ]; then
                ln -sf "${scan}" "${base}"
            fi
        done < singlescans.txt

        ls -1 *desc-preproc*_dtitk.nii.gz > cross_subjects.txt 2>/dev/null || true
        echo "  $(wc -l < cross_subjects.txt) single-timepoint subject(s) added"
        rm singlescans.txt
    else
        echo "  WARNING: subjs1timepoint.txt exists but no matching files found"
        rm -f singlescans.txt
    fi
else
    echo "No subjects with only one session (subjs1timepoint.txt not found)"
    echo
fi

###############################################################################
# Cross-sectional subjects (BIDS without sessions)
###############################################################################
find .. -maxdepth 3 -not -path "*/interreg/*" \
    -path "*/dwi/*" -name "*desc-preproc*_dtitk.nii.gz" > scans.txt

if [ "$(wc -l < scans.txt)" -gt 0 ]; then
    echo
    echo "CROSS-SECTIONAL data found"
    echo

    while IFS= read -r scan; do
        base=$(basename "${scan}")
        if [ ! -L "${base}" ]; then
            ln -sf "${scan}" "${base}"
        fi
    done < scans.txt
    rm scans.txt
else
    rm scans.txt
fi

###############################################################################
# Build combined subject list for inter-subject registration
###############################################################################
ls -1 sub-*.nii.gz | grep -v '_aff\.nii\.gz' > inter_subjects.txt

echo
if [ -f long_subjects.txt ]; then
    echo "Longitudinal subjects  : $(wc -l < long_subjects.txt)"
    if [ -f cross_subjects.txt ]; then
        echo "Single-timepoint subjs : $(wc -l < cross_subjects.txt)"
    fi
    echo "--------"
fi

ninter=$(wc -l < inter_subjects.txt)
if [ "${ninter}" -eq 0 ]; then
    echo "ERROR: inter_subjects.txt is empty — no subjects found for inter-subject registration" >&2
    exit 1
fi

echo "Total subjects for inter-subject registration: ${ninter}"
echo
echo "DONE"
