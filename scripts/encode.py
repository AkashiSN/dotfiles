#!/usr/bin/env python3
import subprocess
import pathlib
import shutil
import glob
import sys
import os

def long_substr(data):
    substr = ''
    if len(data) > 1 and len(data[0]) > 0:
        for i in range(len(data[0])):
            for j in range(len(data[0])-i+1):
                if j > len(substr) and all(data[0][i:i+j] in x for x in data):
                    substr = data[0][i:i+j]
        return substr

if len(sys.argv) > 1:
    files = [pathlib.Path(f).name for f in sys.argv[1:]]
    with open("input.txt", mode='w') as f:
        f.write("file " + "\nfile ".join(files))
    outfile = long_substr(files).rstrip("_")
    command = "ffmpeg -f concat -i input.txt -c copy -y {}.mp4".format(outfile)
    if subprocess.call(command, shell=True):
        os.remove("input.txt")
else:
    files = list(pathlib.Path(".").glob("**/*.mp4"))
    for f in files:
        command="ffmpeg -i \"{}\" "\
                "-c:v h264_nvenc "\
                "-c:a aac -ab 128k "\
                "-f mp4 -y \"{}\"".format(str(f), str(f)+".new")
        subprocess.call(command, shell=True)
    files = list(pathlib.Path(".").glob("**/*.new"))
    for f in files:
        shutil.move(str(f), str(f.parent.joinpath(f.stem)))
