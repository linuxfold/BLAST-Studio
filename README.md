# Local BLAST Studio

<img width="500" height="500" alt="ChatGPT Image May 1, 2026, 01_02_34 AM" src="https://github.com/user-attachments/assets/226fc2b0-1eae-42ec-b37a-794ff4673eae" />

Local BLAST Studio is a native macOS app for running the NCBI BLAST+ command-line suite locally through a GUI. It wraps your installed BLAST+ binaries, scans your local BLAST database folder, manages downloads with NCBI's `update_blastdb.pl`, and keeps the generated command line visible before each run.

> If installing from a precompiled `.dmg`, drag the app into `/Applications`. If macOS quarantines the unsigned app, run: `xattr -dr com.apple.quarantine /Applications/LocalBlastStudio.app`

The app is intentionally local-first. It does not contact NCBI on launch, and it does not upload query sequences. It contacts NCBI only when you explicitly click **Refresh Catalog** or **Download Selected**.

## Features

- Runs local `blastn`, `blastp`, `blastx`, `tblastn`, `tblastx`, `psiblast`, `rpsblast`, `rpstblastn`, `deltablast`, `igblastn`, and `igblastp`.
- Adds IgBLAST controls for immunoglobulin and T cell receptor searches, including `IGDATA`, germline V/D/J/C database prefixes, auxiliary data, optional additional database search, and AIRR TSV output.
- Supports local database searches with downloaded BLAST databases such as `core_nt`, `nr_cluster_seq`, `nt`, `nr`, `refseq_protein`, and `refseq_rna`.
- Supports pairwise sequence comparison with **Align two sequences**, using BLAST+'s `-subject` mode instead of a database.
- Supports BLASTN/BLASTP **Align 3+ sequences** mode for local Clustal Omega multiple sequence alignments.
- Adds an **RNA-Seq** annotation workspace for trimmed/merged `.fq`, `.fastq`, `.fq.gz`, or `.fastq.gz` inputs, including multi-file selection, database choice, output-field selection, and staged progress.
- Adds a **Results** workspace that tracks multiple jobs, auto-loads saved `.txt`, `.tsv`, `.out`, `.aln`, and `.clu` reports, renders BLAST descriptions, alignments, tabular rows, multiple alignments, and raw output in a GUI, supports shift-range selection plus export/delete actions, and can reuse saved run inputs/settings for a new search.
- Provides website-style controls for common BLAST parameters: task, E-value, max target sequences, word size, scoring, filters, masking, output format, genetic code, ranges, and PSI-BLAST settings.
- Provides a raw advanced-arguments field, appended last, for BLAST+ switches that are not yet represented by structured controls.
- Discovers downloadable NCBI database names with `update_blastdb.pl --showall` when requested.
- Downloads and optionally decompresses selected databases with `update_blastdb.pl`.
- Builds custom nucleotide or protein databases with `makeblastdb`.
- Shows installed database count, storage use, file count, installed database badges, and catalog entries that are not installed.
- Packages as a standard macOS `.app` bundle with a custom icon.

## What's New In 0.4.0

- Added BLASTN/BLASTP **Align 3+ sequences** mode backed by local Clustal Omega (`clustalo`).
- Reworked the app shell with a top workspace bar and a persistent, resizable Results panel.
- Added a full Results workspace that opens selected results in the main view while keeping the Results list visible.
- Added result re-use: new runs save a local sidecar metadata file so a result can reload its original inputs/settings into **Run BLAST** with a fresh output path.
- Added multi-result selection with shift-click range selection and command-click toggling.
- Added selected/all result export and delete controls, plus right-click result menus.
- Improved alignment viewing by defaulting sequence alignments to **Raw**, removing BLAST citation blocks from raw display, increasing raw text size, and anchoring alignment text at the top of the pane.
- Updated packaging to produce `BLAST-Studio-0.4.0-universal.dmg`.

## Privacy And Network Behavior

Startup is offline. On launch the app:

1. Scans your configured BLASTDB folder.
2. Checks local BLAST+/IgBLAST tool paths without launching those tools.
3. Builds the command preview locally.

The app contacts NCBI only for these explicit actions:

- **Refresh Catalog**: runs `update_blastdb.pl --showall` to retrieve the current list of downloadable databases.
- **Download Selected**: runs `update_blastdb.pl` for the selected database names.
- **Tools > Recheck**: launches local tools with version flags so their installed versions can be displayed.

Normal BLAST searches run locally with your installed BLAST+ binaries. The app does not send query FASTA content to NCBI.

## Requirements

- macOS 14 or newer.
- Swift 6 toolchain to build from source.
- NCBI BLAST+ installed locally for normal searches, database downloads, and custom database creation.
- NCBI IgBLAST installed locally only when using `igblastn` or `igblastp`.
- Clustal Omega installed locally only when using **Align 3+ sequences**.
- Perl and `curl`, used by NCBI's `update_blastdb.pl`.
- Enough disk space for selected databases.

## External Tool Installation

Local BLAST Studio does not bundle NCBI or Clustal binaries. Install them once, then open **Tools** in the app and either leave the tool directory blank to search `PATH`, or set it to the folder containing the executables.

Required for standard BLAST searches and database downloads:

- `blastn`, `blastp`, `blastx`, `tblastn`, `tblastx`
- `psiblast`, `rpsblast`, `rpstblastn`, `deltablast`
- `makeblastdb`, `blastdbcmd`, `update_blastdb.pl`
- `dustmasker`, `segmasker`, `windowmasker`, `makeprofiledb`, `makembindex`, `convert2blastmask`
- `perl`, `curl`, and `gzip`

Required only for IgBLAST:

- `igblastn`, `igblastp`
- IgBLAST support data containing `internal_data` and `optional_file`
- Local germline V/D/J/C database prefixes formatted for IgBLAST

Required only for **Align 3+ sequences**:

- `clustalo`

Fastest macOS install path for BLAST+ and Clustal Omega with Homebrew:

```sh
brew install blast clustal-omega
```

Fastest single-environment install path for BLAST+, IgBLAST, and Clustal Omega with Conda/Bioconda:

```sh
conda create -n local-blast-studio -c conda-forge -c bioconda blast igblast clustalo
conda activate local-blast-studio
```

After a Homebrew install, the tool directory is usually `/opt/homebrew/bin` on Apple Silicon or `/usr/local/bin` on Intel Macs. After a Conda install, use:

```sh
echo "$CONDA_PREFIX/bin"
```

Verify the installed tools from Terminal:

```sh
blastn -version
makeblastdb -version
update_blastdb.pl --showall
clustalo --version
igblastn -version
```

Official alternatives:

- Install BLAST+ directly from [NCBI](https://www.ncbi.nlm.nih.gov/books/NBK569861/) if you prefer NCBI's macOS installer or tarball.
- Install stand-alone IgBLAST from [NCBI IgBLAST](https://www.ncbi.nlm.nih.gov/igblast/) if you do not use Bioconda.
- Install Clustal Omega through [Bioconda `clustalo`](https://bioconda.github.io/recipes/clustalo/README.html) if Homebrew is not available on the target machine.

## Build And Run

Run from source:

```sh
swift build
swift run LocalBlastStudio
```

Run the smoke checks:

```sh
swift run LocalBlastSmokeTests
```

Create a macOS app bundle:

```sh
./scripts/package_app.sh
```

The packaged app is created at:

```sh
dist/LocalBlastStudio.app
```

Create a universal Intel + Apple Silicon DMG:

```sh
./scripts/package_dmg.sh
```

The DMG is created at:

```sh
dist/BLAST-Studio-0.4.0-universal.dmg
```

The DMG script builds separate `arm64` and `x86_64` release binaries, combines them with `lipo`, creates a drag-to-Applications disk image, and ad-hoc signs the app by default. It is not notarized. To sign with a Developer ID certificate, run it with `CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package_dmg.sh`.

## First Launch

1. Open **Tools** and confirm BLAST+, IgBLAST, and Clustal Omega tools are detected as needed for your workflow.
2. If needed, set the tool bin directory, for example `/opt/homebrew/bin`, `/usr/local/bin`, or the active Conda environment's `bin` directory.
3. Open **Databases** and choose a BLASTDB directory.
4. The app scans installed databases immediately without contacting NCBI.
5. Click **Refresh Catalog** only when you want to fetch the latest downloadable list from NCBI.
6. Start with `core_nt` for BLASTN and `nr_cluster_seq` for BLASTP, or select other databases and click **Download Selected**.
7. For IgBLAST, install the NCBI IgBLAST package, set the same bin directory in **Tools**, and point **Run BLAST** at the IgBLAST release support-data folder through `IGDATA`.
8. Open **Run BLAST**, paste or choose a FASTA query, pick a database or IgBLAST germline databases, set options, and run.
9. Open **Results** to review completed jobs or load saved BLAST result files.

## Running A Database Search

For a normal search, leave **Align two sequences** and **Align 3+ sequences** unchecked.

The app generates a command shaped like:

```sh
blastn -query query.fasta -db core_nt -out result.txt -task megablast
```

The app sets `BLASTDB` for the BLAST process and also passes the selected database path directly.

## Viewing Search Progress And Results

The **Run BLAST** screen shows a live search-progress panel while a job is active. It records when the sequence is submitted, which program and database are being searched, elapsed time, output-file growth, and the parsed hit count when the job finishes.

BLAST writes most report content to the selected `-out` file rather than to stdout. Local BLAST Studio reads that output file automatically after the process exits and renders the report in the GUI, including BLAST description tables, pairwise alignments, tabular rows, IgBLAST domain summaries, AIRR-style rows, and the raw report text.

Pasted plain sequence text is normalized to FASTA before launch, so quick online-BLAST-style query pastes work without manually adding a `>` header.

## Running IgBLAST

Choose `IgBLASTN` or `IgBLASTP` in **Run BLAST** to classify immunoglobulin or T cell receptor sequences against local germline databases.

IgBLAST commands use `-germline_db_V` instead of the normal required BLAST `-db` argument. For nucleotide rearrangement searches, fill in V, D, J, optional C-region, and optional auxiliary-data fields. Set `IGDATA` to the IgBLAST folder that contains `internal_data` and `optional_file`, unless your shell environment already provides it.

Keep IgBLAST germline databases in a path without spaces so BLAST can memory-map the database files reliably. A typical local database folder is:

```sh
~/LocalBlastStudio-IgBlastDatabases
```

Example human local fields are:

```text
IGDATA: /path/to/igblast
V: ~/LocalBlastStudio-IgBlastDatabases/airr_c_human_ig.V
D: ~/LocalBlastStudio-IgBlastDatabases/airr_c_human_igh.D
J: ~/LocalBlastStudio-IgBlastDatabases/airr_c_human_ig.J
C: ~/LocalBlastStudio-IgBlastDatabases/ncbi_human_c_genes
Auxiliary data: /path/to/igblast/optional_file/human_gl.aux
```

The generated command is shaped like:

```sh
IGDATA=/path/to/igblast igblastn -query query.fasta -germline_db_V database/human_gl_V -germline_db_D database/human_gl_D -germline_db_J database/human_gl_J -organism human -ig_seqtype Ig -auxiliary_data optional_file/human_gl.aux -out result.tsv -outfmt 19
```

You can also supply an optional additional BLAST database; when it is a database name rather than a path, Local BLAST Studio sets `BLASTDB` from the additional database directory.

## Annotating Trimmed RNA-Seq FASTQ

Open **RNA-Seq** to annotate one or more trimmed and merged FASTQ files against a local BLAST database.

1. Add one or more `.fq`, `.fastq`, `.fq.gz`, or `.fastq.gz` files.
2. Choose `BLASTN` for nucleotide/transcript databases such as `refseq_rna`, or `BLASTX` for translated searches against protein databases.
3. Pick or type the database name, choose the output `.tsv`, and select the BLAST tabular fields to include.
4. Start annotation.

The RNA-Seq workflow streams FASTQ records to a temporary FASTA file in the output folder, runs BLAST against that FASTA, then removes the converted FASTA unless **Keep converted FASTA beside the output** is enabled. Gzipped FASTQ inputs are streamed through `gzip -dc` and are not decompressed to a standalone `.fq` file first. For 7-30 GB FASTQ inputs, leave enough free space for the converted FASTA, the BLAST output, and BLAST temporary/runtime overhead.

## Choosing A Database

BLAST database choice affects speed, disk use, and biological interpretation more than almost any other setting. The app highlights starter databases, but the right search set depends on the question.

### Recommended Starters

| Goal | Program | Recommended database | Why |
|---|---|---|---|
| Quick nucleotide ID or sanity check | `blastn` | `core_nt` | Smaller practical nucleotide starter set with broad coverage for common local searches. |
| Broad nucleotide search | `blastn` | `nt` | Largest general nucleotide collection; use when `core_nt` is too narrow and you have the storage/time budget. |
| Transcript or RNA-Seq annotation | `blastn` | `refseq_rna` | Curated transcript/reference RNA target set that is usually easier to interpret than all of `nt`. |
| Assembled transcriptome reads | `blastn` | `tsa_nt` | Transcriptome Shotgun Assembly nucleotide records; useful when RefSeq RNA is too curated. |
| 16S or bacterial marker checks | `blastn` | `16S_ribosomal_RNA` | Small, focused marker database that is fast and avoids unrelated nucleotide hits. |
| Quick protein ID | `blastp` | `nr_cluster_seq` | Representative protein clusters from `nr`; much smaller and less redundant than full `nr`. |
| Curated protein function | `blastp` or `blastx` | `swissprot` | Small, high-quality curated protein set; good first pass for clean functional labels. |
| Reference protein annotation | `blastp` or `blastx` | `refseq_protein` | Larger curated/reference-style protein coverage than Swiss-Prot. |
| Broadest protein search | `blastp` or `blastx` | `nr` | Full nonredundant protein set; slower and much larger, but broadest. |

For most new installs, download `core_nt`, `nr_cluster_seq`, `refseq_rna`, `swissprot`, and `taxdb` first. Add larger databases only after you know which search family you actually need.

### Search Strategy

- Use the smallest database that can answer the question. Small focused databases are faster, easier to interpret, and less likely to bury the useful hit in generic matches.
- Use `core_nt` before `nt` for nucleotide searches. Move to `nt` only when the target may be absent from the starter set.
- Use `nr_cluster_seq` before `nr` for protein searches. Move to `nr` when cluster representatives are not enough or you need maximum legacy coverage.
- Use `swissprot` before `nr` when the goal is functional annotation. Swiss-Prot may miss obscure sequences, but its labels are usually cleaner.
- Use `refseq_rna` or `refseq_protein` when you want reference-style records rather than every submitted sequence.
- Add `taxdb` if you need taxonomy names, taxonomy IDs, or better organism labels in reports.
- Build a custom database with `makeblastdb` when searching against a species panel, lab reference set, plasmid collection, primer target set, or any known bounded sequence universe.

### RNA-Seq Notes

For RNA-Seq annotation, prefer a target database that matches the biological question:

- `refseq_rna` for transcript-level nucleotide annotation.
- `refseq_protein`, `swissprot`, or `nr_cluster_seq` with `blastx` when nucleotide reads should be translated and assigned to proteins.
- Custom transcript/protein FASTA databases when you are validating against an organism-specific reference or expected construct set.

RNA-Seq jobs can produce very large tabular outputs. Keep **Max hits/read** low until the pipeline is tuned, and increase **CPU threads** based on available cores and disk speed.

### Performance Expectations

The NCBI web service often feels much faster because it runs on optimized server infrastructure with hot databases, fast storage, and backend parallelism. Local BLAST speed depends on your CPU thread count, database size, disk speed, whether the database is already cached by macOS, and output format. If a local search is unexpectedly slow:

- Increase **CPU threads** from the default if your machine has spare cores.
- Try a smaller or more focused database.
- Keep databases on fast local SSD storage rather than external or network disks.
- Reduce **Max target sequences** while testing.
- Prefer tabular output for large batch workflows; pairwise alignments are easier to read but more expensive to format.

## Comparing Two Sequences

To compare two sequences directly:

1. Open **Run BLAST**.
2. Paste or choose the query FASTA.
3. Check **Align two sequences**.
4. Paste or choose the subject FASTA.
5. Optionally enter query or subject ranges such as `1-250`.
6. Run the search.

This mode uses `-subject` instead of `-db`, for example:

```sh
blastp -query query.faa -subject subject.faa -out pairwise.txt
```

## Aligning Three Or More Sequences

To run a local multiple sequence alignment:

1. Open **Run BLAST**.
2. Choose `BLASTN` for DNA or `BLASTP` for protein.
3. Paste or choose a FASTA file containing at least three records.
4. Check **Align 3+ sequences**.
5. Run the alignment.

This mode uses Clustal Omega through `clustalo`, for example:

```sh
clustalo -i sequences.fasta -o alignment.aln --force --outfmt=clu --seqtype=DNA
```

## How Downloads Work

NCBI distributes preformatted BLAST databases as archives, often split into many volumes. Local BLAST Studio delegates downloads to NCBI's official script:

```sh
update_blastdb.pl --decompress --blastdb_version 5 core_nt
```

The app can also fall back when an older script does not support `--blastdb_version`.

ClusteredNR (`nr_cluster_seq`) is published through NCBI's ClusteredNR experimental metadata rather than the regular `update_blastdb.pl --showall` manifest. Local BLAST Studio treats it as a recommended BLASTP starter database and downloads it directly from NCBI's experimental archive list.

When **Decompress after download** is enabled, the app downloads `.tar.gz` archives, extracts the BLAST database files, and keeps checksum files. During a download, temporary storage can be higher than the final installed database size because archives and extracted files can overlap.

Downloads are resumable in practice because rerunning `update_blastdb.pl` skips or reuses existing local archives/files when possible.

## Database Sizes

These sizes come from NCBI's BLAST metadata manifest on May 2, 2026. `nr_cluster_seq` comes from NCBI's ClusteredNR experimental metadata. They change as NCBI updates the databases.

| Database | Volumes | Compressed Download | Installed Size | Last Updated |
|---|---:|---:|---:|---|
| `core_nt` | 88 | 291.86 GB | not yet measured | 2026-04-29 |
| `nr_cluster_seq` | 247 | 243.06 GB | not yet measured | 2026-04-24 |
| `nt` | 313 | 811.66 GB | 967.59 GB | 2026-04-29 |
| `nr` | 156 | 360.47 GB | 695.75 GB | 2026-04-28 |
| `refseq_protein` | 59 | 143.69 GB | 261.32 GB | 2026-04-30 |
| `refseq_rna` | 20 | 63.87 GB | 73.15 GB | 2026-04-22 |
| `patnt` | 9 | 8.70 GB | 17.70 GB | 2026-04-16 |
| `tsa_nt` | 4 | 3.53 GB | 6.35 GB | 2026-04-28 |
| `tsa_nr` | 5 | 3.26 GB | 6.10 GB | 2026-04-29 |
| `env_nr` | 3 | 2.22 GB | 4.46 GB | 2026-04-29 |
| `env_nt` | 1 | 0.42 GB | 0.44 GB | 2026-04-26 |
| `swissprot` | 1 | 0.22 GB | 0.36 GB | 2026-04-14 |
| `pdbaa` | 1 | 0.12 GB | 0.25 GB | 2026-04-14 |
| `16S_ribosomal_RNA` | 1 | 0.07 GB | 0.02 GB | 2026-04-30 |
| `pdbnt` | 1 | 0.07 GB | 0.01 GB | 2026-04-20 |
| `taxdb` | 1 | 0.06 GB | 0.29 GB | 2026-04-30 |

The full current NCBI metadata manifest contained 38 database groups totaling about:

| Scope | Compressed Download | Installed Size |
|---|---:|---:|
| Full manifest | 2.95 TB | 3.90 TB |

Do not assume your disk only needs the installed-size number. Leave extra space for in-progress downloads, decompression, failed partial archives, filesystem overhead, and macOS purgeable-space behavior.

## Download Time Estimates

Download time depends mostly on NCBI/network throughput and whether the script is doing one file at a time or parallel cloud downloads.

Approximate time formula:

```text
download hours = compressed GB / (MB per second * 3.6)
```

Examples:

| Download | At 10 MB/s | At 25 MB/s | At 50 MB/s |
|---|---:|---:|---:|
| `swissprot` | under 1 min | under 1 min | under 1 min |
| `refseq_rna` | 1.8 hr | 43 min | 21 min |
| `refseq_protein` | 4.0 hr | 1.6 hr | 48 min |
| `nr_cluster_seq` | 6.8 hr | 2.7 hr | 1.4 hr |
| `core_nt` | 8.1 hr | 3.2 hr | 1.6 hr |
| `nr` | 10.0 hr | 4.0 hr | 2.0 hr |
| `nt` | 22.5 hr | 9.0 hr | 4.5 hr |
| Full manifest | 81.9 hr | 32.7 hr | 16.4 hr |

After downloading, decompression and checksum work can add more time.

## Storage Planning

For most users:

- Start with `core_nt` for BLASTN. It is the practical nucleotide starter database and is much smaller than full `nt`.
- Start with ClusteredNR, `nr_cluster_seq`, for BLASTP. It searches representative protein clusters from `nr` and is the preferred protein starter set.
- Add `taxdb` when you need taxonomy names in reports.
- Add `nr` or `nt` only when you specifically need the broader legacy collections.
- Avoid downloading the full manifest unless you have multiple terabytes free and a clear need.

macOS Finder may show "free" space that includes purgeable storage. Terminal tools such as `df -h` often show immediately available non-purgeable space. Plan using the more conservative number.

## Installed Databases From The Development Run

The development machine successfully installed and verified these databases with `blastdbcmd -info` or filesystem scanning:

```text
16S_ribosomal_RNA
env_nr
env_nt
landmark
nr
nt
patnt
pdbaa
pdbnt
refseq_protein
refseq_rna
swissprot
taxdb
tsa_nr
tsa_nt
```

Some legacy names may appear in older starter lists or older BLAST scripts but not in the current version 5 metadata manifest. If a database does not install, refresh the catalog and rely on the current NCBI list.

## Project Layout

```text
Package.swift
Sources/LocalBlastCore/        Core BLAST models, command builder, database scanner
Sources/LocalBlastStudio/      SwiftUI macOS app
Sources/LocalBlastSmokeTests/  Lightweight executable smoke checks
Resources/                     App icon source
scripts/package_app.sh         Release app bundle packaging
scripts/package_dmg.sh         Universal Intel/Apple Silicon DMG packaging
```

## References

- [NCBI BLAST database downloads](https://www.ncbi.nlm.nih.gov/books/NBK569850/)
- [BLAST+ quick start](https://www.ncbi.nlm.nih.gov/books/NBK569856/)
- [NCBI BLAST FTP index](https://ftp.ncbi.nlm.nih.gov/blast/db/)
- [NCBI BLAST metadata manifest](https://ftp.ncbi.nlm.nih.gov/blast/db/blastdb-metadata-1-1.json)
