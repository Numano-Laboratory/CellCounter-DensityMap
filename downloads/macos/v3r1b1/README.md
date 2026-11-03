# CellCounter v3r1b1 for macOS — Apple Silicon

| Your environment | Download |
| --- | --- |
| First installation | [Download installer ZIP](CellCounter_v3r1b1-installer-macOS-AppleSilicon.zip?raw=true) |
| Compatible Runtime already installed | [Download application ZIP](CellCounter_v3r1b1-macOS-AppleSilicon.zip?raw=true) |

These binaries target Apple Silicon (arm64), not Intel Mac. The supplied app metadata specifies macOS 12 or later; this is metadata, not verification of every macOS release. The installer requests MATLAB Runtime R2024b Update 10 for Apple Silicon. MATLAB itself is not required.

## Installation

Download and extract the installer ZIP on your Mac, then open `CellCounter_v3r1b1_installer.app` and follow its prompts. Internet access is required to obtain Runtime. This is not an offline Runtime package.

If compatible MATLAB Runtime is already installed, extract the application ZIP and open `CellCounter_v3r1b1.app`. Keep the extracted files together. A terminal launcher and the compiler-generated readme are also included. The launcher takes your actual Runtime directory:

```sh
./run_CellCounter_v3r1b1.sh "/path/to/MATLAB_Runtime/R2024b"
```

The path above is a placeholder. See the bundled `readme.txt` for deployment details. If macOS blocks the application, review its security notice and verify the download's origin; signing and notarization have not been established here.

## Use

Supply the bright-field image, density map, and fluorescence image expected by the GUI. Check alignment and detection settings, inspect the cell detections, then measure and export results.

The GUI is free to use; modification and redistribution require prior permission. See [GUI usage terms](GUI_LICENSE.md). The TIFF component's supplied MIT notice is in [TiffLoader_LICENSE.txt](TiffLoader_LICENSE.txt) and both ZIPs. Third-party components retain their own terms, including MATLAB Runtime.

## Verification scope

[SHA-256 checksums](SHA256SUMS.txt) identify the downloads.

Installation and the complete GUI workflow have not been verified on macOS.
