#!/bin/bash -l
#SBATCH --job-name=EagerAnalysis
#SBATCH --partition=long
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

COMMON_PATH="/mnt/workspace03/gr7001/share"
# Define default parameters
NEXTFLOW_VERSION="nextflow_dsl1"
SINGULARITY_VERSION="2.5.1"
CONFIG_NAME="lpcg_human"
CONFIG_FILE="$COMMON_PATH/conf/$CONFIG_NAME.config"


export JAVA_HOME="/opt/jdk-18/"
export PATH="$JAVA_HOME/bin:$PATH"

# Flags usage
usage() {
echo "Usage: $0 [OPTIONS]"
echo "Options:"
echo " -c, --config		Configuration name. DEFAULT: 'lpcg_human'."
echo " -i, --input		Input .tsv file with samples information, built following nf-core/eager documentation (https://nf-co.re/eager/2.3.3/docs/usage/#tsv-input-method)."
echo " -n, --nextflow		Installed Nextflow version (with DSL1) name. DEFAULT: nextflow_dsl1."
echo " -o, --outdir		Path to a directory where to store the results. DEFAULT: ./results (created if not present in the current directory)"
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
			-c | --config*)
				if ! has_argument $@; then
					echo "No config file provided. Using default: $CONFIG_FILE"
					shift
					continue
				else
					CONFIG_FILE="$COMMON_PATH/conf/$(extract_argument "$@").config"
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


# Read flags' arguments
handle_options "$@"

# If no output directory is provided, create one
if [ -z "$OUTDIR" ]; then
    OUTDIR="./results"
    mkdir -p "$OUTDIR"
fi

# ==============================================================================
# LOGGING CONFIGURATION
# ==============================================================================
# CONFIG_FILE="$COMMON_PATH/conf/$CONFIG_NAME.config"
LOG_DIR="$COMMON_PATH/eager_outputs/logs"
mkdir -p "$LOG_DIR"

DATE_STR=$(date +%Y-%m-%d)

PROJ_NAME=$(echo "$OUTDIR" | grep -oP 'eager_outputs/\K[^/]+' || echo "default")

# Verifica se il run è su BAM (merged) o FASTQ
IS_MERGED=""
if [[ "$OUTDIR" == *"_merged"* ]]; then
    IS_MERGED="_merged"
fi

LOG_FILE="$LOG_DIR/${DATE_STR}_${PROJ_NAME}${IS_MERGED}.log"

log_event() {
    local status="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [JOB: ${SLURM_JOB_ID:-N/A}] [$status] - $message" >> "$LOG_FILE"
}

log_event "SCHEDULED/STARTED" "Pipeline execution started for Input: $INPUT | Outdir: $OUTDIR"

check_if_all_jobs_finished() {
    local running_jobs
	
	# Count running eager jobs from the same user
    running_jobs=$(squeue -u "$USER" -n "EagerAnalysis" -h | wc -l)

    # If <= 1 job, it is last
    if [ "$running_jobs" -le 1 ]; then
        local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        echo "--------------------------------------------------------------------------------" >> "$LOG_FILE"
        echo "[$timestamp] [ALL_JOBS_COMPLETED] All scheduled pipeline runs for this batch have finished." >> "$LOG_FILE"
        echo "--------------------------------------------------------------------------------" >> "$LOG_FILE"
    fi
}

trap_handler() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        local error_reason=""
        
        if [[ -f ".nextflow.log" ]]; then
            error_reason=$(grep -E -i "Caused by:|Error:|Exception" .nextflow.log | tail -n 1 | xargs)
        fi
        
        if [[ -z "$error_reason" ]] && [[ -n "${SLURM_JOB_ID:-}" ]]; then
            local slurm_out="slurm-${SLURM_JOB_ID}_EagerAnalysis.out"
            if [[ -f "$slurm_out" ]]; then
                error_reason=$(grep -E -i "Error|Failed|No such file|Command exit" "$slurm_out" | tail -n 1 | xargs)
            fi
        fi
        
        if [[ -z "$error_reason" ]]; then
            error_reason="Check slurm-${SLURM_JOB_ID:-N/A}_EagerAnalysis.out or .nextflow.log for details."
        fi

        log_event "FAILED" "Job exited with code $exit_code. Reason: $error_reason | Outdir: $OUTDIR"
        
        check_if_all_jobs_finished
    fi
}

trap trap_handler ERR EXIT

# ==============================================================================
# WORKFLOW EXECUTION
# ==============================================================================


# If no input is provided, kill the process
if [ -z "$INPUT" ]; then
    echo "Input file required"
    exit 1
fi

# Check if the singularity version provided is the default one: if yes, use the singularity image (.sif) already downloaded. This speeds up the process significantly.
SINGULARITY_ARG=""
if [ "$SINGULARITY_VERSION" = "2.5.1" ]; then
    SINGULARITY_ARG="-with-singularity $COMMON_PATH/singularity_images/nfcore-eager-2.5.1.sif"
fi

echo "=== Starting workflow ==="
set -euo pipefail

$NEXTFLOW_VERSION run -resume nf-core/eager \
    -profile singularity \
    -c $CONFIG_FILE \
    -r $SINGULARITY_VERSION \
    $SINGULARITY_ARG \
    --input $INPUT \
    --outdir $OUTDIR

trap - EXIT

# Check for MultiQC output to confirm successful eager completion
if [[ -d "$OUTDIR/multiqc" ]] || [[ -f "$OUTDIR/multiqc/multiqc_report.html" ]]; then
    log_event "SUCCESS" "nf-core/eager completed successfully. MultiQC generated in $OUTDIR/multiqc/"
else
    log_event "COMPLETED_NO_MULTIQC" "Pipeline finished but MultiQC report was not found in $OUTDIR"
fi

check_if_all_jobs_finished

echo ""
echo "=== Cleaning up obsolete work directories ==="
nextflow clean -f -before last && find work -type d -empty -delete
echo "=== Workflow complete ==="