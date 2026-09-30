#!/bin/bash

# Default values
RUN_NAME=""
PROFILE_NAME="lpcg_human"
COMMON_FILES_DIRECTORY="/mnt/workspace03/gr7001/share"
COMMON_SLURM_SCRIPT="slurm_eager_profiles.sh"
SLURM_SCRIPT="${COMMON_FILES_DIRECTORY}/scripts/${COMMON_SLURM_SCRIPT}"

usage() {
    echo "Usage: $0 -i <master_tsv> [-o <outdir> -s <slurm_script> -r <run_name> -c <config_name>]"
    echo "  -i: (Required) Path to run-specific tsv file"
    echo "  -o: (Optional) Output directory where your sample folders are saved (ex. eager_outputs/human/)"
    echo "  -s: (Optional) Path to SLURM script for eager"
    echo "  -r: (Optional) Name of run to correct Long ID (es. the case of run NR103SS)"
	echo "  -c: (Optional) Configuration file for nextflow (ex. lpcg_human)"
	echo "  -n: (Optional) Node list of nodes to esclude, separated by a comma (ex. node143,node144)"
    exit 1
}


# Parsing flags
while getopts "i:o:s:r:c:n:" opt; do
    case $opt in
        i) MASTER_TSV=$(readlink -f "$OPTARG") ;;
        o) BASE_DIR=$(readlink -f "$OPTARG") ;;
        s) SLURM_SCRIPT=$(readlink -f "$OPTARG") ;;
        r) RUN_NAME="$OPTARG" ;;
        c) PROFILE_NAME="$OPTARG" ;;
		n) NODELIST="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$MASTER_TSV" ]]; then
    usage
fi

if [[ -z "$BASE_DIR" ]]; then

    TSV_BASENAME=$(basename "$MASTER_TSV")
    PROJECT=$(echo "$TSV_BASENAME" | sed -E 's/^eager_input_([^_]+)_.*/\1/')

    PROJECT_DIR="${COMMON_FILES_DIRECTORY}/eager_outputs/${PROJECT}"
    GLOBAL_DIR="${COMMON_FILES_DIRECTORY}/eager_outputs/global"

    if [[ -d "$PROJECT_DIR" ]]; then
        BASE_DIR="$PROJECT_DIR"
        echo "Using project output directory: $BASE_DIR"
    elif [[ -d "$GLOBAL_DIR" ]]; then
        BASE_DIR="$GLOBAL_DIR"
        echo "Project directory not found, using global output directory: $BASE_DIR"
    else
        echo "ERROR: Neither $PROJECT_DIR nor $GLOBAL_DIR exists"
        exit 1
    fi
fi

tail -n +2 "$MASTER_TSV" | while IFS=$'\t' read -r Sample_Name Library_ID Lane Chem Seq Org Strand UDG R1 R2 BAM || [[ -n "$Sample_Name" ]]; do
    # Skip empty
	[[ -z "$Sample_Name" ]] && continue
	
	# 1. Long ID
    LONG_ID="$Library_ID"

    # 2. Run (if flag -r)
	if [[ -n "$RUN_NAME" ]]; then
		FILENAME=$(basename "$R1")
		LONG_ID=$(echo "$FILENAME" | sed 's/_R1.*//; s/_R2.*//; s/_L00.*//; s/\.fastq\.gz//; s/\.fq\.gz//')
		echo "Extracted long ID: $LONG_ID"
		
		LONG_ID=$(echo "$LONG_ID" | rev | cut -d'_' -f2- | rev)_${RUN_NAME}
		echo "Corrected long ID: $LONG_ID"
	fi

    # 3. Path
    IND_DIR="$BASE_DIR/$Sample_Name"
    SAMPLE_DIR="$IND_DIR/$LONG_ID"
    INPUT_TSV="$IND_DIR/$LONG_ID.tsv"
	
	EXTRA_FLAGS=""
	if [[ -n "$PROFILE_NAME" ]]; then
		EXTRA_FLAGS="-c $PROFILE_NAME"
	fi
	
	SBATCH_FLAGS=()
    if [[ -n "$NODELIST" ]]; then
        SBATCH_FLAGS+=("--exclude=$NODELIST")
    fi

    # 4. Execution
    if [[ -d "$SAMPLE_DIR" && -f "$INPUT_TSV" ]]; then
        echo "--> Submitting: Individual $Sample_Name | Sample $LONG_ID"
        
        # Go to sample directory to isolate .nextflow files and work/ of each sample
        cd "$SAMPLE_DIR" || continue

        # Launch SLURM
		
		# Capture Slurm job submission result
		JOB_OUTPUT=$(sbatch "${SBATCH_FLAGS[@]}" "$SLURM_SCRIPT" -i "$INPUT_TSV" -o "$SAMPLE_DIR" $EXTRA_FLAGS)
		JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')

		# Determine project and write submission entry to log
		LOG_DIR="${COMMON_FILES_DIRECTORY}/eager_outputs/logs"
		mkdir -p "$LOG_DIR"
		DATE_STR=$(date +%Y-%m-%d)
		
		PROJ_NAME=$(basename "$(dirname "$IND_DIR")")
		LOG_FILE="${LOG_DIR}/${DATE_STR}_${PROJ_NAME}.log"

		# Log di sbatch
		echo "[$(date "+%Y-%m-%d %H:%M:%S")] [JOB: $JOB_ID] [SUBMITTED_LIBRARY] Individual: $Sample_Name | Sample: $LONG_ID | Config: $PROFILE_NAME" >> "$LOG_FILE"

        # Go back for next run
        cd - > /dev/null
    else
        echo "[SKIP] Directory or TSV file not found for library $LONG_ID in $IND_DIR"
    fi

done