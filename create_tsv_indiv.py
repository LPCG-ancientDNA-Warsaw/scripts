#!/usr/bin/env python3

import os
import pandas as pd
import argparse
import re

COMMONS_FILE_DIRECTORY = "/mnt/workspace03/gr7001/share/"
EAGER_OUTPUTS_DIRECTORY = os.path.join(COMMONS_FILE_DIRECTORY, "eager_outputs")


def get_long_id(fastq_path, run_name = None):
    """
    Extract long ID. If a run ID is provided, substitute suffix _SXXX with run.
    """
    if pd.isna(fastq_path) or fastq_path in ["NA", ""]:
        return None

    filename = os.path.basename(fastq_path)

    long_id = (
        filename.split('_R1')[0]
        .split('_R2')[0]
        .split('_L00')[0]
        .replace('.fastq.gz', '')
        .replace('.fq.gz', '')
    )

    if run_name:
        parts = long_id.split('_')
        parts[-1] = run_name
        long_id = "_".join(parts)

    return long_id


def safe_makedir(path, dry_run, created_dirs):
    created_dirs.add(path)

    if dry_run:
        print(f"[DRY-RUN] mkdir -p {path}")
    else:
        os.makedirs(path, exist_ok=True)


def safe_write_tsv(df, path, dry_run, created_files):
    created_files.add(path)

    if dry_run:
        print(f"[DRY-RUN] write TSV: {path} ({len(df)} rows)")
    else:
        df.to_csv(path, sep="\t", index=False)


def determine_output_directory(input_path, outdir=None):
    """
    Determine output directory.
    """

    if outdir:
        base_outdir = os.path.abspath(outdir)
        m = re.match(r"eager_input_([^_]+)_", os.path.basename(input_path))
        project = m.group(1) if m else None

        if project:
            inferred_dir = os.path.join(EAGER_OUTPUTS_DIRECTORY, project)
            if os.path.abspath(base_outdir) != os.path.abspath(inferred_dir):
                print(f"[WARNING] TSV project '{project}' does not match outdir '{base_outdir}'.")

        print(f"[INFO] Using provided outdir: {base_outdir}")
        return base_outdir

    basename = os.path.basename(input_path)
    match = re.match(r"eager_input_([^_]+)_", basename)

    if match:
        project = match.group(1)
    else:
        project = "global"
        print("[WARNING] Could not infer project from filename. Using 'global'.")

    base_outdir = os.path.join(EAGER_OUTPUTS_DIRECTORY, project)
    print(f"[INFO] Using inferred outdir: {base_outdir}")

    return base_outdir


def process(args, dry_run = True):
    created_dirs = set()
    created_files = set()

    input_path = os.path.abspath(args.input)

    base_outdir = determine_output_directory(input_path, args.outdir)

    if not dry_run and not os.path.exists(base_outdir):
        os.makedirs(base_outdir, exist_ok=True)

    try:
        df = pd.read_csv(input_path, sep="\t", dtype = str).fillna("NA")

    except Exception as e:
        raise RuntimeError(f"Error reading input file: {e}")

    for individual, group in df.groupby("Sample_Name"):
        ind_dir = os.path.join(base_outdir, str(individual))
        merged_dir = os.path.join(ind_dir, f"{individual}_merged")
        safe_makedir(merged_dir, dry_run, created_dirs)

        print(f"\nProcessing Individual: {individual}")
        individual_tsv_rows = []

        for _, row in group.iterrows():
            library_id = row["Library_ID"]

            if args.run:
                long_id = get_long_id(row["R1"], run_name = args.run)

                if not long_id:
                    print(f"[SKIP] Cannot infer long ID for {library_id}")
                    continue

                library_id = long_id

            sample_dir = os.path.join(ind_dir, library_id)
            dir_exists = os.path.isdir(sample_dir)
            safe_makedir(sample_dir, dry_run, created_dirs)
            
            if dir_exists:
                if dry_run:
                    print(f"  [PREVIEW] Directory already found: {library_id}. No action necessary.")
                else:
                    print(f"  [EXISTS] Directory already found: {library_id}. No action necessary.")
            else:
                if dry_run:
                    print(f"  [PREVIEW - TO CREATE] Directory: {library_id}")
                else:
                    print(f"  [CREATED] Directory: {library_id}.")
            
            sample_tsv_path = os.path.join(ind_dir, f"{library_id}.tsv")
            sample_exists = os.path.exists(sample_tsv_path)
            sample_row = row.copy()
            sample_row["Library_ID"] = library_id
            safe_write_tsv(pd.DataFrame([sample_row]), sample_tsv_path, dry_run, created_files)
            
            if sample_exists:
                if dry_run:
                    print(f"  [PREVIEW - TO UPDATE] Sample TSV found: {library_id}.tsv")
                else:
                    print(f"  [UPDATED] Sample TSV found: {library_id}.tsv")
            else:
                if dry_run:
                    print(f"  [PREVIEW - TO CREATE] Sample TSV: {library_id}.tsv")
                else:
                    print(f"  [CREATED] Sample TSV: {library_id}.tsv")

            individual_row = row.copy()
            individual_row["Library_ID"] = (library_id.split("hlf")[0] if "hlf" in library_id else library_id)
            if "_NR" in individual_row["Library_ID"]:
                individual_row["Library_ID"] = individual_row["Library_ID"].split("_NR")[0]
            individual_row["R1"] = "NA"
            individual_row["R2"] = "NA"
            
            bam_path = (f"{base_outdir}/{individual}/{library_id}/mapping/bwa/{library_id}_{individual_row['SeqType']}.mapped.bam")
            individual_row["BAM"] = bam_path
            
            individual_tsv_rows.append(individual_row)

        master_tsv_path = os.path.join(ind_dir, f"{individual}.tsv")
        master_exists = os.path.exists(master_tsv_path)
        
        master_df = pd.DataFrame(individual_tsv_rows)
        master_df["SeqType"] = "SE"

        if master_exists:
            existing_df = pd.read_csv(master_tsv_path, sep="\t", dtype=str).fillna("NA")
            before_rows = len(existing_df)
            master_df = (pd.concat([existing_df, master_df]).drop_duplicates(subset=["BAM"], keep="last"))
            after_rows = len(master_df)

            safe_write_tsv(master_df, master_tsv_path, dry_run, created_files)
            
            if dry_run:
                print(f"  [PREVIEW - TO UPDATE] Master TSV: {master_tsv_path} ({before_rows} -> {after_rows} rows)")
            else:
                print(f"  [UPDATED] Master TSV: {master_tsv_path} ({before_rows} -> {after_rows} rows)")
        else:
            safe_write_tsv(master_df, master_tsv_path, dry_run, created_files)
            if dry_run:
                print(f"  [PREVIEW - TO CREATE] Master TSV: {master_tsv_path}")
            else:
                print(f"  [CREATED] Master TSV: {master_tsv_path}")

    return created_dirs, created_files


def main():

    parser = argparse.ArgumentParser(description=("Setup directory structure and TSV files for nf-core/eager."))
    parser.add_argument("-i", "--input", required=True)
    parser.add_argument("-o", "--outdir")
    parser.add_argument("-r", "--run")
    parser.add_argument("-y", "--yes", action="store_true", help="Skip confirmation prompt.")

    args = parser.parse_args()

    print("\n========== PREVIEW ==========\n")
    created_dirs, created_files = process(args, dry_run = True)

    print("\n========== SUMMARY ==========\n")
    print(f"Directories: {len(created_dirs)}")
    print(f"Files: {len(created_files)}")

    if not args.yes:
        answer = input("\nProceed with creation? [y/N]: ").strip().lower()
        if answer not in ("y", "yes"):
            print("Aborted.")
            return

    print("\n========== EXECUTING ==========\n")
    process(args, dry_run=False)
    print("\nDone.")


if __name__ == "__main__":
    main()