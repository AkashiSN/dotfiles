#!/usr/bin/env python3
import os
import argparse
import PyPDF2 as pp2

parser = argparse.ArgumentParser()

parser.add_argument("file")
parser.add_argument("-n", "--pagenumber", help="Target page number", type=int, default=0)
parser.add_argument("-r", "--rotate", help="Rotate angle", type=int, default=-90)

args = parser.parse_args()

inputFile = os.path.abspath(args.file)
dirname = os.path.dirname(inputFile)
basename = os.path.basename(inputFile).split('.pdf')[0]
outputFile=os.path.join(dirname, basename+'-rotate.pdf')

reader = pp2.PdfReader(inputFile)
writer = pp2.PdfWriter()

for pages in reader.pages:
    writer.add_page(pages)

writer.pages[args.pagenumber].rotate(args.rotate)

with open(outputFile, "wb") as fp:
    writer.write(fp)
    print(outputFile)
