function [bin, map3] = map2bin(uksz, lksz, tmap, map)
%MAP2BIN Locate regional maxima using multi-scale density-map integration (MSDMI).
% [bin, score] = map2bin(upperKernel, lowerKernel, threshold, map)
% Returns a logical maxima mask and the accumulated threshold-crossing score.
map3 = map*0;
for ksz = lksz:uksz
    map2 = movsum(map, ksz, 1);
    map2 = movsum(map2,ksz, 2);
    map3 = map3 + double(map2 >= tmap);
end
bin = imregionalmax(map3);