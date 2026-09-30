#!/usr/bin/env python3

# Usage:
# create_tsv_run.py --project <project_name> [--dir <fastq_dir> --data <sample_sheet.csv> --chemistry 2 --species homo_sapiens \
# --strand single --udg hlf --ignore-samplesheet --dry-run]

# This script requires yaml package which might not be installed on your account. Install it by running pip install pyyaml


import argparse
import os
import re
import yaml
import pandas as pd
from pathlib import Path
import sys

COMMONS_FILE_DIRECTORY = "/mnt/workspace03/gr7001/share/"
PROJECTS_PARAMS_FILE = COMMONS_FILE_DIRECTORY + "conf/lpcg_lib_params.yaml"

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-p", "--project", default = ["global"], nargs = "+", help = "Project name(s): when providing more than one, separate them with a space. Matches projects in the .yaml configuration file and/or Sample_Project column in the SampleSheet.csv file.")
    parser.add_argument("-c", "--config", default = PROJECTS_PARAMS_FILE, help = "Path to .yaml file with projects parameters.")
    parser.add_argument("--dir", default = os.getcwd(), help = "Directory where .fastq files are stored.")
    parser.add_argument("-o", "--outdir", default = os.getcwd(), help = "Diretory where the output file will be generated.")
    parser.add_argument("--data", help = ".csv files that contains Lane information. Contains a row that starts with '[Data]'.")
    parser.add_argument("--ignore-samplesheet", action = "store_true", help = "Ignore the samplesheet in the folder and use default parameters.")
    parser.add_argument("-r", "--run", help = "Correct Library ID by adding the provided run name.")
    parser.add_argument("--dry-run", action = "store_true", help = "Displays what the script would do.")
    parser.add_argument("--chemistry")
    parser.add_argument("--species", help = "Species sequenced [genus_species] format.")
    parser.add_argument("--seqtype", help = "Sequencing type, 'PE' for Paired End and 'SE' for Single end.")
    parser.add_argument("--strand", help = "'single' or 'double'")
    parser.add_argument("--udg", help = "UDG treatment: can be 'full', 'hlf' or 'none'.")
    return parser.parse_args()


def load_project_config(config_file, project):
    """
    Loads the project-specific parameters.
    
    Input:
    - config_file: path to the .yaml file with project-specific libary naming structure;
    - project: name of the project
    
    Ouput:
    - a dictionary of all the parameters associated with a project.
    """
    
    with open(config_file) as opened_config_file:
        loaded_config_file = yaml.safe_load(opened_config_file)

    settings = loaded_config_file["global"].copy()
    
    if project == "global" or project not in loaded_config_file["projects"]:
        print(f"Project {project} is either the default setting or was not found in the configuration file. Using default settings: this will override any project information provided in the Sample sheet and all samples in the folder will be treated as being part of the same project.", file=sys.stderr)
    else:
        project_config = loaded_config_file["projects"][project]
        settings.update(project_config)
    
    return settings


def find_samplesheet(workdir):
    """
    Find the samplesheet with lane information in the given folder: 
    it can either be the one provided by the sequencing machine (it will have a row called [Data], 
    or a manually-prepared file.
    
    Input:
    - workdir: a path to a working directory.
    
    Output:
    - the .csv file found in the working directory.
    """
    csvs = list(Path(workdir).glob("*.csv"))

    if len(csvs) == 0:
        raise FileNotFoundError("No csv file found.")
    if len(csvs) > 1:
        raise ValueError("Multiple csv files found. Use --data.")
    return csvs[0]


def read_samplesheet(path):
    """
    Reads and extract information from a .csv file, given that it has a row called [Data] after which all data starts.
    
    Input:
    - path: path to the .csv file containing samples information.
    
    Ouput:
    - a pandas dataframe of the samples' information contained in the .csv file.
    """
    
    with open(path) as opened_samplesheet:
        lines = opened_samplesheet.readlines()

    data_start = None

    for i, line in enumerate(lines):
        if line.strip() == "[Data]":
            data_start = i + 1
            break

    if data_start is None:
        raise ValueError("Cannot find [Data] section.")
    return pd.read_csv(path, skiprows = data_start, index_col=False)
    
    

def get_fastqs(workdir):
    """
    Obtain a list of all fastq files in a certain directory.
    
    Input:
    - workdir: path to the folder that contains the fastq files.
    
    Output:
    - list of (sorted) .fastq files names.
    """
    fastqs = []
    fastqs.extend(Path(workdir).glob("*.fastq"))
    fastqs.extend(Path(workdir).glob("*.fastq.gz"))

    return sorted(fastqs)


def parse_filename(filename, sample_id_regex, library_id_regex, run_name = None):
    """
    Function to parse the .fastq file name to find the Sample name and the Library ID based on the REGEX strings provided.
    
    Input:
    - filename: name or path of the .fastq file;
    - sample_id_regex: regex of the Sample Name;
    - library_id_regex: regex of the Library ID.
    - run_name (OPTIONAL): name of the run to append at the end of the library ID.
    
    Output:
    - a tuple containing the Sample Name, the Library ID strings.
    """
    base_name = re.sub(r"\.fastq(?:\.gz)?$", "", filename)
    base_name = re.sub(r"_L\d{3}", "", base_name)
    base_name = re.sub(r"_S\d+", "", base_name)
    
    sample = re.search(sample_id_regex, base_name)
    library = re.search(library_id_regex, base_name)

    if sample is None:
        base_name = re.sub(r"_R[12]_.*$", "", base_name)
        print(f"Cannot parse Sample ID from {filename}. Using {base_name}.", file=sys.stderr)
        sample = base_name
    else:
        sample = sample.group(1)

    if library is None:
        base_name = re.sub(r"_R[12]_.*$", "", base_name)
        print(f"Cannot parse Library ID from {filename}. Using {base_name}.", file=sys.stderr)
        library = base_name
    else:
        library = library.group(1)
    
    if run_name:
        library = "_".join((library, run_name))

    return (sample, library)


def get_lane(library_id, samplesheet_info, default_lane):
    """
    Extract lane information from samplesheet if available. Otherwise return default lane.
    
    Input:
    - library_id: Library ID of the specific library.
    - samplesheet_info: pandas dataframe with the info contained in the .csv file.
    - default_lane: value to insert if no info is available.
    
    Output:
    - value for the lane info associated to a specific library.
    """

    if samplesheet_info is None or "Lane" not in samplesheet_info.columns:
        return default_lane
    
    lib_str = str(library_id) if pd.notna(library_id) else ""
    
    valid_samples = samplesheet_info.dropna(subset=["Sample_ID"])
    matches = valid_samples[valid_samples["Sample_ID"].astype(str).apply(lambda x: library_id.startswith(x))]

    if len(matches) == 0:
        return default_lane
    
    return matches.iloc[0]["Lane"]

def get_sample_project(library_id, samplesheet_info):
    """
    Extract project name information from samplesheet if available.
    
    Input:
    - library_id: Library ID of the specific library.
    - samplesheet_info: pandas dataframe with the info contained in the .csv file.
    
    Output:
    - value for the project name associated to a specific library.
    """
    
    if samplesheet_info is None or "Sample_Project" not in samplesheet_info.columns:
        return None

    lib_str = str(library_id) if pd.notna(library_id) else ""

    valid_samples = samplesheet_info.dropna(subset=["Sample_ID"])

    matches = valid_samples[valid_samples["Sample_ID"].astype(str).apply(lambda x: library_id.startswith(x))]
    
    if len(matches) == 0:
        return None

    return str(matches.iloc[0]["Sample_Project"]).strip().lower()


    
def extract_udg_treatment(filename, project_settings):
    """
    Retrieve information on udg treatment knowing the filename and project-settings.
    
    Input:
    - filename: the fastq file name.
    - settngs: the project specific settings extracted from the .yaml file
    
    Output:
    - string for udg treatment."""
    
    regex = project_settings.get("udg_regex")
    if regex is None:
        return project_settings.get("UDG_Treatment")

    match = re.search(regex, filename)
    if not match:
        return project_settings.get("UDG_Treatment")

    code = match.group(1)
    return project_settings.get("udg_mapping", {}).get(code, code)
    



########### Main code ##########
args = parse_args()
workdir = (args.dir)
outdir = (args.outdir)

samplesheet = None

if not args.ignore_samplesheet:
    samplesheet_path = args.data
    if samplesheet_path is None:
        try:
            samplesheet_path = find_samplesheet(workdir)
        except (FileNotFoundError, ValueError):
            parent_dir = os.path.dirname(os.path.normpath(workdir))
            try:
                samplesheet_path = find_samplesheet(parent_dir)
            except (FileNotFoundError, ValueError):
                samplesheet_path = None

    if samplesheet_path:
        samplesheet = read_samplesheet(samplesheet_path)

if samplesheet is None or "Sample_Project" not in samplesheet.columns or samplesheet["Sample_Project"].isnull().all():
    print("Sample project column not found in the Sample sheet or empty. Checking number of projects provided...", file=sys.stderr)
    if len(args.project)>1:
        print("More than one project name provided. Setting project name as default 'global' and all samples in the folder will be treated as being part of the same project.", file=sys.stderr)
        args.project = ["global"]
    else:
        print(f"Attempting using project name: {args.project[0]}.", file=sys.stderr)

projects_present = (samplesheet["Sample_Project"].astype(str).str.strip().str.lower().unique() if samplesheet is not None and "Sample_Project" in samplesheet.columns else [])


for project_in_list in args.project:
    project = project_in_list.strip().lower()
    
    if project != 'global' and project not in projects_present and not args.ignore_samplesheet:
        print(f"No samples associated with project '{project}'. Skipping.", file=sys.stderr)
        continue

    
    print(f"Processing project '{project}'.", file=sys.stderr)
    ## Retrieve parameters from flags or project parameters.
    # Only provided by flags:
    project_config = load_project_config(args.config, project)


    # Only provided by config file
    default_lane = project_config["Lane"]

    # Provided by flags OR config file
    chemistry = (args.chemistry or project_config["Colour_Chemistry"])
    species = (args.species or project_config["Organism"])
    strand = (args.strand or project_config["Strandedness"])
    seqtype = (args.seqtype or project_config["SeqType"])

    ## How to extract Sample Name and Library ID? We need the regex strings ##
    sample_id_regex = project_config["sample_id_regex"]
    library_id_regex = project_config["library_id_regex"]

    # List of all fastq files
    fastqs = get_fastqs(workdir)

    rows = []

    for fq in fastqs:
        if "_R2_" in fq.name:
            continue
        sample_name, library_id = parse_filename(fq.name, sample_id_regex, library_id_regex, run_name = args.run)
        
        if project != "global" and samplesheet is not None and not args.ignore_samplesheet:
            sample_project = get_sample_project(library_id, samplesheet)
            if sample_project != project:
                continue
                
        lane = get_lane(library_id, samplesheet, default_lane)
        
        # Special case: UDG treatment. Sometimes in flags, sometimes in config, sometimes in fastqname.
        udg = (args.udg or extract_udg_treatment(fq.name, project_config))
        
        if seqtype == "PE":
            R2 = str(fq).replace("_R1_", "_R2_")
        else:
            R2 = "NA"
        
        rows.append({
        "Sample_Name": sample_name, 
        "Library_ID": library_id, 
        "Lane" : lane,
        "Colour_Chemistry" : chemistry,
        "SeqType" : seqtype,
        "Organism" : species,
        "Strandedness" : strand,
        "UDG_Treatment" : udg,
        "R1" : str(fq),
        "R2" : R2,
        "BAM": "NA"})
        
        
    df = pd.DataFrame(rows)
    
    if args.run:
        folder_name = args.run
    else:
        folder_name = next((part for part in reversed(os.path.normpath(workdir).split(os.sep)) if part.startswith("NR")), os.path.basename(workdir.rstrip("/")))


    if args.dry_run:
        print(f"\nFound {len(df)} libraries in folder {folder_name} associated with project {project}:", file=sys.stderr)
        print(df[["Sample_Name","Library_ID"]], file=sys.stderr)
        print(f"\n", file=sys.stderr)
        print(f"The generated .tsv file will look like this (no columns R1 and R2):", file=sys.stderr)
        print(df.drop(columns=["R1", "R2"]).to_string(index=False), file=sys.stderr)
        print(f"\n", file=sys.stderr)

    else:
        output = os.path.join(outdir, f"eager_input_{project}_{folder_name}.tsv")
        df.to_csv(output, sep="\t", index = False)
        
        
        if args.udg:
            udg_used = args.udg
        elif project_config.get("udg_regex"):
            udg_used = "filename-dependent"
        else:
            udg_used = project_config.get("UDG_Treatment")
        
        print(f"""Used the following parameters:
        "Project name": {project},
        "Colour_Chemistry" : {chemistry},
        "SeqType" : {seqtype},
        "Organism" : {species},
        "Strandedness" : {strand},
        "UDG_Treatment" : {udg_used}.\n
        
        Please manually check the generated file for mistakes.
        """, file=sys.stderr)
        
        print(f"\nInput .tsv file generated at:", file=sys.stderr)
        print(output, file=sys.stderr)
        print(output)
