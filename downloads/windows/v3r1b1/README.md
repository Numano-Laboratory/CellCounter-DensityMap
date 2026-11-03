# CellCounter v3r1b1 for Windows

## Download and start

| Your environment | Download |
| --- | --- |
| First installation | [Download installer](CellCounter_v3r1b1_installer.exe?raw=true) |
| MATLAB Runtime R2024b is already installed | [Download application](CellCounter_v3r1b1.exe?raw=true) |

The installer obtains MATLAB Runtime over the internet. It is not an offline Runtime bundle. Run the downloaded installer and follow its prompts. If using the application executable directly, install Windows x64 MATLAB Runtime R2024b first, then run the executable. MATLAB itself is not required.

[Download MATLAB Runtime from MathWorks](https://www.mathworks.com/products/compiler/mcr/index.html)

## Basic workflow

Select the bright-field image, corresponding density map, and fluorescence image expected by the GUI. Check alignment, kernel sizes, and the density-map threshold. Run cell counting, inspect detections, then measure fluorescence and export results. Generate prediction maps separately; trained models and experimental data are not included.

## Usage

The GUI is free to use. Modification and redistribution require prior permission; share the repository link instead. See [GUI usage terms](GUI_LICENSE.md).

## Distribution

GUI source is excluded. The repository's MIT license covers the published analysis source and does not grant rights to excluded GUI source. MathWorks products retain their own terms; see [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

[SHA-256 checksums](SHA256SUMS.txt) identify these exact downloads. Installation and the complete GUI workflow have not been verified on a clean Runtime-only machine.
