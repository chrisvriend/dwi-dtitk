#!/bin/bash
# Written by C. Vriend - AmsUMC Jan 2023
# Modified: SLURM job-array parallelisation of per-subject QC step

set -euo pipefail

Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 03b-DTITK_warpqc.sh
    Computes the mean warped DTI image across all subjects, extracts
    the L3 eigenvalue map for registration quality inspection, and
    generates per-subject overlay PNGs via a SLURM job array.

    Usage: bash ./03b-DTITK_warpqc_slurm.sh <scriptdir> <warpdir>
      scriptdir  directory containing this script and config.sh
      warpdir    full path to directory containing warped subject images
                 (*_space-template_desc-b*_res-?mm_dtitk.nii.gz)

EOF
    exit 1
}

[ _${2:-} = _ ] && Usage

scriptdir=${1}
warpdir=${2}

source "${scriptdir}/config.sh"

module load dtitk/${DTITK_VERSION}
module load fsl/${FSL_VERSION}

if [ ! -d "${warpdir}" ]; then
    echo "ERROR: warpdir not found: ${warpdir}" >&2
    exit 1
fi

cd "${warpdir}"

echo "Making overlays for quality inspection"

# ── collect warped scans ────────────────────────────────────────────────────
mapfile -t warped_scans < <(ls -1 *res-?mm_dtitk.nii.gz 2>/dev/null)

if [ ${#warped_scans[@]} -eq 0 ]; then
    echo "ERROR: no warped scans (*res-?mm_dtitk.nii.gz) found in ${warpdir}" >&2
    exit 1
fi

echo "Found ${#warped_scans[@]} warped scans"

printf '%s\n' "${warped_scans[@]}" > subjs_warped.txt

# ── Step 1: mean image (serial — fast, single call) ─────────────────────────
if [ ! -f mean_final_high_res.nii.gz ]; then
    echo "Computing mean warped image"
    TVMean -in subjs_warped.txt -out mean_final_high_res.nii.gz
else
    echo "mean_final_high_res.nii.gz already exists — skipping TVMean"
fi

# ── Step 2: L3 reference map (serial — single call) ─────────────────────────
if [ ! -f mean_final_high_res_regcheck.nii.gz ]; then
    echo "Extracting L3 eigenvalue map for QC reference"
    TVEigenSystem -in mean_final_high_res.nii.gz -type FSL
    mv mean_final_high_res_L3.nii.gz mean_final_high_res_regcheck.nii.gz
    rm -f mean_final_high_res_??.nii.gz
else
    echo "mean_final_high_res_regcheck.nii.gz already exists — skipping"
fi

mkdir -p "${warpdir}/QC"

# ── Step 3: per-subject QC — submit as a SLURM job array ────────────────────
# Write the subject list so the array worker can index into it
printf '%s\n' "${warped_scans[@]}" > "${warpdir}/subjs_warped_list.txt"
n_subjs=${#warped_scans[@]}

echo "Submitting SLURM job array (1-${n_subjs}) for per-subject QC overlays"

sbatch \
    --job-name=dtitk_qc \
    --array=1-${n_subjs}%20 \
    --time=00:05:00 \
    --mem=500M \
    --cpus-per-task=1 \
    --output="${warpdir}/QC/slurm-%A_%a.out" \
    --wrap="
        set -euo pipefail
        source '${scriptdir}/config.sh'
        module load dtitk/\${DTITK_VERSION}
        module load fsl/\${FSL_VERSION}

        # pick this task's scan from the list (1-based SLURM_ARRAY_TASK_ID)
        subj_scan=\$(sed -n \"\${SLURM_ARRAY_TASK_ID}p\" '${warpdir}/subjs_warped_list.txt')
        cd '${warpdir}'

        stem=\${subj_scan%_space-template_desc-b\${bshell}*}
        stam=\${subj_scan%.nii.gz}

        echo \"-------- \${stem} --------\"

        if [ -f '${warpdir}/QC/\${stem}_overlay.png' ]; then
            echo 'QC overlay already exists — skipping'
            exit 0
        fi

        # Use a per-job temp dir to avoid filename collisions between tasks
        tmpdir=\$(mktemp -d '${warpdir}/tmp_qc_XXXXXX')
        trap 'rm -rf \"\${tmpdir}\"' EXIT

        cp '${warpdir}/\${subj_scan}' \"\${tmpdir}/\"
        cd \"\${tmpdir}\"

        TVEigenSystem -in \"\${subj_scan}\" -type FSL
        slicer '${warpdir}/mean_final_high_res_regcheck.nii.gz' \
               \"\${stam}_L3.nii.gz\" \
               -a '${warpdir}/QC/\${stem}_overlay.png'
    "

echo
echo "Job array submitted. Monitor with: squeue -u \$USER"
echo "QC overlays will be written to ${warpdir}/QC"
