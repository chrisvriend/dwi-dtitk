#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Fri Feb  3 14:17:57 2023

@author: cvriend

"""

import os
import pandas as pd
import argparse

class UnexpectedNdiff(Exception):
    pass

parser = argparse.ArgumentParser('restructure txt files with diffusion measures into csv table format')

# required arguments
parser.add_argument('--workdir', action="store", dest="workdir", required=True,
                    help='working directory, generally folder with diffusion maps')
parser.add_argument('--outdir', action="store", dest="outdir", required=True,
                    help='output directory for csv files ')
parser.add_argument('--subjid', action="store", dest="subjid", required=True,
                    help='subject ID')

args = parser.parse_args()

workdir=args.workdir
outputdir=args.outdir
subjid=args.subjid


diffnoddi=['AD', 'FA', 'MD', 'RD', 'OD', 'ND','FW']
diff=['AD', 'FA', 'MD', 'RD']


# list comprehension | find directories in work directory that start with sub-
diff_files=[ diff_files for diff_files in os.listdir(workdir)
       if diff_files.endswith('diffvalues.txt') and diff_files.startswith(subjid)];
diff_files.sort()

os.chdir(workdir)

list_df=[]
for diff_file in diff_files:
    
    df=pd.read_csv(diff_file,delim_whitespace=True,header=None)
    temp=diff_file.split('_diffvalues')[0].split(subjid + '_')[1]
    df.columns=[temp]

    if df.shape[0] == 7:
        df['diff']=diffnoddi
    elif df.shape[0] == 4:    
        df['diff']=diff
    else:
        raise UnexpectedNdiff("Error: Unexpected number of diff measures. Script cannot continue.")

    df=df.set_index(['diff'])
    list_df.append(df)

df2=pd.concat(list_df,axis=1)
df2.to_csv(os.path.join(outputdir,(subjid + '_diffvalues.csv')))
