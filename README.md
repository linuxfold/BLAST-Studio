# Local BLAST Studio

<img width="500" height="500" alt="ChatGPT Image May 1, 2026, 01_02_34 AM" src="https://github.com/user-attachments/assets/226fc2b0-1eae-42ec-b37a-794ff4673eae" />

Local BLAST Studio is a native macOS app for running the NCBI BLAST+ command-line suite locally through a GUI. It wraps your installed BLAST+ binaries, scans your local BLAST database folder, manages downloads with NCBI's `update_blastdb.pl`, and keeps the generated command line visible before each run.

>If installing from precompiled .dmg, after dragging the app into your Aplications, type: xattr -dr com.apple.quarantine /Applications/LocalBlastStudio.app

The app is intentionally local-first. It does not contact NCBI on launch, and it does not upload query sequences. It contacts NCBI only when you explicitly click **Refresh Catalog** or **Download Selected**.

## Features

- Runs local `blastn`, `blastp`, `blastx`, `tblastn`, `tblastx`, `psiblast`, `rpsblast`, `rpstblastn`, and `deltablast`.
- Supports local database searches with downloaded BLAST databases such as `nt`, `nr`, `refseq_protein`, and `refseq_rna`.
- Supports pairwise sequence comparison with **Align two sequences**, using BLAST+'s `-subject` mode instead of a database.
- Provides website-style controls for common BLAST parameters: task, E-value, max target sequences, word size, scoring, filters, masking, output format, genetic code, ranges, and PSI-BLAST settings.
- Provides a raw advanced-arguments field, appended last, for BLAST+ switches that are not yet represented by structured controls.
- Discovers downloadable NCBI database names with `update_blastdb.pl --showall` when requested.
- Downloads and optionally decompresses selected databases with `update_blastdb.pl`.
- Builds custom nucleotide or protein databases with `makeblastdb`.
- Shows installed database count, storage use, file count, installed database badges, and catalog entries that are not installed.
- Packages as a standard macOS `.app` bundle with a custom icon.

## Privacy And Network Behavior

Startup is offline. On launch the app:

1. Scans your configured BLASTDB folder.
2. Checks local BLAST+ tool paths and versions.
3. Builds the command preview locally.

The app contacts NCBI only for these explicit actions:

- **Refresh Catalog**: runs `update_blastdb.pl --showall` to retrieve the current list of downloadable databases.
- **Download Selected**: runs `update_blastdb.pl` for the selected database names.

Normal BLAST searches run locally with your installed BLAST+ binaries. The app does not send query FASTA content to NCBI.

## Requirements

- macOS 14 or newer.
- Swift 6 toolchain to build from source.
- NCBI BLAST+ installed locally.
- Perl and `curl`, which are used by NCBI's `update_blastdb.pl`.
- Enough disk space for selected databases.

On the development machine used for this build, BLAST+ was installed at:

```sh
/opt/homebrew/anaconda3/bin
```

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
dist/BLAST-Studio-0.1.0-universal.dmg
```

The DMG script builds separate `arm64` and `x86_64` release binaries, combines them with `lipo`, creates a drag-to-Applications disk image, and ad-hoc signs the app by default. It is not notarized. To sign with a Developer ID certificate, run it with `CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package_dmg.sh`.

## First Launch

1. Open **Tools** and confirm BLAST+ tools are detected.
2. If needed, set the BLAST+ bin directory, for example `/opt/homebrew/anaconda3/bin`.
3. Open **Databases** and choose a BLASTDB directory.
4. The app scans installed databases immediately without contacting NCBI.
5. Click **Refresh Catalog** only when you want to fetch the latest downloadable list from NCBI.
6. Select databases and click **Download Selected**.
7. Open **Run BLAST**, paste or choose a FASTA query, pick a database, set options, and run.

## Running A Database Search

For a normal search, leave **Align two sequences** unchecked.

The app generates a command shaped like:

```sh
blastn -query query.fasta -db /path/to/blastdb/nt -out result.txt -task megablast
```

The app sets `BLASTDB` for the BLAST process and also passes the selected database path directly.

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

## How Downloads Work

NCBI distributes preformatted BLAST databases as archives, often split into many volumes. Local BLAST Studio delegates downloads to NCBI's official script:

```sh
update_blastdb.pl --decompress --blastdb_version 5 nt nr
```

The app can also fall back when an older script does not support `--blastdb_version`.

When **Decompress after download** is enabled, the script downloads `.tar.gz` archives, extracts the BLAST database files, keeps checksum files, and removes the large archive payloads after extraction. During a download, temporary storage can be higher than the final installed database size because archives and extracted files can overlap.

Downloads are resumable in practice because rerunning `update_blastdb.pl` skips or reuses existing local archives/files when possible.

## Database Sizes

These sizes come from NCBI's BLAST metadata manifest on May 2, 2026. They change as NCBI updates the databases.

| Database | Volumes | Compressed Download | Installed Size | Last Updated |
|---|---:|---:|---:|---|
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
| `nr` | 10.0 hr | 4.0 hr | 2.0 hr |
| `nt` | 22.5 hr | 9.0 hr | 4.5 hr |
| Full manifest | 81.9 hr | 32.7 hr | 16.4 hr |

After downloading, decompression and checksum work can add more time.

## Storage Planning

For most users:

- Start with `taxdb`, `swissprot`, `refseq_rna`, and `refseq_protein`.
- Add `nr` when you need broad protein search coverage.
- Add `nt` when you need broad nucleotide search coverage.
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
