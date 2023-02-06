# DTITK_template-diffvalues
(C) Chris Vriend - Amsterdam UMC - feb ' 23

c.vriend<at>amsterdamumc-dot-nl

 DTITK template creation and extract diffusion measures from b1000 shell and NODDI measures

 The main script to call is 00-DTITK_[pipeline]_wrapper_sbatch.sh where [pipeline] is either cross or long depending on whether you are processing cross-sectional or longitudinal data. This script functions as a wrapper that calls all other scripts and submits them to the slurm scheduler (e.g. 01-DTITK_cross_fit.sh, 2a-DTITK_cross_prepinterreg.sh, etc.)
 The wrapper script requires one input: the full path to a folder that contains (1) your subject-specific DWI folders (containing bvecs bvals and data.nii.gz with single/multishell DWI data), (2) where all the processed data will be written to. all subjec-specific folders need to start with sub-*, and (3) a "scripts" folder that contains all the *.sh, *.py and JHU-ICBM.labels files (all available here in this GitHub repository)

In case of longitudinal data the script expects two or more Tx subfolders where x stands for the timepoint, e.g. T0 and T1. see also the "data structure heading" in the 00-DTITK_[pipeline]_wrapper_sbatch.sh script. In case of cross-sectional data, the bvecs, bvals and data.nii.gz files should be saved directly under the subject-specific folder.
Additional help info is provided in the scripts + usage information. (more info may be added in future updates). The scripts have been optimized for use on the Luna AmsUMC server and requires specification of the partition (e.g. luna-cpu-short, luna-cpu-long).
The run time depends on the number of subjects in your dataset (and what you specify for the "simul" variable that sets the number of simultaneous processes/subjects to run).
Test runs with 12 subjects took approximately 3 hours. Adjust your session (and partition) accordingly.

example command:
sbatch ./00-DTITK_long_wrapper_sbatch.sh ~/my-scratch/DTITK_mysample

don't forget to change the input variables in that script before running (i.e. the path to the NODDIarchive and the number of subjecs to process simultaneously )


