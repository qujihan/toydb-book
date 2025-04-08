#!/bin/bash

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m"

src_dir="$1" && output_dir="$2" &&
    mkdir -p ${output_dir} &&
    printf "${YELLOW}src dir: ${src_dir}, output dir: ${output_dir}${NC}\n"

[[ -d "${src_dir}" ]] || (printf "${RED}src dir: ${src_dir} is not a directory${NC}\n" && exit 1)
[[ -d "${output_dir}" ]] || (printf "${RED}output dir: ${output_dir} is not a directory${NC}\n" && exit 1)

for dir in ${src_dir}/*; do
    [[ -d "${dir}" ]] || continue
    [[ -f "${dir}/makefile" ]] || continue
    printf "${GREEN}build pdf in ${dir}${NC}\n"
    make -C "${dir}" c && mv "${dir}"/*.pdf ${output_dir} || (printf "${RED} build ${dir} failed ${NC}\n" && exit 1)
done
