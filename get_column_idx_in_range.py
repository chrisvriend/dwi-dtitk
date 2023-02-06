#!/usr/bin/env python3.8


import argparse
import math

parser = argparse.ArgumentParser('Get the indices of the columns which first frow lie within the specified range')
parser.add_argument('bval', help='bval input file name')
parser.add_argument('min', type=float, help='minimum value to be selected')
parser.add_argument('max', type=float, help='maximum value to be selected')
args = parser.parse_args()

with open(args.bval,'r') as f:
    bval = [float(val) for val in f.readline().split()]

indices=[]
for idx, val in enumerate(bval):
    if val >= args.min and val <= args.max :
        indices.append( str(idx) )

print( ' '.join(indices) )
