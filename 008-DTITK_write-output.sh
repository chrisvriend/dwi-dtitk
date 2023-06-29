#!/bin/bash

# Written by C. Vriend - AmsUMC Jan 2023
# c.vriend@amsterdamumc.nl

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - 2/3/2023 - 07-DTITK_extract-diffvalues.sh
   
    Usage: ./07-DTITK_extract-diffvalues.sh workdir tractfile
    Obligatory: 
    workdir = full path to working (head) directory where all folders are situated, including the subject folders (see wrapper script)
    tractdir = full path to folder with tracts in templatespace, produced by previous 06-DTITK_warpatlas2template.sh script
    scriptdir
EOF
    exit 1
}

[ _$3 = _ ] && Usage


workdir=${1}
outputdir=${3}
diffdir=${workdir}/diffmaps
tractdir=${workdir}/tracts

cd ${workdir}
for subj in $(ls -d sub-*); do 




cd ${diffdir}


##################################################################