#!/bin/bash

# Exit on error
set -e

# Load Conda (if not already loaded)
source $(conda info --base)/etc/profile.d/conda.sh

# Create and activate a Conda environment
mamba create -y -n plant_kraken_env -c bioconda -c conda-forge \
    kraken2 bracken fastqc fastp seqkit ncbi-genome-download \
    pigz parallel multiqc

conda activate plant_kraken_env

# Verify installations
fastqc --version
fastp --version
kraken2 --version
bracken --version
seqkit version
ncbi-genome-download --help

# Define Kraken2 database directory
KRAKEN_DB="/Data/pipelines/kraken2_db/plant_pathogens/kraken2_db/plant_pathogens/"

# Create Kraken2 database structure
mkdir -p $KRAKEN_DB/library
mkdir -p $KRAKEN_DB/taxonomy

# Download and extract the taxonomy database
kraken2-build --download-taxonomy --db $KRAKEN_DB
tar -xvzf $KRAKEN_DB/taxonomy/taxdump.tar.gz -C $KRAKEN_DB/taxonomy/

# Verify taxonomy files
echo "Checking taxonomy files..."
ls -lh $KRAKEN_DB/taxonomy/

# Download only COMPLETE genomes of relevant plant pathogens
echo "Downloading complete bacterial genomes..."
ncbi-genome-download bacteria -o $KRAKEN_DB/library/refseq_bacteria --formats fasta --section refseq --assembly-level complete --parallel 20

echo "Downloading complete fungal genomes..."
ncbi-genome-download fungi -o $KRAKEN_DB/library/refseq_fungi --formats fasta --section refseq --assembly-level complete --parallel 20

echo "Downloading complete viral genomes..."
ncbi-genome-download viral -o $KRAKEN_DB/library/refseq_viral --formats fasta --section refseq --assembly-level complete --parallel 20

# Verify downloaded genomes
echo "Checking downloaded genomes..."
find $KRAKEN_DB/library/refseq_bacteria -name "*.fna.gz" | wc -l
find $KRAKEN_DB/library/refseq_fungi -name "*.fna.gz" | wc -l
find $KRAKEN_DB/library/refseq_viral -name "*.fna.gz" | wc -l

# Decompress genomes in parallel using pigz (16 threads)
echo "Decompressing genome files..."
find $KRAKEN_DB/library -name "*.fna.gz" | parallel pigz -d -p 16 {}

# Verify decompression
echo "Checking decompressed files..."
find $KRAKEN_DB/library -name "*.fna" | wc -l

# Add genomes to Kraken2 library in parallel
echo "Adding bacterial genomes to Kraken2..."
find $KRAKEN_DB/library/refseq_bacteria -name "*.fna" | parallel kraken2-build --add-to-library {} --db $KRAKEN_DB

echo "Adding fungal genomes to Kraken2..."
find $KRAKEN_DB/library/refseq_fungi -name "*.fna" | parallel kraken2-build --add-to-library {} --db $KRAKEN_DB

echo "Adding viral genomes to Kraken2..."
find $KRAKEN_DB/library/refseq_viral -name "*.fna" | parallel kraken2-build --add-to-library {} --db $KRAKEN_DB

# Detect available CPU cores
THREADS=$(nproc)

# Rebuild the Kraken2 database
echo "Building Kraken2 database..."
kraken2-build --build --db $KRAKEN_DB --threads $THREADS

# Verify the final database
echo "Checking Kraken2 database files..."
ls -lh $KRAKEN_DB/

# Check if taxonomy IDs are present
kraken2-inspect --db $KRAKEN_DB | grep "Streptococcus mitis"

echo "✅ Kraken2 database setup completed successfully!"