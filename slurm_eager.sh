#!/bin/bash -l
#SBATCH --job-name=EagerAnalysis
#SBATCH --partition=short
#SBATCH --ntasks=8
#SBATCH --mem 20G
#SBATCH -e slurm-%j_%x.out
#SBATCH -o slurm-%j_%x.out

# This script file is used to start a SLURM job with nf-core/eager pipeline on your data.
# REQUIREMENTS:
# - Java's module openjdk-18 (available by default on anthill 4.0 server)
# - Nextflow version with DSL1. To download it please refer to the Markdown Tutorial provided at: https://github.com/LPCG-ancientDNA-Warsaw/nfcore-eager-LPCG/blob/b2d0c4156b7b0df9e181abcc3a68020bb6c51261/Tutorial_new_server.md
# 	This tutorial assumes that the DSL1 compliant version of Nextflow is saved under the name 'nextflow_dsl1': if saved under a different name, please specify it with the appropriate flag (Illustrated below)
# - nf-core/eager pipeline installed on your account.


# Define default parameters
NEXTFLOW_VERSION="nextflow_dsl1"
SINGULARITY_VERSION="2.5.1"
REFERENCE="/mnt/workspace03/gr7001/share/references/hs37d5.fa"
BWA_INDEX_PATH="/mnt/workspace03/gr7001/share/references/"

source /etc/profile.d/modules.sh || . /usr/share/modules/init/bash

# Flags usage
usage() {
echo "Usage: $0 [OPTIONS]"
echo "Options:"
echo " -b, --bwa_index		Path to a bwa index file (.bai), in accordance with the fasta reference file provided. DEFAULT: /mnt/workspace03/gr7001/share/references/ (index built on Human Reference Genome hs37d5)."
echo " -i, --input		Input .tsv file with samples information, built following nf-core/eager documentation (https://nf-co.re/eager/2.3.3/docs/usage/#tsv-input-method)."
echo " -n, --nextflow		Installed Nextflow version (with DSL1) name. DEFAULT: nextflow_dsl1."
echo " -o, --outdir		Path to a directory where to store the results. DEFAULT: ./results (created if not present in the current directory)"
echo " -r, --reference		Fasta file with reference genome. DEFAULT: /mnt/workspace03/gr7001/share/references/hs37d5.fa (Human)"
echo " -s, --singularity		Singularity version. DEFAULT: 2.5.1."
}

# Function to check which flag (short or long) was provided
has_argument() {
[[ ("$1" == *=* && -n ${1#*=}) || (! -z "$2"&& "$2" != -*) ]];
}

# Function to extract the argument provided
extract_argument() {
echo "${2:-${1#*=}}"
}

# Function to read the flags provided
handle_options() {
	while [ $# -gt 0 ]; do
		case $1 in
			-r | --reference*)
				if ! has_argument $@; then
					echo "Reference genome not provided. Setting it to default."
					shift
					continue
				else
					REFERENCE=$(extract_argument $@)
					if [[ "$1" == *=* ]]; then
						shift 1
					else
						shift 2
					fi
					continue
				fi
			;;
			-b | --bwa_index*)
				if ! has_argument $@; then
					echo "Bwa index not specified. Checking the provided reference..."
					if [ "$REFERENCE" = "/home/users/fleotta/common_files/references/hs37d5.fa" ]; then
						echo "Using default reference genome and bwa index."
						BWA_INDEX_PATH="/home/users/fleotta/common_files/references/"
						if [[ "$1" == *=* ]]; then
							shift 1
						else
							shift 2
						fi
						continue
					else
						echo "A bwa index will be created based on the reference genome provided."
						BWA_INDEX_PATH=""
						shift
						continue
					fi
				else
					BWA_INDEX_PATH=$(extract_argument $@)
					if [[ "$1" == *=* ]]; then
						shift 1
					else
						shift 2
					fi
					continue
				fi
			;;
			-i | --input*)
				if ! has_argument $@; then
					echo "No input file provided. Exiting..."
					exit 1
				else
					INPUT=$(extract_argument $@)
					if [[ "$1" == *=* ]]; then
						shift 1
					else
						shift 2
					fi
					continue
				fi
			;;
			-n | --nextflow*)
				if ! has_argument $@; then
					echo "No nextflow name provided. Using default name."
					shift
					continue
				else
					NEXTFLOW_VERSION=$(extract_argument $@)
					if [[ "$1" == *=* ]]; then
						shift 1
					else
						shift 2
					fi
					continue
				fi
			;;
			-s | --singularity*)
				if ! has_argument $@; then
					echo "No singularity version provided. Using default name."
					shift
					continue
				else
					SINGULARITY_VERSION=$(extract_argument $@)
					if [[ "$1" == *=* ]]; then
						shift 1
					else
						shift 2
					fi
					continue
				fi
			;;
			-o | --outdir*)
				if ! has_argument $@; then
					echo "No output directory provided. Creating one..."
					shift
					continue
				else
					OUTDIR=$(extract_argument $@)
					if [[ "$1" == *=* ]]; then
						shift 1
					else
						shift 2
					fi
					continue
				fi
			;;
			*)
				echo "Invalid option: $1" >&2
				usage
				exit 1
			;;
			esac
			shift
	done
}

# Loading the right module for java
module load java/openjdk-18

# Read flags' arguments
handle_options "$@"

# If no input is provided, kill the process
if [ -z "$INPUT" ]; then
    echo "Input file required"
    exit 1
fi

# If no output directory is provided, create one
if [ -z "$OUTDIR" ]; then
    OUTDIR="./results"
    mkdir -p "$OUTDIR"
fi

# Check if a bwa index was provided
BWA_ARG=""
[ -n "$BWA_INDEX_PATH" ] && BWA_ARG="--bwa_index $BWA_INDEX_PATH"

# Check if the singularity version provided is the default one: if yes, use the singularity image (.sif) already downloaded. This speeds up the process significantly.
SINGULARITY_ARG=""
if [ "$SINGULARITY_VERSION" = "2.5.1" ]; then
    SINGULARITY_ARG="-with-singularity /mnt/workspace03/gr7001/share/singularity_images/nfcore-eager-2.5.1.sif"
fi


# Finally run eager

$NEXTFLOW_VERSION run -resume nf-core/eager \
    -profile singularity \
    -r $SINGULARITY_VERSION \
    $SINGULARITY_ARG \
    --input $INPUT \
    --fasta $REFERENCE \
    $BWA_ARG \
    --outdir $OUTDIR