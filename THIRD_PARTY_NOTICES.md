# External dependencies

The active TIFF reader is the independent ColAnalyzer implementation; the active writer is a new implementation using MATLAB's Tiff API. The former YoonOh Tak TIFF implementations are no longer included as analysis-source files. Their notices still apply to historical copies and any binaries that embed them.

MATLAB, MATLAB Runtime, toolboxes, and compiler/runtime components remain subject to their respective terms and notices. Calling MATLAB's Tiff API does not remove those dependencies: that API uses MATLAB's LibTIFF integration. The optional native reader has no direct LibTIFF linkage.

See TIFF_IO.md for implementation scope, build instructions, and verification. GUI binaries are supplied separately by the maintainer; analysis-source changes alone do not identify the implementation embedded in them.

## Supplied GUI executables

The maintainer supplied corrected GUI binaries and reported replacing the former TIFF reader. The earlier build-project dependency list does not establish the contents of these binaries. See [GUI dependency notes](downloads/windows/v3r1b1/THIRD_PARTY_NOTICES.txt) and [installation instructions](downloads/windows/v3r1b1/README.md). The statement above about the former reader applies to older copies containing it.

## macOS GUI downloads

The Mac installer payload supplies a TIFF component MIT notice. It is retained in downloads/macos/v3r1b1/TiffLoader_LICENSE.txt and both Mac ZIPs. GUI usage terms and Runtime requirements are in downloads/macos/v3r1b1/README.md. This notice does not imply verification of all embedded components.
