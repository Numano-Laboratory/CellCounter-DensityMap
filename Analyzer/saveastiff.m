function result = saveastiff(data, filename, options)
%SAVEASTIFF Write numeric TIFF images using the MATLAB Tiff API.
% Independent implementation for CellCounter-DensityMap, MIT licensed.
% Grayscale: H-by-W-by-N. RGB: H-by-W-by-3-by-N with color=true.
% Options: color, big, overwrite, message (logical scalars), and
% compress ('no', 'lzw', 'adobe'). append=true and JPEG are unsupported.
% Returns 0 on success; errors are thrown. No scaling or casting occurs.
% Existing files require overwrite=true. A temporary file is completed
% before replacing the destination. This is not a full legacy API clone.
if nargin < 3
    options = struct;
end
validateattributes(data, ...
    {'uint8','uint16','uint32','int8','int16','int32','single','double'}, ...
    {'real','nonempty','nonsparse'}, mfilename, 'data');
validateattributes(options, {'struct'}, {'scalar'});
if isstring(filename) && isscalar(filename) && ~ismissing(filename)
    filename = char(filename);
end
validateattributes(filename, {'char'}, {'row','nonempty'});
if any(filename == char(0))
    error('saveastiff:InvalidPath', 'Filename contains a null character.');
end
defaults = struct('color',false, 'big',false, 'overwrite',false, ...
    'message',true, 'compress','no', 'append',false);
unknown = setdiff(fieldnames(options), fieldnames(defaults));
if ~isempty(unknown)
    error('saveastiff:UnknownOption', ...
        'Unsupported option: %s.', strjoin(unknown, ', '));
end
names = fieldnames(defaults);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(options, name)
        options.(name) = defaults.(name);
    end
    if ~strcmp(name, 'compress')
        validateattributes(options.(name), {'logical'}, {'scalar'});
    end
end
if options.append
    error('saveastiff:AppendUnsupported', ...
        'Append is unsupported; write the complete stack to a new file.');
end
compression_name = validatestring(options.compress, ...
    {'no','lzw','adobe'}, mfilename, 'compress');
if options.color
    if ndims(data) > 4 || size(data,3) ~= 3
        error('saveastiff:InvalidShape', 'RGB requires H-by-W-by-3-by-N.');
    end
    frame_count = size(data,4);
    samples = 3;
    photo = Tiff.Photometric.RGB;
else
    if ndims(data) > 3
        error('saveastiff:InvalidShape', 'Grayscale requires H-by-W-by-N.');
    end
    frame_count = size(data,3);
    samples = 1;
    photo = Tiff.Photometric.MinIsBlack;
end
[folder,~,~] = fileparts(filename);
if isempty(folder), folder = pwd; end
if ~isfolder(folder) || isfolder(filename)
    error('saveastiff:InvalidPath', 'Destination must be in an existing folder.');
end
if isfile(filename) && ~options.overwrite
    error('saveastiff:FileExists', 'Use overwrite=true to replace a file.');
end
classes = {'uint8','uint16','uint32','int8','int16','int32', ...
    'single','double'};
bits = [8 16 32 8 16 32 32 64];
type_index = find(strcmp(class(data), classes), 1);
if type_index <= 3
    sample_format = Tiff.SampleFormat.UInt;
elseif type_index <= 6
    sample_format = Tiff.SampleFormat.Int;
else
    sample_format = Tiff.SampleFormat.IEEEFP;
end
compression_values = [Tiff.Compression.None, Tiff.Compression.LZW, ...
    Tiff.Compression.AdobeDeflate];
compression_index = find(strcmp(compression_name, {'no','lzw','adobe'}));
tags = struct('ImageLength',size(data,1), 'ImageWidth',size(data,2), ...
    'SamplesPerPixel',samples, 'BitsPerSample',bits(type_index), ...
    'SampleFormat',sample_format, 'Photometric',photo, ...
    'PlanarConfiguration',Tiff.PlanarConfiguration.Chunky, ...
    'Compression',compression_values(compression_index), ...
    'RowsPerStrip',min(size(data,1),64));
mode = 'w';
if options.big, mode = 'w8'; end
temporary = [tempname(folder) '.tif'];
cleanup = onCleanup(@() removeTemporary(temporary));
writeStack(temporary, mode, tags, data, options.color, frame_count);
% Check again in case the destination appeared during writing.
if isfile(filename) && ~options.overwrite
    error('saveastiff:FileExists', 'Destination appeared during writing.');
end
if options.overwrite
    [ok,message] = movefile(temporary, filename, 'f');
else
    [ok,message] = movefile(temporary, filename);
end
if ~ok, error('saveastiff:MoveFailed', '%s', message); end
result = 0;
if options.message
    fprintf('Saved %d TIFF frame(s).\n', frame_count);
end
end

function writeStack(filename, mode, tags, data, color, frame_count)
file = Tiff(filename, mode);
cleanup = onCleanup(@() close(file));
for k = 1:frame_count
    setTag(file, tags);
    if color
        write(file, data(:,:,:,k));
    else
        write(file, data(:,:,k));
    end
    if k < frame_count, writeDirectory(file); end
end
end

function removeTemporary(filename)
if isfile(filename), delete(filename); end
end
