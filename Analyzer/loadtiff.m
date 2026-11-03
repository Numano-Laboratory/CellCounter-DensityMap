% --- Function -----------------------------------------------------------
% image = loadtiff(path, options)
% Read a TIFF stack, with an optional AVI compatibility path.
%
% --- Input --------------------------------------------------------------
% path : (character row vector or string scalar) Image file path.
% options : Name-value arguments (optional).
%     Backend : Reader backend: "auto", "matlab", or "native".
%               Default: "auto".
%               "auto" uses the native MEX when supported, then falls back
%               to MATLAB for unsupported TIFF layouts.
%               "matlab" uses tiffreadVolume directly.
%               "native" requires loadtiff_native and errors if the file
%               uses an unsupported TIFF layout.
%
% --- Output -------------------------------------------------------------
% image : Image data. Grayscale stacks are [height, width, frames]; color
%         stacks are [height, width, channels, frames]. The stored numeric
%         class and sample values are preserved. One-bit TIFF data is logical;
%         2-bit and 4-bit TIFF data is uint8 without rescaling.
%         AVI frames are converted to grayscale when they have three color
%         channels.
%
% --- Notes --------------------------------------------------------------
% The MATLAB TIFF fallback requires MATLAB R2020b or later and Image
% Processing Toolbox. The native MEX is optional; run buildLoadtiffMex to
% build it for the current platform. This reader is an independent
% implementation and does not change the working folder or warning state.
%
% --- Related -----------------------------------------------------------
% BatchColAnalyzer > DoLoadVideo > loadtiff
% loadtiff > loadtiff_native (optional native TIFF backend)
% loadtiff > tiffreadVolume (MATLAB TIFF backend)
% loadtiff > VideoReader > rgb2gray (AVI input)
% loadtiff > Tiff (WhiteIsZero sample correction)
% buildLoadtiffMex > TiffLoader/loadtiff_native.cpp
% --

function image = loadtiff(path, options)
arguments
    path
    options.Backend (1,1) string {mustBeMember(options.Backend, ...
        ["auto", "matlab", "native"])} = "auto"
end
% Keep the public entry point at the repository root and its support files
% together. Resolve the folder from this file, independent of the caller's cwd.
loaderFolder = fullfile(fileparts(mfilename('fullpath')), 'TiffLoader');
if exist('loadtiff_native', 'file') ~= 3 && isfolder(loaderFolder)
    addpath(loaderFolder);
end
if isstring(path) && isscalar(path) && ~ismissing(path)
    path = char(path);
end
if ~ischar(path) || ~isrow(path) || isempty(path) || any(path == char(0))
    error('loadtiff:InvalidPath', 'Path must be a nonempty character row vector or string scalar.');
end
if ~isfile(path)
    error('loadtiff:FileNotFound', 'File does not exist: %s', path);
end
[~, ~, extension] = fileparts(path);
if strcmpi(extension, '.avi')
    frames = read(VideoReader(path));
    if size(frames, 3) == 3
        image = zeros(size(frames, 1), size(frames, 2), size(frames, 4), 'like', frames);
        for k = 1:size(frames, 4)
            image(:,:,k) = rgb2gray(frames(:,:,:,k));
        end
    else
        image = reshape(frames, size(frames, 1), size(frames, 2), []);
    end
    return
end
if options.Backend ~= "matlab"
    if exist('loadtiff_native', 'file') == 3
        try
            image = loadtiff_native(path);
        catch failure
            if options.Backend == "auto" && strcmp(failure.identifier, 'MATLAB:invalidMEXFile')
                image = []; % A binary from another MATLAB release can be rebuilt.
            else
                rethrow(failure);
            end
        end
        if ~isempty(image), return; end
        if options.Backend == "native"
            error('loadtiff:NativeUnsupported', ...
                'The native reader does not support this TIFF encoding. Use Backend="auto" or "matlab".');
        end
    elseif options.Backend == "native"
        error('loadtiff:MexUnavailable', 'Run buildLoadtiffMex to build the native reader.');
    end
end
image = tiffreadVolume(path);
% tiffreadVolume puts color after the frame dimension; the public API keeps
% the conventional MATLAB image layout H-by-W-by-C-by-N.
if ndims(image) == 4
    image = permute(image, [1 2 4 3]);
end
if islogical(image) || isa(image, 'uint8') || isa(image, 'int8')
    % MATLAB normalizes WhiteIsZero images with <=8 bits for display. Undo
    % that normalization so numeric samples retain the old reader's meaning.
    t = Tiff(path, 'r');
    closer = onCleanup(@()close(t));
    if getTag(t, 'Photometric') == Tiff.Photometric.MinIsWhite
        bits = getTag(t, 'BitsPerSample');
        if islogical(image)
            image = ~image;
        elseif isa(image, 'uint8')
            image = uint8(2^bits-1)-image;
        else
            % imread saturates signed 8-bit WhiteIsZero samples, which cannot
            % be undone arithmetically. Tiff.read returns their original bits.
            for k = 1:size(image, 3)
                image(:,:,k) = read(t);
                if k < size(image, 3), nextDirectory(t); end
            end
        end
    end
end
end
