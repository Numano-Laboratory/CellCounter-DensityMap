# Analysis source release preparation — 2026-10-29

## Scope

This distribution contains map2bin (MSDMI detector), optimizeMSDMI, TIFF input/output, and synthetic tests. The detector and evaluation functions retain their existing numerical implementations. GUI source, callbacks, icon, launchers, manuscript PDFs, datasets, session files, and old executables are excluded from the analysis source.

The detector source was originally copied from CellCounter commit `b2fc673db07166e50bc7cbe8696e6e00725c831e`. The TIFF reader was transferred from ColAnalyzer and the writer was replaced with a MATLAB Tiff-based implementation. See TIFF_IO.md for compatibility limits. Previously compiled GUI binaries are not updated by this source release.

## Validation scope

Tests exercise a known synthetic detection, agreement of optimized parameter-search candidate counts with direct detector evaluation, and numeric TIFF round trips. MATLAB dependency analysis is used to check that the retained analysis functions do not require excluded GUI files.

This is not an exact experimental reproduction release. No paper dataset validation, GUI executable build, files larger than 4 GB, or cross-platform testing is claimed.

## Publication metadata

Associated article DOI: https://doi.org/10.35848/1347-4065/aeb94f

Source code in this distribution is MIT licensed. Windows GUI v3r1b1 binaries are now supplied alongside the analysis source. Their installation requirements and dependency notices are documented separately in downloads/windows/v3r1b1/README.md and THIRD_PARTY_NOTICES.txt in that folder.

Verified on MATLAB R2024b / Windows on 2026-10-30: all five remaining test functions passed, including 48 numeric TIFF combinations. Dependency analysis reported MATLAB, Image Processing Toolbox, and Statistics and Machine Learning Toolbox, with no excluded GUI source dependencies.

## GUI v3r1b1 binaries — 2026-11-02

Added the user-supplied Windows executable and web installer. Hashes match the development build outputs. The generated deployment readme requires MATLAB Runtime R2024b. This addition does not claim a new GUI build, clean-machine validation, or synchronization with the analysis-source TIFF replacement.

## Corrected GUI downloads — 2026-11-03

Moved the maintainer's corrected executable and installer into downloads/windows/v3r1b1. The root README now links directly to both downloads and their installation guide. SHA-256 checksums were refreshed. Old build metadata is not used to assert which TIFF reader is embedded in these corrected binaries. No new compilation or clean-machine GUI validation was performed here.

## Apple Silicon Mac downloads — 2026-11-04

Added application and web-installer ZIPs in downloads/macos/v3r1b1. Runtime target: R2024b Update 10 (maca64). Original compiler payload bytes and ZIP Unix permissions are retained for the application archive; Mach-O executable modes are set for the installer archive. Archive integrity and payload byte equality were checked. No Mac execution, signing/notarization verification, or recompilation was performed.
