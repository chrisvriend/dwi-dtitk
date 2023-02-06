#!/usr/bin/env python3.8


import argparse
import math

parser = argparse.ArgumentParser('Copy the specified white space seperated columns from one file into the other')
parser.add_argument('file_in', help='Input file name from which to select the columns')
parser.add_argument('file_out', help='Output file to write the columns into')
parser.add_argument('indices', type=int, nargs='+', help='Indices of columns to be copied ( zero based )')
args = parser.parse_args()

out_text=''
with open(args.file_in,'r') as f_in:
    for line in f_in:
        all = line.split()
        selected = [all[i] for i in args.indices]
        #print(selected)
        out_text+=' '.join(selected)+'\n'

with open(args.file_out,'w') as f_out:
       f_out.writelines(out_text)
