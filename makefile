.PHONY: all

pwd := $(shell pwd)
src_dir := $(pwd)
output_dir := $(pwd)/output

all: fonts build

fonts:
	@echo "Download Fonts ..."
	@bash ./scripts/download_fonts.sh || echo "\033[0;31m Error: Failed to download fonts"

build:
	@echo "Building..."
	@bash ./scripts/build_all_pdf.sh ${src_dir} ${output_dir} || echo "\033[0;31m Error: Failed to build PDF"

clean:
	@echo "Cleaning..."
	@bash ./scripts/clean.sh || echo "\033[0;31m Error: Failed to clean"