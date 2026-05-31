#!/usr/bin/env python3
import os
import argparse
import PyPDF2 as pp2

parser = argparse.ArgumentParser()

parser.add_argument("--files", required=True, nargs="*", help="Concat pdf files", type=str)
args = parser.parse_args()

inputFile = os.path.abspath(args.files[0])
dirname = os.path.dirname(inputFile)
basename = os.path.basename(inputFile).split('.pdf')[0]
outputFile=os.path.join(dirname, basename+'-concat.pdf')

merger = pp2.PdfMerger()

for file in args.files:
    inputFile = os.path.abspath(file)
    merger.append(inputFile)

merger.write(outputFile)
merger.close()
