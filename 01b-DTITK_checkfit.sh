#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: set -euo pipefail, safer loops, explicit error tracking,
# non-zero exit on failures, input validation

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 01b-DTITK_checkfit.sh
    Check that DTI-TK conversion and intra-subject registration completed
    successfully for all subjects. Writes subjs1timepoint.txt for subjects
    with only a single session. Exits non-zero if any subject failed.

    Usage: bash ./01b-DTITK_checkfit.sh workdir
      workdir  full path to working (head) directory

EOF
    exit 1
}

[ _${1:-} = _ ] && Usage

workdir=${1}

if [ ! -d "${workdir}" ]; then
    echo "ERROR: workdir not found: ${workdir}" >&2
    exit 1
fi

cd "${workdir}"

rm -f "${workdir}/subjs1timepoint.txt"

n_ok=0
n_single=0
n_failed=0
failed_list=""

mapfile -t subj_dirs < <(ls -d sub-*/ 2>/dev/null | sed 's:/.*::')

if [ ${#subj_dirs[@]} -eq 0 ]; then
    echo "ERROR: no subject directories found in ${workdir}" >&2
    exit 1
fi

for subj in "${subj_dirs[@]}"; do

    cd "${workdir}/${subj}"

    if [ ! -d "${workdir}/${subj}/intra" ]; then
        # no intra dir: expect exactly one dtitk file (single timepoint)
        n_dtitk=$(find . -path '*/dwi/*' \
            -name "*desc-preproc*_dtitk.nii.gz" 2>/dev/null | wc -l)

        if [ "${n_dtitk}" -eq 1 ]; then
            echo "${subj}: single timepoint — OK"
            echo "${subj}" >> "${workdir}/subjs1timepoint.txt"
            n_single=$((n_single + 1))
        else
            echo "ERROR: fsl-to-dtitk conversion failed for ${subj} (found ${n_dtitk} dtitk files, expected 1)" >&2
            failed_list="${failed_list} ${subj}"
            n_failed=$((n_failed + 1))
        fi

    else
        # intra dir exists: expect exactly one intra-subject template
        n_intra=$(find . -path '*/intra/*' \
            -name "*_space-intra_template.nii.gz" 2>/dev/null | wc -l)

        if [ "${n_intra}" -eq 1 ]; then
            echo "${subj}: intra-subject registration OK"
            n_ok=$((n_ok + 1))
        else
            echo "ERROR: intra-subject registration failed for ${subj} (found ${n_intra} intra templates, expected 1)" >&2
            failed_list="${failed_list} ${subj}"
            n_failed=$((n_failed + 1))
        fi
    fi

    cd "${workdir}"
done

echo
echo "Summary:"
echo "  Longitudinal (intra-reg OK) : ${n_ok}"
echo "  Single timepoint            : ${n_single}"
echo "  Failed                      : ${n_failed}"

if [ "${n_failed}" -gt 0 ]; then
    echo
    echo "ERROR: the following subjects failed and must be resolved before continuing:" >&2
    for f in ${failed_list}; do
        echo "  ${f}" >&2
    done
    exit 1
fi

echo
echo "DONE — all subjects passed"
