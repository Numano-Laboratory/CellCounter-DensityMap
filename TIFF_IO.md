# TIFF input and output

The active source distribution replaces the previous third-party `loadtiff.m` and `saveastiff.m` implementations.

## Reader

`Analyzer/loadtiff.m`, `Analyzer/TiffLoader/loadtiff_native.cpp`, and `buildLoadtiffMex.m` were transferred from ColAnalyzer. The native reader uses the MEX API, standard C++, and operating-system memory mapping, without directly linking LibTIFF. It accelerates supported uncompressed TIFF layouts. `Backend="auto"` falls back to MATLAB's `tiffreadVolume` for unsupported layouts; corrupt inputs raise an error. Without a MEX binary, the MATLAB backend remains available. This backend requires Image Processing Toolbox and MATLAB R2020b or later.

Build the optional native reader for your platform:

```matlab
addpath('Analyzer', fullfile('Analyzer', 'TiffLoader'));
mex -setup C++
buildLoadtiffMex;
image = loadtiff('density.tif');
```

Use `Backend="matlab"` to force the MATLAB decoder or `Backend="native"` to require the MEX. Color stacks use H-by-W-by-C-by-N layout; grayscale stacks use H-by-W-by-N. Mixed page sizes/types and complex encodings are not promised as compatible with the former reader.

## Writer

`Analyzer/saveastiff.m` is a new implementation using MATLAB's documented `Tiff` API, rather than a modification of the previous writer. It preserves stored sample values and numeric class without rescaling.

```matlab
options = struct('compress','lzw', 'overwrite',false, 'message',false);
saveastiff(single(density), 'density.tif', options);
```

- Supported types: uint8/16/32, int8/16/32, single, double.
- Grayscale: H-by-W-by-N. RGB: H-by-W-by-3-by-N with `color=true`.
- Compression: `no`, `lzw`, or `adobe` (lossless).
- `big=true` selects BigTIFF; the default is classic TIFF.
- Existing files require `overwrite=true`. The writer completes a temporary file before replacing the destination.
- `append=true`, JPEG compression, complex/logical/64-bit-integer samples, and unknown options are rejected. This is not complete compatibility with the former writer.
- Success returns 0; failure throws an error rather than returning a numeric error code.

## Verification

On MATLAB R2024b / Windows, a native MEX was built from source using Microsoft Visual C++ 2022. Tests check exact values and types for all eight numeric classes across classic TIFF/BigTIFF and three compression modes (48 combinations), against both automatic and MATLAB readers and the native reader where supported. RGB stacks, overwrite protection, and rejected options are also covered.

After building the MEX, run:

```matlab
results = runtests(fullfile('tests', 'testTiffIO.m'));
assertSuccess(results);
```

These tests do not establish compatibility with every third-party TIFF encoding or validate files larger than 4 GB. This change does not update previously compiled GUI executables; those must be rebuilt separately if their bundled dependencies are to change.
