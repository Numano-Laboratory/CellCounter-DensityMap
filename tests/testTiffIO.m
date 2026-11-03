function tests = testTiffIO
tests = functiontests(localfunctions);
end

function setup(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
    fullfile(root, 'Analyzer')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
    fullfile(root, 'Analyzer', 'TiffLoader')));
folder = testCase.applyFixture( ...
    matlab.unittest.fixtures.TemporaryFolderFixture);
testCase.TestData.folder = folder.Folder;
end

function testNumericRoundTrips(testCase)
types = {'uint8','uint16','uint32','int8','int16','int32', ...
    'single','double'};
filename = fullfile(testCase.TestData.folder, 'numeric.tif');
for k = 1:numel(types)
    source = cast(reshape(-50:69, 5,8,3), types{k});
    if isfloat(source), source = source / 7; end
    for big = [false true]
        for compression = {'no','lzw','adobe'}
            options = struct('big',big, 'compress',compression{1}, ...
                'overwrite',true, 'message',false);
            verifyEqual(testCase, saveastiff(source,filename,options), 0);
            verifyEqual(testCase, loadtiff(filename), source);
            verifyEqual(testCase, ...
                loadtiff(filename,Backend="matlab"), source);
            if strcmp(compression{1}, 'no') && exist('loadtiff_native','file') == 3
                verifyEqual(testCase, ...
                    loadtiff(filename,Backend="native"), source);
            end
        end
    end
end
end

function testRgbRoundTrip(testCase)
filename = fullfile(testCase.TestData.folder, 'rgb.tif');
source = uint16(reshape(1:360,5,12,3,2));
saveastiff(source,filename,struct('color',true,'message',false));
if exist('loadtiff_native','file') == 3
    verifyEqual(testCase, loadtiff(filename,Backend="native"), source);
end
verifyEqual(testCase, loadtiff(filename,Backend="matlab"), source);
end

function testNoClobberAndRejectedOptions(testCase)
filename = fullfile(testCase.TestData.folder, 'protected.tif');
source = single([0 0.125; 1.5 20.75]);
saveastiff(source,filename,struct('message',false));
verifyError(testCase, @() saveastiff(source*2,filename), ...
    'saveastiff:FileExists');
verifyError(testCase, @() saveastiff(source,filename, ...
    struct('append',true)), 'saveastiff:AppendUnsupported');
verifyError(testCase, @() saveastiff(source,filename, ...
    struct('jpegquality',90)), 'saveastiff:UnknownOption');
verifyEqual(testCase, loadtiff(filename), source);
verifyEqual(testCase, numel(dir(fullfile( ...
    testCase.TestData.folder, '*.tif'))), 1);
end
