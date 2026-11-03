// Independent TIFF reader for the uncompressed microscopy fast path.
// Uses the MEX API, standard C++, and OS memory mapping; no LibTIFF linkage.
// Unsupported encodings return [] so loadtiff.m can use MATLAB's decoder.
#include "mex.h"
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace {
using U64 = std::uint64_t;
using Byte = unsigned char;
struct Unsupported {};
struct Invalid : std::runtime_error { using std::runtime_error::runtime_error; };

U64 add(U64 a, U64 b) {
    if (b > std::numeric_limits<U64>::max() - a) throw Invalid("TIFF size overflow.");
    return a + b;
}
U64 multiply(U64 a, U64 b) {
    if (a && b > std::numeric_limits<U64>::max() / a) throw Invalid("TIFF size overflow.");
    return a * b;
}
std::size_t hostSize(U64 value) {
    if (value > std::numeric_limits<std::size_t>::max()) throw Invalid("TIFF is too large for this platform.");
    return static_cast<std::size_t>(value);
}
U64 number(const Byte* bytes, unsigned count, bool little) {
    U64 value = 0;
    if (little) {
        for (unsigned i = count; i > 0; --i) value = (value << 8) | bytes[i - 1];
    } else {
        for (unsigned i = 0; i < count; ++i) value = (value << 8) | bytes[i];
    }
    return value;
}

class File {
    const Byte* mapped = nullptr;
#ifdef _WIN32
    HANDLE handle = INVALID_HANDLE_VALUE, mapping = nullptr;
#else
    int handle = -1;
#endif
    void close() noexcept {
#ifdef _WIN32
        if (mapped) UnmapViewOfFile(mapped);
        if (mapping) CloseHandle(mapping);
        if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
#else
        if (mapped) munmap(const_cast<Byte*>(mapped), static_cast<std::size_t>(size));
        if (handle >= 0) ::close(handle);
#endif
    }
public:
    U64 size = 0;
    explicit File(const mxArray* path) {
        try {
#ifdef _WIN32
        const mxChar* text = mxGetChars(path);
        std::wstring name(text, text + mxGetNumberOfElements(path));
        handle = CreateFileW(name.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (handle == INVALID_HANDLE_VALUE) throw Invalid("Cannot open the TIFF file for reading.");
        LARGE_INTEGER length;
        if (!GetFileSizeEx(handle, &length) || length.QuadPart < 8) throw Invalid("TIFF header is missing or truncated.");
        size = static_cast<U64>(length.QuadPart);
        hostSize(size);
        mapping = CreateFileMappingW(handle, nullptr, PAGE_READONLY, 0, 0, nullptr);
        if (!mapping) throw Unsupported();
        mapped = static_cast<const Byte*>(MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0));
        if (!mapped) throw Unsupported();
#else
        char* text = mxArrayToUTF8String(path);
        if (!text) throw Invalid("Cannot encode the filename.");
        handle = ::open(text, O_RDONLY);
        mxFree(text);
        if (handle < 0) throw Invalid("Cannot open the TIFF file for reading.");
        struct stat info;
        if (fstat(handle, &info) || info.st_size < 8) throw Invalid("TIFF header is missing or truncated.");
        size = static_cast<U64>(info.st_size);
        void* view = mmap(nullptr, hostSize(size), PROT_READ, MAP_PRIVATE, handle, 0);
        if (view == MAP_FAILED) throw Unsupported();
        mapped = static_cast<const Byte*>(view);
#endif
        } catch (...) { close(); throw; }
    }
    ~File() { close(); }
    File(const File&) = delete;
    File& operator=(const File&) = delete;
    void range(U64 offset, U64 length) const {
        if (offset > size || length > size - offset) throw Invalid("TIFF data extend beyond the end of the file.");
    }
    const Byte* data(U64 offset, U64 length) const {
        range(offset, length);
        return mapped + hostSize(offset);
    }
    std::vector<Byte> read(U64 offset, U64 length) {
        const Byte* start = data(offset, length);
        return std::vector<Byte>(start, start + hostSize(length));
    }
};

struct Page {
    U64 width = 0, height = 0, bits = 1, samples = 1, format = 1;
    U64 compression = 1, photo = 99, planar = 1, fill = 1, orientation = 1;
    U64 rows = 0xffffffffULL, predictor = 1, depth = 1, imageJFrames = 0;
    bool tiled = false, extra = false;
    std::vector<U64> offsets, counts;
};

class Reader {
    File file;
    bool little = true, big = false;
    std::vector<Page> pages;

    std::vector<U64> values(const Byte* entry) {
        const U64 type = number(entry + 2, 2, little);
        const unsigned width = type == 3 ? 2 : type == 4 ? 4 : type == 16 ? 8 : 0;
        if (!width) throw Unsupported();
        const U64 count = number(entry + 4, big ? 8 : 4, little);
        const U64 bytes = multiply(count, width);
        const Byte* source = entry + (big ? 12 : 8);
        std::vector<Byte> external;
        if (bytes > (big ? 8u : 4u)) {
            external = file.read(number(source, big ? 8 : 4, little), bytes);
            source = external.data();
        }
        std::vector<U64> result(hostSize(count));
        for (std::size_t i = 0; i < result.size(); ++i) result[i] = number(source + i * width, width, little);
        return result;
    }
    U64 scalar(const Byte* entry, bool repeated = false) {
        auto v = values(entry);
        if (v.empty()) throw Invalid("Empty required TIFF tag.");
        if ((!repeated && v.size() != 1) ||
            !std::all_of(v.begin(), v.end(), [&](U64 x) { return x == v[0]; })) throw Unsupported();
        return v[0];
    }
    void description(const Byte* entry, Page& page) {
        if (number(entry + 2, 2, little) != 2) return;
        U64 count = number(entry + 4, big ? 8 : 4, little);
        // ImageJ's stack header is at the beginning; do not load large XML metadata.
        const Byte* source = entry + (big ? 12 : 8);
        std::vector<Byte> external;
        if (count > (big ? 8u : 4u)) {
            const U64 offset = number(source, big ? 8 : 4, little);
            file.range(offset, count);
            count = std::min<U64>(count, 4096);
            external = file.read(offset, count);
            source = external.data();
        }
        const std::string text(reinterpret_cast<const char*>(source), hostSize(count));
        if (text.compare(0, 7, "ImageJ=") != 0) return;
        const auto pos = text.find("\nimages=");
        if (pos != std::string::npos) page.imageJFrames = std::strtoull(text.c_str() + pos + 8, nullptr, 10);
    }
    U64 directory(U64 offset) {
        const unsigned countWidth = big ? 8 : 2, entryWidth = big ? 20 : 12;
        auto prefix = file.read(offset, countWidth);
        const U64 count = number(prefix.data(), countWidth, little);
        const U64 bytes = add(multiply(count, entryWidth), big ? 8 : 4);
        file.range(add(offset, countWidth), bytes);
        if (count > 4096) throw Unsupported();
        auto entries = file.read(add(offset, countWidth), bytes);
        Page page;
        std::unordered_set<unsigned> seen;
        for (U64 i = 0; i < count; ++i) {
            const Byte* entry = entries.data() + hostSize(i * entryWidth);
            const unsigned tag = static_cast<unsigned>(number(entry, 2, little));
            if (!seen.insert(tag).second) throw Invalid("Duplicate tag in TIFF directory.");
            switch (tag) {
                case 256: page.width = scalar(entry); break;
                case 257: page.height = scalar(entry); break;
                case 258: page.bits = scalar(entry, true); break;
                case 259: page.compression = scalar(entry); break;
                case 262: page.photo = scalar(entry); break;
                case 266: page.fill = scalar(entry); break;
                case 270: description(entry, page); break;
                case 273: page.offsets = values(entry); break;
                case 274: page.orientation = scalar(entry); break;
                case 277: page.samples = scalar(entry); break;
                case 278: page.rows = scalar(entry); break;
                case 279: page.counts = values(entry); break;
                case 284: page.planar = scalar(entry); break;
                case 317: page.predictor = scalar(entry); break;
                case 322: case 323: case 324: case 325: page.tiled = true; break;
                case 338: page.extra = true; break;
                case 339: page.format = scalar(entry, true); break;
                case 32997: page.depth = scalar(entry); break;
            }
        }
        if (!page.width || !page.height || !page.rows || !page.samples) throw Invalid("Invalid TIFF dimensions.");
        if (page.compression != 1 || page.tiled || page.extra || page.depth != 1 ||
            page.predictor != 1 || page.orientation != 1 ||
            (page.samples != 1 && page.bits < 8) ||
            (page.planar != 1 && page.planar != 2) ||
            (page.fill != 1 && (page.fill != 2 || page.bits > 8)) ||
            !((page.photo <= 1 && page.samples == 1) || (page.photo == 2 && page.samples == 3))) throw Unsupported();
        classId(page);
        const U64 stripsPerPlane = 1 + (page.height - 1) / page.rows;
        const U64 planes = page.planar == 2 ? page.samples : 1;
        if (page.offsets.size() != multiply(stripsPerPlane, planes) || page.offsets.size() != page.counts.size())
            throw Invalid("TIFF strip table does not match the image dimensions.");
        const U64 rowBytes = bytesPerRow(page);
        for (U64 s = 0; s < page.offsets.size(); ++s) {
            const U64 y = (s % stripsPerPlane) * page.rows;
            const U64 needed = multiply(rowBytes, std::min(page.rows, page.height - y));
            if (page.counts[hostSize(s)] < needed) throw Invalid("TIFF strip is shorter than its pixel data.");
            file.range(page.offsets[hostSize(s)], page.counts[hostSize(s)]);
        }
        if (!pages.empty()) {
            const auto& first = pages.front();
            if (page.width != first.width || page.height != first.height || page.bits != first.bits ||
                page.format != first.format || page.samples != first.samples || page.photo != first.photo)
                throw Invalid("All TIFF pages must have the same dimensions and sample type.");
        }
        pages.push_back(std::move(page));
        return number(entries.data() + hostSize(count * entryWidth), big ? 8 : 4, little);
    }
    static U64 bytesPerRow(const Page& p) {
        return add(multiply(multiply(p.width, p.planar == 2 ? 1 : p.samples), p.bits), 7) / 8;
    }
    static mxClassID classId(const Page& p) {
        if (p.format == 1) {
            switch (p.bits) {
                case 1: return mxLOGICAL_CLASS;
                case 2: case 4: case 8: return mxUINT8_CLASS;
                case 16: return mxUINT16_CLASS;
                case 32: return mxUINT32_CLASS;
            }
        } else if (p.format == 2) {
            switch (p.bits) {
                case 8: return mxINT8_CLASS;
                case 16: return mxINT16_CLASS;
                case 32: return mxINT32_CLASS;
            }
        } else if (p.format == 3) {
            if (p.bits == 32) return mxSINGLE_CLASS;
            if (p.bits == 64) return mxDOUBLE_CLASS;
        }
        throw Unsupported();
    }
    static Byte reverseBits(Byte x) {
        x = static_cast<Byte>((x >> 4) | (x << 4));
        x = static_cast<Byte>(((x & 0xcc) >> 2) | ((x & 0x33) << 2));
        return static_cast<Byte>(((x & 0xaa) >> 1) | ((x & 0x55) << 1));
    }
    template<class T, bool Swap> void decodeAligned(mxArray* output) {
        T* target = static_cast<T*>(mxGetData(output));
        const Byte* fileBase = file.data(0, file.size);
        const std::size_t frameElements = hostSize(pages.front().width * pages.front().height * pages.front().samples);
        const auto pageCount = static_cast<std::ptrdiff_t>(pages.size());
        const bool parallel = pages.size() >= 4 && frameElements * pages.size() * sizeof(T) >= 4 * 1024 * 1024;
        (void)parallel;
#ifdef _OPENMP
#pragma omp parallel for num_threads(4) if(parallel) schedule(static)
#endif
        for (std::ptrdiff_t index = 0; index < pageCount; ++index) {
            const auto& p = pages[static_cast<std::size_t>(index)];
            T* frame = target + static_cast<std::size_t>(index) * frameElements;
            const std::size_t width = hostSize(p.width), height = hostSize(p.height);
            const std::size_t planeSize = width * height;
            const std::size_t stripsPerPlane = 1 + (height - 1) / hostSize(p.rows);
            const std::size_t channels = p.planar == 2 ? 1 : hostSize(p.samples);
            const std::size_t rowBytes = width * channels * sizeof(T);
            for (std::size_t s = 0; s < p.offsets.size(); ++s) {
                const std::size_t y0 = (s % stripsPerPlane) * hostSize(p.rows);
                const std::size_t rows = std::min(hostSize(p.rows), height - y0);
                const std::size_t firstChannel = p.planar == 2 ? s / stripsPerPlane : 0;
                const Byte* buffer = fileBase + static_cast<std::size_t>(p.offsets[s]);
                for (std::size_t c = 0; c < channels; ++c) {
                    T* plane = frame + (firstChannel + c) * planeSize + y0;
                    for (std::size_t yBlock = 0; yBlock < rows; yBlock += 32) {
                        const std::size_t endY = std::min(rows, yBlock + 32);
                        for (std::size_t x = 0; x < width; ++x) {
                            const Byte* source = buffer + yBlock * rowBytes + (x * channels + c) * sizeof(T);
                            T* destination = plane + x * height + yBlock;
                            for (std::size_t y = yBlock; y < endY; ++y) {
                                Byte sample[sizeof(T)];
                                for (std::size_t b = 0; b < sizeof(T); ++b)
                                    sample[b] = source[Swap ? sizeof(T) - 1 - b : b];
                                std::memcpy(destination++, sample, sizeof(T));
                                source += rowBytes;
                            }
                        }
                    }
                }
            }
        }
    }
    template<class T> void decode(mxArray* output) {
        if (pages.front().bits >= 8 && std::all_of(pages.begin(), pages.end(), [](const Page& p) { return p.fill == 1; })) {
            const std::uint16_t endianProbe = 1;
            if (little == (*reinterpret_cast<const Byte*>(&endianProbe) == 1)) decodeAligned<T, false>(output);
            else decodeAligned<T, true>(output);
            return;
        }
        T* target = static_cast<T*>(mxGetData(output));
        const std::uint16_t endianProbe = 1;
        const bool swap = little != (*reinterpret_cast<const Byte*>(&endianProbe) == 1);
        U64 frameBase = 0;
        for (const auto& p : pages) {
            const U64 planeSize = multiply(p.width, p.height);
            const U64 stripsPerPlane = 1 + (p.height - 1) / p.rows;
            const U64 rowBytes = bytesPerRow(p);
            const U64 chunkSamples = p.planar == 2 ? 1 : p.samples;
            for (U64 s = 0; s < p.offsets.size(); ++s) {
                const U64 y0 = (s % stripsPerPlane) * p.rows;
                const U64 rows = std::min(p.rows, p.height - y0);
                const U64 channelBase = p.planar == 2 ? s / stripsPerPlane : 0;
                const U64 length = multiply(rowBytes, rows);
                const Byte* buffer = file.data(p.offsets[hostSize(s)], length);
                // Small blocks keep the row-major source and column-major output in cache.
                for (U64 yBlock = 0; yBlock < rows; yBlock += 32) {
                    for (U64 xBlock = 0; xBlock < p.width; xBlock += 32) {
                        for (U64 c = 0; c < chunkSamples; ++c) {
                            for (U64 y = yBlock; y < std::min(rows, yBlock + 32); ++y) {
                                const Byte* row = buffer + hostSize(y * rowBytes);
                                for (U64 x = xBlock; x < std::min(p.width, xBlock + 32); ++x) {
                                    const U64 sourceIndex = x * chunkSamples + c;
                                    T value;
                                    if (p.bits < 8) {
                                        const U64 bit = sourceIndex * p.bits;
                                        Byte byte = row[hostSize(bit / 8)];
                                        if (p.fill == 2) byte = reverseBits(byte);
                                        value = static_cast<T>((byte >> (8 - p.bits - bit % 8)) & ((1u << p.bits) - 1));
                                    } else {
                                        Byte sample[sizeof(T)];
                                        const Byte* source = row + hostSize(sourceIndex * sizeof(T));
                                        for (std::size_t b = 0; b < sizeof(T); ++b) {
                                            sample[b] = source[swap ? sizeof(T) - 1 - b : b];
                                            if (p.fill == 2) sample[b] = reverseBits(sample[b]);
                                        }
                                        std::memcpy(&value, sample, sizeof(T));
                                    }
                                    target[hostSize(frameBase + (channelBase + c) * planeSize + x * p.height + y0 + y)] = value;
                                }
                            }
                        }
                    }
                }
            }
            frameBase += planeSize * p.samples;
        }
    }
public:
    explicit Reader(const mxArray* path) : file(path) {}
    mxArray* read() {
        auto header = file.read(0, 8);
        if (header[0] == 'I' && header[1] == 'I') little = true;
        else if (header[0] == 'M' && header[1] == 'M') little = false;
        else throw Invalid("File is not a TIFF file.");
        const auto version = number(header.data() + 2, 2, little);
        U64 next;
        if (version == 42) next = number(header.data() + 4, 4, little);
        else if (version == 43) {
            big = true;
            if (number(header.data() + 4, 2, little) != 8 || number(header.data() + 6, 2, little) != 0)
                throw Invalid("Invalid BigTIFF header.");
            header = file.read(8, 8);
            next = number(header.data(), 8, little);
        } else throw Invalid("Unsupported TIFF header version.");
        std::unordered_set<U64> visited;
        while (next) {
            if (!visited.insert(next).second) throw Invalid("Cyclic TIFF directory chain.");
            next = directory(next);
        }
        if (pages.empty()) throw Invalid("TIFF contains no image directories.");
        // ImageJ can store an entire stack behind a single IFD, including >4GB classic TIFFs.
        if (pages.size() == 1 && pages.front().imageJFrames > 1) throw Unsupported();
        const Page& first = pages.front();
        const U64 elements = multiply(multiply(multiply(first.width, first.height), first.samples), pages.size());
        hostSize(multiply(elements, std::max<U64>(1, first.bits / 8)));
        const mxClassID type = classId(first);
        mwSize dims[] = {hostSize(first.height), hostSize(first.width), hostSize(first.samples), pages.size()};
        if (first.samples == 1) dims[2] = pages.size();
        const mwSize dimensionCount = first.samples == 1 ? 3 : 4;
        mxArray* raw = type == mxLOGICAL_CLASS ? mxCreateLogicalArray(dimensionCount, dims) :
            mxCreateUninitNumericArray(dimensionCount, dims, type, mxREAL);
        if (!raw) throw std::bad_alloc();
        std::unique_ptr<mxArray, decltype(&mxDestroyArray)> output(raw, &mxDestroyArray);
        switch (type) {
            case mxLOGICAL_CLASS: decode<mxLogical>(raw); break;
            case mxUINT8_CLASS: decode<std::uint8_t>(raw); break;
            case mxUINT16_CLASS: decode<std::uint16_t>(raw); break;
            case mxUINT32_CLASS: decode<std::uint32_t>(raw); break;
            case mxINT8_CLASS: decode<std::int8_t>(raw); break;
            case mxINT16_CLASS: decode<std::int16_t>(raw); break;
            case mxINT32_CLASS: decode<std::int32_t>(raw); break;
            case mxSINGLE_CLASS: decode<float>(raw); break;
            case mxDOUBLE_CLASS: decode<double>(raw); break;
            default: throw Unsupported();
        }
        return output.release();
    }
};
} // namespace

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
    if (nrhs != 1 || nlhs > 1 || !mxIsChar(prhs[0]) || mxGetM(prhs[0]) != 1 || mxIsEmpty(prhs[0]))
        mexErrMsgIdAndTxt("loadtiff:NativeUsage", "Use loadtiff(filename), or pass a character row vector to loadtiff_native.");
    try {
        mxArray* result;
        try { result = Reader(prhs[0]).read(); }
        catch (const Unsupported&) { result = mxCreateDoubleMatrix(0, 0, mxREAL); }
        if (nlhs) plhs[0] = result;
        else mxDestroyArray(result);
    } catch (const std::bad_alloc&) {
        mexErrMsgIdAndTxt("loadtiff:OutOfMemory", "Not enough memory to read this TIFF stack.");
    } catch (const std::exception& error) {
        mexErrMsgIdAndTxt("loadtiff:InvalidTiff", "%s", error.what());
    }
}
