# DTITK INTER/INTRA TEMPLATE CREATION AND EXTRACTING DTI & NODDI MEASURES FROM WHITE-MATTER TRACTS 
# AN AUTOMATED SLURM PIPELINE
(C) Chris Vriend - Amsterdam UMC - Jul ' 23

c.vriend|amsterdamumc-dot-nl

 DTITK template creation and extract diffusion measures from b1000 shell and NODDI measures

 The main script to call is 000-DTITK_wrapper_sbatch.sh. This script functions as a wrapper that calls all other scripts and submits them to the slurm scheduler (e.g. 001-DTITK_fit+intrareg.sh, 02a-DTITK_prepinterreg.sh, etc.)
 The wrapper script requires two inputs: the full path to a folder that contains (1) your subject-specific and preprocessed DWI folders (containing bvecs bvals and single/multishell DWI data), (2) folder where all the data will be processed. All subjec-specific folders need to start with sub-*. There is also a "scripts" folder that contains all the *.sh, *.py and JHU-ICBM.labels files (all available here in this GitHub repository)

In case of longitudinal data the script expects two or more ses-Tx subfolders where x stands for the timepoint, e.g. T0 and T1. see also the "data structure heading" in the 000-DTITK_wrapper_sbatch.sh script. In case of cross-sectional data, files should be saved directly in the folder dwi under the subject-specific folder.
Additional help info is provided in the scripts + usage information. (more info may be added in future updates). The scripts have been optimized for use on the Luna AmsUMC server and requires specification of the partition (e.g. luna-cpu-short, luna-cpu-long).
The run time depends on the number of subjects in your dataset (and what you specify for the "simul" variable that sets the number of simultaneous processes/subjects to run).
Test runs with 12 subjects took approximately 3 hours. Adjust your session (and partition) accordingly.

example command:
sbatch ./000-DTITK_long_wrapper_sbatch.sh ~/my-scratch/mri-project/derivatives/dwi-preproc ~/my-scratch/DTITK_mysample

don't forget to change the input variables in that script before running (e.g. the number of subjecs to process simultaneously )


