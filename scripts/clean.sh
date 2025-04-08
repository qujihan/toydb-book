#!/bin/bash

[ -d "../output" ] && rm -rf ../output
find ../scripts -type f ! -name "*.sh" -exec rm -f {} +;
find ../scripts -type d -empty -delete