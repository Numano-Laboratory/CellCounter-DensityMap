function result = optimizeMSDMI(map, human_eye, ukszList, lkszList, tmapList, varargin)
%OPTIMIZEMSDMI Fast parameter search using localization and count accuracy.
%
% result = optimizeMSDMI(map, human_eye, ukszList, lkszList, tmapList)
%
% Each moving sum is calculated only once per (tmap, kernel size), instead
% of rerunning the whole map2bin function for every parameter combination.
%
% Candidate quality is measured with OSPA distance. OSPA performs a
% one-to-one assignment, measures localization error, and charges the same
% CutoffDistance for every missed or excess point. Its unit is pixels.
%
% Name-value options:
%   "CutoffDistance"  Maximum useful matching distance in pixels (default 20)
%   "Order"           OSPA order, normally 1 or 2 (default 1)
%   "Verbose"         true (default) or false

parser = inputParser;
parser.addParameter("CutoffDistance", 20);
parser.addParameter("Order", 1);
parser.addParameter("Verbose", true);
parser.parse(varargin{:});

cutoff = parser.Results.CutoffDistance;
order = parser.Results.Order;
verbose = logical(parser.Results.Verbose);

validateattributes(map, {'numeric', 'logical'}, ...
    {'2d', 'nonempty', 'real', 'finite'}, mfilename, 'map');
validateattributes(human_eye, {'numeric'}, ...
    {'2d', 'ncols', 2, 'nonempty', 'real', 'finite'}, ...
    mfilename, "human_eye");
validateattributes(ukszList, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'}, mfilename, 'ukszList');
validateattributes(lkszList, {'numeric'}, ...
    {'vector', 'integer', 'positive', 'finite'}, mfilename, 'lkszList');
validateattributes(tmapList, {'numeric'}, ...
    {'vector', 'real', 'finite'}, mfilename, 'tmapList');
validateattributes(cutoff, {'numeric'}, ...
    {'scalar', 'real', 'positive', 'finite'}, mfilename, 'CutoffDistance');
validateattributes(order, {'numeric'}, ...
    {'scalar', 'real', 'positive', 'finite'}, mfilename, 'Order');

ukszList = unique(ukszList(:));
lkszList = unique(lkszList(:));
tmapList = unique(tmapList(:));
allKernelSizes = (min(lkszList):max(ukszList)).';
nGT = size(human_eye, 1);
validPairs = lkszList <= ukszList.';
nCandidates = sum(validPairs(:)) * numel(tmapList);

uksz = zeros(nCandidates, 1);
lksz = zeros(nCandidates, 1);
tmap = zeros(nCandidates, 1);
nPred = zeros(nCandidates, 1);
countDifference = zeros(nCandidates, 1);
assignmentDistance = inf(nCandidates, 1);
ospaDistance = inf(nCandidates, 1);

row = 0;

% Moving sums do not depend on tmap. Cache each kernel result once for the
% entire search; thresholding these cached maps is much cheaper.
summedMaps = cell(numel(allKernelSizes), 1);
for ki = 1:numel(allKernelSizes)
    kernelSize = allKernelSizes(ki);
    summed = movsum(map, kernelSize, 1);
    summedMaps{ki} = movsum(summed, kernelSize, 2);
end

for ti = 1:numel(tmapList)
    threshold = tmapList(ti);
    if verbose
        fprintf("MSDMI search: tmap %.6g (%d/%d)\n", ...
            threshold, ti, numel(tmapList));
    end

    % Reuse the cached moving sums at the current threshold.
    hits = cell(numel(allKernelSizes), 1);
    for ki = 1:numel(allKernelSizes)
        hits{ki} = summedMaps{ki} >= threshold;
    end

    for li = 1:numel(lkszList)
        lower = lkszList(li);
        accumulated = zeros(size(map), 'double');

        for upper = lower:max(ukszList)
            hitIndex = upper - allKernelSizes(1) + 1;
            accumulated = accumulated + hits{hitIndex};

            if ~ismember(upper, ukszList)
                continue
            end

            row = row + 1;
            bw = imregionalmax(accumulated);
            props = regionprops(bw, "Centroid");
            if isempty(props)
                predicted = zeros(0, 2);
            else
                predicted = cat(1, props.Centroid);
            end

            uksz(row) = upper;
            lksz(row) = lower;
            tmap(row) = threshold;
            nPred(row) = size(predicted, 1);
            countDifference(row) = abs(nPred(row) - nGT);
            [ospaDistance(row), assignmentDistance(row)] = ...
                calculateOSPA(human_eye, predicted, cutoff, order);
        end
    end
end

candidates = table(uksz, lksz, tmap, nPred, countDifference, ...
    assignmentDistance, ospaDistance);
candidates = sortrows(candidates, ...
    {'ospaDistance', 'countDifference', 'assignmentDistance'});

% OSPA is the recommended joint optimum. Count-first is also returned so
% the user can explicitly require equal/closest counts without rerunning.
best = candidates(1, :);
countFirst = sortrows(candidates, ...
    {'countDifference', 'assignmentDistance', 'ospaDistance'});
bestCountFirst = countFirst(1, :);

isDominated = false(height(candidates), 1);
for i = 1:height(candidates)
    noWorse = candidates.countDifference <= candidates.countDifference(i) & ...
        candidates.assignmentDistance <= candidates.assignmentDistance(i);
    strictlyBetter = candidates.countDifference < candidates.countDifference(i) | ...
        candidates.assignmentDistance < candidates.assignmentDistance(i);
    isDominated(i) = any(noWorse & strictlyBetter);
end
pareto = candidates(~isDominated, :);
pareto = sortrows(pareto, {'countDifference', 'assignmentDistance'});

[bestBin, bestMap3] = map2bin(best.uksz, best.lksz, best.tmap, map);
bestProps = regionprops(bestBin, "Centroid");
if isempty(bestProps)
    bestCentroids = zeros(0, 2);
else
    bestCentroids = cat(1, bestProps.Centroid);
end

result.best = best;
result.bestCountFirst = bestCountFirst;
result.pareto = pareto;
result.candidates = candidates;
result.bin = bestBin;
result.map3 = bestMap3;
result.centroids = bestCentroids;
result.nHuman = nGT;
result.cutoffDistance = cutoff;
result.order = order;

if verbose
    fprintf("\nBest joint optimum (OSPA)\n");
    printCandidate(best, nGT);
    fprintf("\nBest count-first candidate\n");
    printCandidate(bestCountFirst, nGT);
end
end

function [ospa, matchedMean] = calculateOSPA(reference, predicted, cutoff, order)
nReference = size(reference, 1);
nPredicted = size(predicted, 1);
nLarge = max(nReference, nPredicted);

if nLarge == 0
    ospa = 0;
    matchedMean = 0;
    return
elseif nReference == 0 || nPredicted == 0
    ospa = cutoff;
    matchedMean = inf;
    return
end

cost = min(pdist2(reference, predicted, "euclidean"), cutoff);

% Since every entry is <= cutoff, this forces min(nReference,nPredicted)
% unique matches. Unmatched points are handled by the OSPA cardinality term.
pairs = matchpairs(cost.^order, cutoff^order + eps);
distances = cost(sub2ind(size(cost), pairs(:, 1), pairs(:, 2)));
matchedMean = mean(distances);

localization = sum(distances.^order);
cardinality = cutoff^order * abs(nReference - nPredicted);
ospa = ((localization + cardinality) / nLarge)^(1 / order);
end

function printCandidate(candidate, nHuman)
fprintf("  uksz = %d, lksz = %d, tmap = %.6g\n", ...
    candidate.uksz, candidate.lksz, candidate.tmap);
fprintf("  points = %d (human = %d, difference = %d)\n", ...
    candidate.nPred, nHuman, candidate.countDifference);
fprintf("  matched distance = %.4f px, OSPA = %.4f px\n", ...
    candidate.assignmentDistance, candidate.ospaDistance);
end
