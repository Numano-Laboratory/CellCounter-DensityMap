function binaryPath = buildLoadtiffMex
%BUILDLOADTIFFMEX Build the optional, independent uncompressed TIFF reader.
% Run once on each platform after configuring a compiler with mex -setup C++.
% No external libraries or Image Processing Toolbox headers are needed.
root = fileparts(mfilename('fullpath'));
source = fullfile(root, 'loadtiff_native.cpp');
clear loadtiff_native
flags = {};
compiler = mex.getCompilerConfigurations('C++', 'Selected');
if ~isempty(compiler)
    if ispc && contains(compiler.Manufacturer, 'Microsoft')
        flags = {'COMPFLAGS=$COMPFLAGS /openmp'};
    elseif isunix && ~ismac && contains(compiler.Manufacturer, 'GNU')
        flags = {'CXXFLAGS=$CXXFLAGS -fopenmp', 'LDFLAGS=$LDFLAGS -fopenmp'};
    end
end
mex('-R2018a', '-O', flags{:}, '-outdir', root, '-output', 'loadtiff_native', source);
binaryPath = fullfile(root, ['loadtiff_native.' mexext]);
fprintf('Built %s\n', binaryPath);
end
