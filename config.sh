#!/bin/bash

# ============================================================
# config.sh  –  site-specific variables for dwi-dtitk pipeline
# Source this file from every script:  source ${scriptdir}/config.sh
# ============================================================

# --- Software module versions ---
export DTITK_VERSION=2.3.1
export FSL_VERSION=6.0.7.6
export ANTS_VERSION=2.5.1
export ANACONDA_VERSION=2024.02-1

# --- Python / conda environment ---
export PYTHON_ENV=/scratch/anw/share/python-env/mrtrix

# --- External tool paths ---
export SYNTHSTRIP=/scratch/anw/share-np/fmridenoiser/synthstrip.1.2.sif

# --- Templates ---
export IXITEMPLATE=/data/anw/anw-work/NP/doorgeefluik/ixi_aging_template_v3.0/template/ixi_aging_template.nii.gz
export IXITEMPLATE_DIR=/data/anw/anw-work/NP/doorgeefluik/ixi_aging_template_v3.0/template

# --- SLURM partition / QOS ---
export SLURM_PARTITION=luna-cpu-short
export SLURM_QOS=anw-cpu

# --- shell ---
export bshell=1000

# ============================================================
# Do NOT edit below this line unless you know what you are doing
# ============================================================
export DTITK_USE_QSUB=0
