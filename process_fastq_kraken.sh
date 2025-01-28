#!/bin/bash
set -e  # Stop if any command fails

# Define paths
DB_PATH="/Data/pipelines/kraken2_db/plant_pathogens_db"
INPUT_DIR="/path/to/raw_fastq_files"
OUTPUT_DIR="/path/to/output"
REPORT_DIR="$OUTPUT_DIR/reports"
CLASSIFIED_DIR="$OUTPUT_DIR/classified_reads"

mkdir -p $REPORT_DIR $CLASSIFIED_DIR

# Load Conda environment
conda activate plant_kraken_env

echo "🔍 Step 1: Quality Control with FastQC"
mkdir -p $OUTPUT_DIR/fastqc_reports
fastqc $INPUT_DIR/*.fastq.gz -o $OUTPUT_DIR/fastqc_reports

echo "🔧 Step 2: Read Trimming & Filtering with Fastp"
mkdir -p $OUTPUT_DIR/cleaned_reads
for SAMPLE in $INPUT_DIR/*_R1.fastq.gz; do
    BASE=$(basename $SAMPLE _R1.fastq.gz)
    fastp -i "$INPUT_DIR/${BASE}_R1.fastq.gz" -I "$INPUT_DIR/${BASE}_R2.fastq.gz" \
          -o "$OUTPUT_DIR/cleaned_reads/${BASE}_R1_clean.fastq.gz" \
          -O "$OUTPUT_DIR/cleaned_reads/${BASE}_R2_clean.fastq.gz" \
          --detect_adapter_for_pe --trim_poly_g --length_required 50 \
          --html "$REPORT_DIR/${BASE}_fastp_report.html"
done

echo "🧬 Step 3: Classifying Reads with Kraken2"
mkdir -p $OUTPUT_DIR/kraken_results
for SAMPLE in $OUTPUT_DIR/cleaned_reads/*_R1_clean.fastq.gz; do
    BASE=$(basename $SAMPLE _R1_clean.fastq.gz)
    
    kraken2 --db $DB_PATH --threads 16 --use-names \
            --report "$REPORT_DIR/${BASE}_kraken_report.txt" \
            --output "$OUTPUT_DIR/kraken_results/${BASE}_kraken_output.txt" \
            --classified-out "$CLASSIFIED_DIR/${BASE}_classified.fastq" \
            --unclassified-out "$CLASSIFIED_DIR/${BASE}_unclassified.fastq" \
            --paired "$OUTPUT_DIR/cleaned_reads/${BASE}_R1_clean.fastq.gz" "$OUTPUT_DIR/cleaned_reads/${BASE}_R2_clean.fastq.gz"
done

echo "📂 Step 4: Extracting Classified Reads by Pathogen"
mkdir -p $CLASSIFIED_DIR/per_species
for REPORT in $REPORT_DIR/*_kraken_report.txt; do
    BASE=$(basename $REPORT _kraken_report.txt)
    awk -F '\t' '$4 == "S" {print $6}' $REPORT | while read TAXID; do
        kraken2 --db $DB_PATH --threads 16 --use-names \
                --classified-out "$CLASSIFIED_DIR/per_species/${BASE}_${TAXID}.fastq" \
                --unclassified-out /dev/null \
                --paired "$CLASSIFIED_DIR/${BASE}_classified.fastq" "$CLASSIFIED_DIR/${BASE}_classified.fastq"
    done
done

echo "📊 Step 5: Generating Summary Report"
echo -e "Sample\tPathogen\tReads\tPercentage" > $REPORT_DIR/final_pathogen_summary.tsv
for REPORT in $REPORT_DIR/*_kraken_report.txt; do
    BASE=$(basename $REPORT _kraken_report.txt)
    awk -F '\t' '$4 == "S" {print "'"$BASE"'\t"$6"\t"$2"\t"$3}' $REPORT >> $REPORT_DIR/final_pathogen_summary.tsv
done

echo "✅ Pipeline completed successfully!"