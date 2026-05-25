#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl
# Modified for efficiency: dependency chains, generic subject glob,
# configurable simul, fixed log naming, set -euo pipefail,
# scriptdir exported so all sbatch jobs can find config.sh,
# --kill-on-invalid-dep=yes so downstream jobs are cancelled on failure
#
# NOTE: Run this script as a plain bash script from a login node in
# screen/tmux rather than as an sbatch job. It submits all stages
# with SLURM dependency chains and exits immediately after submission.
#
# Usage:
#   bash ./000-DTITK_wrapper_sbatch.sh <preprocdir> <workdir> <outputdir> [simul]

set -euo pipefail

# ── Usage ─────────────────────────────────────────────────────────────────────
Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC - 000-DTITK_wrapper_sbatch.sh

    Wrapper script: submits all DTI-TK pipeline stages to SLURM using
    dependency chains. Exits immediately after submission.

    Usage: bash ./000-DTITK_wrapper_sbatch.sh preprocdir workdir outputdir [simul]

    Obligatory:
      preprocdir  full path to preprocessed DWI derivatives
      workdir     full path to working directory
      outputdir   full path to final output directory

    Optional:
      simul       max simultaneous array tasks (default: 7)

EOF
    exit 1
}

[ _${2:-} = _ ] && Usage

# ── Inputs ────────────────────────────────────────────────────────────────────
preprocdir=${1}
workdir=${2}
outputdir=${3}
simul=${4:-7}

simulreg=$(( ${simul} * 2 ))  # more simultaneous tasks for registration stages since they are faster than warping
# Resolve scriptdir once on the login node as an absolute path.
# Exported so every sbatch job receives it as an environment variable
# and does not need to re-derive it from BASH_SOURCE[0].
export scriptdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ── Source site config ────────────────────────────────────────────────────────
source "${scriptdir}/config.sh"

# ── Pipeline parameters ───────────────────────────────────────────────────────
Niter=5
bshell=${bshell:-1000}

# ── Locate subjects ───────────────────────────────────────────────────────────
cd "${preprocdir}"

mapfile -t subj_array < <(ls -d sub-*/ 2>/dev/null | sed 's:/.*::')

if [ ${#subj_array[@]} -eq 0 ]; then
    echo "ERROR: no subject directories (sub-*/) found in ${preprocdir}" >&2
    exit 1
fi

printf '%s\n' "${subj_array[@]}" > subjects.txt
nsubj=${#subj_array[@]}
echo "Found ${nsubj} subjects in ${preprocdir}"

mkdir -p "${workdir}"
mkdir -p "${workdir}/logs"

# ── Common sbatch flags ───────────────────────────────────────────────────────
# --kill-on-invalid-dep=yes  : automatically cancel jobs whose upstream
#                              dependency failed (avoids orphaned queue entries)
# --export                   : pass scriptdir to every job so config.sh is found
sbatch_common=(
    --kill-on-invalid-dep=yes
    --export="ALL,scriptdir=${scriptdir}"
)

# =============================================================================
# STAGE 1 – fit + intra-subject registration (array)
# =============================================================================
echo "Submitting stage 1: fit + intra-subject registration (array 1-${nsubj}%${simul})"
jid1=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --array="1-${nsubj}%${simul}" \
    --job-name=dtitk-fit \
    --output="${workdir}/logs/1-DTITK_%A_%a.log" \
    "${scriptdir}/01a-DTITK_fit+intrareg.sh" \
        "${preprocdir}" "${workdir}" "${preprocdir}/subjects.txt")
echo "  -> job ${jid1}"

# =============================================================================
# STAGE 1b – check fit
# =============================================================================
echo "Submitting stage 1b: check fit (depends on ${jid1})"
jid1b=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid1} \
    --job-name=dtitk-checkfit \
    --mem=2G \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-0:15:00 \
    --output="${workdir}/logs/1b-DTITK_checkfit_%j.log" \
    --wrap="bash ${scriptdir}/01b-DTITK_checkfit.sh ${workdir} ${scriptdir}")
echo "  -> job ${jid1b}"

# =============================================================================
# STAGE 2a – prepare inter-subject registration
# =============================================================================
echo "Submitting stage 2a: prep inter-reg (depends on ${jid1b})"
jid2a=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid1b} \
    --job-name=dtitk-prepinterreg \
    --mem=2G \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-0:15:00 \
    --output="${workdir}/logs/2a-DTITK_prepinterreg_%j.log" \
    --wrap="bash ${scriptdir}/02a-DTITK_prepinterreg.sh ${workdir} ${scriptdir}")
echo "  -> job ${jid2a}"

# =============================================================================
# STAGE 2b – inter-subject rigid registration
# =============================================================================
echo "Submitting stage 2b: inter-reg rigid (depends on ${jid2a})"
jid2b=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid2a} \
    --job-name=dtitk-interreg-rigid \
    --mem=4G \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-2:00:00 \
    --output="${workdir}/logs/2b-DTITK_interreg-rigid_%j.log" \
    --wrap="bash ${scriptdir}/02b-DTITK_interreg-rigid.sh \
        ${workdir}/interreg ${scriptdir} ${IXITEMPLATE} inter_subjects.txt ${simul}")
echo "  -> job ${jid2b}"

# =============================================================================
# STAGE 2c – inter-subject affine registration
# =============================================================================
echo "Submitting stage 2c: inter-reg affine (depends on ${jid2b})"
jid2c=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid2b} \
    --job-name=dtitk-interreg-affine \
    --mem=4G \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-4:00:00 \
    --output="${workdir}/logs/2c-DTITK_interreg-affine_%j.log" \
    --wrap="bash ${scriptdir}/02c-DTITK_interreg-affine.sh \
        ${workdir}/interreg ${scriptdir} inter_subjects.txt ${Niter} ${simul}")
echo "  -> job ${jid2c}"

# =============================================================================
# STAGE 2c-post – build inter_subjects_aff.txt
# =============================================================================
echo "Submitting stage 2c-post: build aff list (depends on ${jid2c})"
jid2cpost=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid2c} \
    --job-name=dtitk-afflist \
    --mem=500M \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-0:05:00 \
    --output="${workdir}/logs/2c-post_%j.log" \
    --wrap="cd ${workdir}/interreg && \
            mkdir -p logs && \
            mv *.log logs/ 2>/dev/null || true && \
            ls -1 sub-*_aff.nii.gz > inter_subjects_aff.txt")
echo "  -> job ${jid2cpost}"

# =============================================================================
# STAGE 2d – inter-subject diffeomorphic registration
# =============================================================================
echo "Submitting stage 2d: inter-reg diffeo (depends on ${jid2cpost})"
jid2d=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid2cpost} \
    --job-name=dtitk-interreg-diffeo \
    --mem=1G \
    --partition=luna-cpu-long \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-16:00:00 \
    --output="${workdir}/logs/2d-DTITK_interreg-diffeo_%j.log" \
    --wrap="bash ${scriptdir}/02d-DTITK_interreg-diffeo.sh \
        ${workdir}/interreg ${scriptdir} \
        mean_affine${Niter}.nii.gz mask.nii.gz inter_subjects_aff.txt ${simul}")
echo "  -> job ${jid2d}"

# =============================================================================
# STAGE 3a – warp subjects to template (array)
# =============================================================================
echo "Submitting stage 3a: warp to template (array, depends on ${jid2d})"
jid3a=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid2d} \
    --array="1-${nsubj}%${simul}" \
    --job-name=dtitk-warp2template \
    --output="${workdir}/logs/3a-DTITK_%A_%a.log" \
    "${scriptdir}/03a-DTITK_warp2template.sh" ${scriptdir}\
        "${workdir}" "${bshell}" "${preprocdir}/subjects.txt")
echo "  -> job ${jid3a}"

# =============================================================================
# STAGE 3b – warp QC figures
# =============================================================================
echo "Submitting stage 3b: warp QC (depends on ${jid3a})"
jid3b=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid3a} \
    --job-name=dtitk-warpqc \
    --mem=500M \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-0:30:00 \
    --output="${workdir}/logs/3b-DTITK_warpqc_%j.log" \
    --wrap="bash ${scriptdir}/03b-DTITK_warpqc.sh ${scriptdir} ${workdir}/warps")
echo "  -> job ${jid3b}"

# =============================================================================
# STAGE 4 – extract diffusion maps (array)
# =============================================================================
echo "Submitting stage 4: make diffusion maps (array, depends on ${jid3b})"
jid4=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid3b} \
    --array="1-${nsubj}%${simul}" \
    --job-name=dtitk-diffmaps \
    --output="${workdir}/logs/4-DTITK_%A_%a.log" \
    "${scriptdir}/004-DTITK_makediffmaps.sh" \
        "${workdir}" "${bshell}" "${preprocdir}/subjects.txt")
echo "  -> job ${jid4}"

# =============================================================================
# STAGE 5 – TBSS skeleton
# =============================================================================
echo "Submitting stage 5: TBSS (depends on ${jid4})"
jid5=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid4} \
    --job-name=dtitk-tbss \
    --mem=8G \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-1:00:00 \
    --output="${workdir}/logs/5-DTITK_TBSS_%j.log" \
    --wrap="ln -sf ${workdir}/warps/mean_final_high_res.nii.gz \
                   ${workdir}/diffmaps/mean_final_high_res.nii.gz 2>/dev/null || true && \
            bash ${scriptdir}/005-DTITK_TBSS.sh ${workdir}/diffmaps")
echo "  -> job ${jid5}"

# =============================================================================
# STAGE 6 – warp JHU atlas to template
# =============================================================================
echo "Submitting stage 6: warp atlas (depends on ${jid5})"
jid6=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid5} \
    --job-name=dtitk-atlas \
    --output="${workdir}/logs/6-DTITK_atlas_%j.log" \
    "${scriptdir}/006-DTITK_warpatlas2template.sh" \
        "${workdir}" "${scriptdir}/JHU-ICBM.labels")
echo "  -> job ${jid6}"

# =============================================================================
# STAGE 6-post – build tractfile.txt
# =============================================================================
echo "Submitting stage 6-post: build tractfile (depends on ${jid6})"
jid6post=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid6} \
    --job-name=dtitk-tractfile \
    --mem=500M \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-0:05:00 \
    --output="${workdir}/logs/6-post_%j.log" \
    --wrap="cd ${workdir}/tracts && \
            ls -1 JHU*.nii.gz > tractfile.txt && \
            sed -i '/JHU-ICBM-labels_templatespace.nii.gz/d' tractfile.txt && \
            sed -i 's/.nii.gz//' tractfile.txt")
echo "  -> job ${jid6post}"

# =============================================================================
# STAGE 7 – extract median diffusion values (array)
# =============================================================================
echo "Submitting stage 7: extract diff values (array, depends on ${jid6post})"
jid7=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid6post} \
    --array="1-${nsubj}%${simul}" \
    --job-name=dtitk-extractdiff \
    --output="${workdir}/logs/7-DTITK_%A_%a.log" \
    "${scriptdir}/007-DTITK_extract-diffvalues.sh" \
        "${workdir}" "${workdir}/tracts/tractfile.txt" "${scriptdir}" \
        "${preprocdir}/subjects.txt")
echo "  -> job ${jid7}"

# =============================================================================
# STAGE 8 – write output
# =============================================================================
echo "Submitting stage 8: write output (depends on ${jid7})"
jid8=$(sbatch --parsable \
    "${sbatch_common[@]}" \
    --dependency=afterok:${jid7} \
    --job-name=dtitk-output \
    --mem=500M \
    --partition="${SLURM_PARTITION}" \
    --qos="${SLURM_QOS}" \
    --cpus-per-task=1 \
    --time=00-0:30:00 \
    --output="${workdir}/logs/8-DTITK_output_%j.log" \
    --wrap="bash ${scriptdir}/008-DTITK_write-output.sh \
        ${workdir} ${outputdir} ${bshell}")
echo "  -> job ${jid8}"

# =============================================================================
echo ""
echo "All stages submitted. Dependency chain:"
echo "  1 (${jid1}) -> 1b (${jid1b}) -> 2a (${jid2a}) -> 2b (${jid2b})"
echo "  -> 2c (${jid2c}) -> 2c-post (${jid2cpost}) -> 2d (${jid2d})"
echo "  -> 3a (${jid3a}) -> 3b (${jid3b}) -> 4 (${jid4})"
echo "  -> 5 (${jid5}) -> 6 (${jid6}) -> 6-post (${jid6post})"
echo "  -> 7 (${jid7}) -> 8 (${jid8})"
echo ""
echo "Monitor with: squeue -u \${USER}"
echo "Final output will be written to: ${outputdir}"
