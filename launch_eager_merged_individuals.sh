#!/bin/bash

# Default values
PROFILE_NAME=""
COMMON_FILES_DIRECTORY="/mnt/workspace03/gr7001/share"
COMMON_SLURM_SCRIPT="slurm_eager_profiles.sh"
SLURM_SCRIPT="${COMMON_FILES_DIRECTORY}/scripts/${COMMON_SLURM_SCRIPT}"

usage() {
    echo "Usage: $0 -i <input_path> [-s <slurm_script> -c <config_name>]"
    echo "  -i: Path to directory (ex. eager_outputs/human/) OR a text file (.txt/.csv/.tsv) with a list of IDs"
    echo "  -s: (Optional) Path to SLURM script for eager"
    echo "  -c: (Optional) Configuration file name for nextflow (ex. lpcg_human)"
	echo "  -n: (Optional) Node list of nodes to esclude, separated by a comma (ex. node143,node144)"
    exit 1
}

# Parsing flags
while getopts "i:o:s:c:n:" opt; do
    case $opt in
        i) INPUT_PATH=$(readlink -f "$OPTARG") ;;
        s) SLURM_SCRIPT=$(readlink -f "$OPTARG") ;;
        c) PROFILE_NAME="$OPTARG" ;;
		n) NODELIST="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$INPUT_PATH" ]]; then
    usage
fi

# extra flag for profile name
EXTRA_FLAGS=""
if [[ -n "$PROFILE_NAME" ]]; then
    EXTRA_FLAGS="-c $PROFILE_NAME"
fi

SBATCH_FLAGS=()
if [[ -n "$NODELIST" ]]; then
	SBATCH_FLAGS+=("--exclude=$NODELIST")
fi

# ==============================================================================
# CREATE PARSING FUNCTION
# ==============================================================================

process_individual() {
    local ind_id="$1"
    local ind_dir="$2"
    
    local merged_dir="$ind_dir/${ind_id}_merged"
    local master_tsv="$ind_dir/${ind_id}.tsv"

    echo "--------------------------------------------------"
    echo "Checking Individual: $ind_id"

    # Checks presence of individual TSV file and "_merged" folder
    if [[ -d "$merged_dir" && -f "$master_tsv" ]]; then
        echo "--> Submitting MERGED analysis for: $ind_id"
        
        cd "$merged_dir" || return

        # Launch script SLURM
        # sbatch "$SLURM_SCRIPT" -i "$master_tsv" -o "$merged_dir" $EXTRA_FLAGS
		
		JOB_OUTPUT=$(sbatch "${SBATCH_FLAGS[@]}" "$SLURM_SCRIPT" -i "$master_tsv" -o "$merged_dir" $EXTRA_FLAGS)
		JOB_ID=$(echo "$JOB_OUTPUT" | awk '{print $NF}')

		LOG_DIR="${COMMON_FILES_DIRECTORY}eager_outputs/logs"
		mkdir -p "$LOG_DIR"
		DATE_STR=$(date +%Y-%m-%d)
		
		PROJ_NAME=$(basename "$(dirname "$ind_dir")")
		LOG_FILE="${LOG_DIR}/${DATE_STR}_${PROJ_NAME}_merged.log"

		# Log di sbatch
		echo "[$(date "+%Y-%m-%d %H:%M:%S")] [JOB: $JOB_ID] [SUBMITTED_MERGED] Individual: $ind_id | Config: ${PROFILE_NAME:-default} | Directory: $merged_dir" >> "$LOG_FILE"

        cd - > /dev/null
    else
        echo "[SKIP] Missing ${ind_id}.tsv or ${ind_id}_merged/ folder in $ind_dir"
    fi
}

infer_output_dir_from_tsv() {

    local tsv="$1"

    local tsv_basename
    tsv_basename=$(basename "$tsv")

    local project
    project=$(echo "$tsv_basename" | sed -E 's/^eager_input_([^_]+)_.*/\1/')

    local project_dir="${COMMON_FILES_DIRECTORY}/eager_outputs/${project}"
    local global_dir="${COMMON_FILES_DIRECTORY}/eager_outputs/global"

    if [[ -d "$project_dir" ]]; then
        echo "$project_dir"
    elif [[ -d "$global_dir" ]]; then
        echo "$global_dir"
    else
        return 1
    fi
}

# ==============================================================================
# NOW RUN FUNCTION
# ==============================================================================

if [[ -d "$INPUT_PATH" ]]; then
    # Input is a FOLDER
    echo "Input is a directory. Parsing all subfolders..."
    
    for ind_dir in "$INPUT_PATH"/*; do
        if [[ -d "$ind_dir" ]]; then
            # Name of the folder = ID of the individual
            IND_ID=$(basename "$ind_dir")
            process_individual "$IND_ID" "$ind_dir"
        fi
    done

elif [[ -f "$INPUT_PATH" ]]; then

    if head -n1 "$INPUT_PATH" | grep -q "Sample_Name"; then
        INPUT_TYPE="TSV"
    else
        INPUT_TYPE="LIST"
    fi

    if [[ "$INPUT_TYPE" == "TSV" ]]; then

        echo "Input is a TSV file."

        BASE_DIR=$(infer_output_dir_from_tsv "$INPUT_PATH")

        if [[ -z "$BASE_DIR" ]]; then
            echo "[ERROR] Could not determine output directory"
            exit 1
        fi

        awk -F'\t' 'NR>1 {print $1}' "$INPUT_PATH" \
        | sort -u \
        | while read -r IND_ID; do

            IND_DIR="${BASE_DIR}/${IND_ID}"

            process_individual "$IND_ID" "$IND_DIR"

        done

    else
        echo "Input is a txt file. Reading individual list..."

        BASE_DIR=$(dirname "$INPUT_PATH")

        while IFS= read -r IND_ID || [[ -n "$IND_ID" ]]; do
            IND_ID=$(echo "$IND_ID" | tr -d '\r' | xargs)

            [[ -z "$IND_ID" ]] && continue

            if [[ -d "$BASE_DIR/$IND_ID" ]]; then
                IND_DIR="$BASE_DIR/$IND_ID"
            elif [[ -d "./$IND_ID" ]]; then
                IND_DIR="$(pwd)/$IND_ID"
            else
				
                echo "[ERROR] Cannot find directory for individual $IND_ID"
				echo "[ERROR] Checked directories: $BASE_DIR/$IND_ID and $(pwd)/$IND_ID"
                continue
            fi

            process_individual "$IND_ID" "$IND_DIR"

        done < "$INPUT_PATH"

    fi

else
    echo "[ERROR] Input path '$INPUT_PATH' does not exist."
    exit 1
fi