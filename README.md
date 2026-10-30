Hello! A quick overview before I write the documentation for each script I created in this folder:

- slurm_eager.sh: script to launch eager. Not really customizable, it was built with our human data in mind.
- slurm_eager.sh: script to launch eager. This one is way more customizable! It takes a new flag -c which allows you to pass 
	a configuration file. At the moment, the two available are lpcg_warsaw (common for the whole laboratory) and lpcg_human, 
	but more can be created!
- tsv_input_parser.py: script to create the folders and sample/individual.tsv files from a run-specific .tsv file. 
	I am working on the script to automatically create this run-specific .tsv file, but this one at least automatize the creation 
	of all the folders and subfolders.
- launch_eager_per_run.sh: script to launch eager for more than one sample at the same time, but separately for each of them. It
	requires an input .tsv file for the run itself (the same one as the previous script) and also requires that samples tsv files were
	already created (which is the job for the script before this one).