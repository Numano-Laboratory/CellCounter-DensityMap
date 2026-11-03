function tests = testAnalysis
tests = functiontests(localfunctions);
end

function setup(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root,'Analyzer')));
end

function testKnownDetection(testCase)
map = zeros(17,19); map(8,12) = 10;
[bin, score] = map2bin(1,1,5,map);
expected = false(size(map)); expected(8,12) = true;
verifyEqual(testCase, bin, expected);
verifyEqual(testCase, score, double(expected));
props = regionprops(bin,'Centroid');
verifyEqual(testCase, props.Centroid, [12 8]);

end

function testSearchMatchesDirectDetector(testCase)
map = zeros(21); map(6,7) = 12; map(16,15) = 20;
reference = [7 6; 15 16];
result = optimizeMSDMI(map,reference,[1 3 5],[1 3],[5 15],'Verbose',false);
verifyEqual(testCase, height(result.candidates), 10);
for i = 1:height(result.candidates)
    row = result.candidates(i,:);
    bin = map2bin(row.uksz,row.lksz,row.tmap,map);
    props = regionprops(bin,'Centroid');
    verifyEqual(testCase,row.nPred,numel(props));
end
[bin,score] = map2bin(result.best.uksz,result.best.lksz,result.best.tmap,map);
verifyEqual(testCase,result.bin,bin);
verifyEqual(testCase,result.map3,score);
verifyEqual(testCase,result.best.ospaDistance,0,'AbsTol',1e-12);
end
