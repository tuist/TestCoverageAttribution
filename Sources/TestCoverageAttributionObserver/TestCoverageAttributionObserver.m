// Per-test coverage attribution for Xcode test runs.
//
// Linked into a test target, this library records which coverage counters each test moves, and
// by how much, while the tests run. It never calls the LLVM profile runtime, whose symbols are
// hidden per image: it finds the `__llvm_prf_cnts` section of every instrumented image, copies
// it when a scope starts, and when the scope ends records the counters that changed. Counters
// are never zeroed, so Xcode's own coverage report is untouched.
//
// Nothing happens unless $TEST_COVERAGE_ATTRIBUTION_DIR names where to write (through xcodebuild,
// TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR), so a test target can link it unconditionally.
//
// Scopes:
//   - an XCTest test, from XCTestObservation, registered when the test bundle loads;
//   - a Swift Testing test, from the `.coverageAttribution` trait, which calls
//     test_coverage_attribution_scope_begin/end around the test body (Swift Testing has no
//     observation center a library can join);
//   - a gap: whatever ran between two scopes (class setUp, a suite's one-time bootstrap,
//     leaked background work), recorded with the scope that follows or the suite that closed.
//
// Output, under $TEST_COVERAGE_ATTRIBUTION_DIR/<pid>/:
//   images.tsv     image index, counters byte size, __llvm_prf_data address, __llvm_prf_cnts
//                  address, path
//   <n>.data       the image's raw __llvm_prf_data section
//   <n>.names      the image's raw __llvm_prf_names section
//   records.bin    one record per scope, see write_record()
#import <Foundation/Foundation.h>
#import "TestCoverageAttributionObserver.h"
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

enum { kRecordGap = 0, kRecordXCTest = 1, kRecordSwiftTesting = 2 };
enum { kFlagOverlapped = 1 };
// 1: each image's counter indices are followed by how much each counter moved.
enum { kRecordVersion = 1 };

typedef struct {
    uint64_t *counters;
    uint64_t *snapshot;
    unsigned long counters_size;
} instrumented_image;

static instrumented_image *images;
static unsigned images_count;
static bool images_discovered;
static char out_dir[PATH_MAX];
static FILE *records;
static uint32_t *scratch;
static uint64_t *scratch_deltas;
static size_t scratch_len;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned active_scopes;
static bool scopes_overlapped;
static char bundle_name[NAME_MAX];

static const uint8_t *section(const struct mach_header_64 *h, const char *name, unsigned long *size) {
    const uint8_t *p = getsectiondata(h, "__DATA", name, size);
    if (!p) p = getsectiondata(h, "__DATA_CONST", name, size);
    if (!p) p = getsectiondata(h, "__DATA_DIRTY", name, size);
    return p;
}

// Recording stops at the first thing that fails, and what was written for the process is removed:
// a reader then finds no output for it, rather than records whose counters it can't map, which
// would read as tests that ran nothing. The tests run on as if nothing were linked.
static void stop_recording(void) {
    if (!records) return;
    fclose(records);
    records = NULL;
    char file[PATH_MAX];
    snprintf(file, sizeof file, "%s/images.tsv", out_dir);
    unlink(file);
    snprintf(file, sizeof file, "%s/records.bin", out_dir);
    unlink(file);
}

// Whether the section is written in full; an image without it has nothing to write.
static bool dump_section(const struct mach_header_64 *h, const char *name, unsigned index, const char *extension) {
    unsigned long size = 0;
    const uint8_t *p = section(h, name, &size);
    if (!p) return true;
    char file[PATH_MAX];
    snprintf(file, sizeof file, "%s/%u.%s", out_dir, index, extension);
    FILE *f = fopen(file, "wb");
    if (!f) return false;
    bool written = fwrite(p, 1, size, f) == size;
    return fclose(f) == 0 && written;
}

// Images loaded after the first scope (a framework the tests dlopen late) are not picked up;
// their code is then missing from the evidence, which the per-target floor covers.
static void discover_images(void) {
    if (images_discovered) return;
    images_discovered = true;
    unsigned n = _dyld_image_count();
    images = calloc(n ? n : 1, sizeof(instrumented_image));
    char file[PATH_MAX];
    snprintf(file, sizeof file, "%s/images.tsv", out_dir);
    FILE *f = images ? fopen(file, "w") : NULL;
    bool ok = f != NULL;
    for (unsigned i = 0; ok && i < n; i++) {
        const struct mach_header_64 *h = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!h || h->magic != MH_MAGIC_64) continue;
        unsigned long size = 0;
        uint8_t *cnts = (uint8_t *)section(h, "__llvm_prf_cnts", &size);
        if (!cnts || size == 0) continue;
        unsigned long data_size = 0;
        const uint8_t *data = section(h, "__llvm_prf_data", &data_size);
        if (!data) continue;
        instrumented_image *img = &images[images_count];
        img->counters = (uint64_t *)cnts;
        img->snapshot = malloc(size);
        img->counters_size = size;
        ok = img->snapshot
            && fprintf(f, "%u\t%lu\t%llu\t%llu\t%s\n", images_count, size, (unsigned long long)(uintptr_t)data,
                       (unsigned long long)(uintptr_t)cnts, _dyld_get_image_name(i)) >= 0
            && dump_section(h, "__llvm_prf_data", images_count, "data")
            && dump_section(h, "__llvm_prf_names", images_count, "names");
        if (!ok) break;
        size_t words = size / sizeof(uint64_t);
        if (words > scratch_len) scratch_len = words;
        images_count++;
    }
    if (f && fclose(f) != 0) ok = false;
    if (ok) {
        scratch = malloc((scratch_len ? scratch_len : 1) * sizeof(uint32_t));
        scratch_deltas = malloc((scratch_len ? scratch_len : 1) * sizeof(uint64_t));
        ok = scratch && scratch_deltas;
    }
    if (!ok) stop_recording();
}

static void take_snapshot(void) {
    for (unsigned i = 0; i < images_count; i++) {
        memcpy(images[i].snapshot, images[i].counters, images[i].counters_size);
    }
}

static void write_string(const char *s) {
    uint32_t len = s ? (uint32_t)strlen(s) : 0;
    fwrite(&len, sizeof len, 1, records);
    if (len) fwrite(s, 1, len, records);
}

// Record: u8 kind, u8 flags, u8 version, u8 zero, then the length-prefixed (u32) module, suite
// and name, then u32 image count and per image u32 index, u32 count, count u32 counter indices
// (the 8-byte counters that changed since the snapshot) and count u64 deltas (by how much).
// The deltas are what tells which lines ran: a region's count is an expression over counters.
// Images nothing touched are left out, and so is a gap in which nothing ran.
static bool counters_changed(void) {
    for (unsigned i = 0; i < images_count; i++) {
        if (memcmp(images[i].counters, images[i].snapshot, images[i].counters_size) != 0) return true;
    }
    return false;
}

static void write_record(uint8_t kind, uint8_t flags, const char *module, const char *suite, const char *name) {
    if (!records || !scratch || !scratch_deltas) return;
    if (kind == kRecordGap && !counters_changed()) return;
    uint8_t header[4] = {kind, flags, kRecordVersion, 0};
    fwrite(header, 1, sizeof header, records);
    write_string(module);
    write_string(suite);
    write_string(name);
    long count_position = ftell(records);
    if (count_position < 0) {
        stop_recording();
        return;
    }
    uint32_t touched_images = 0;
    fwrite(&touched_images, sizeof touched_images, 1, records);
    for (unsigned i = 0; i < images_count; i++) {
        size_t words = images[i].counters_size / sizeof(uint64_t);
        const uint64_t *c = images[i].counters;
        const uint64_t *s = images[i].snapshot;
        uint32_t count = 0;
        for (size_t w = 0; w < words; w++) {
            if (c[w] != s[w]) {
                scratch[count] = (uint32_t)w;
                scratch_deltas[count++] = c[w] - s[w];
            }
        }
        if (count == 0) continue;
        uint32_t index = i;
        fwrite(&index, sizeof index, 1, records);
        fwrite(&count, sizeof count, 1, records);
        fwrite(scratch, sizeof(uint32_t), count, records);
        fwrite(scratch_deltas, sizeof(uint64_t), count, records);
        touched_images++;
    }
    if (touched_images) {
        long end = ftell(records);
        if (end < 0 || fseek(records, count_position, SEEK_SET) != 0
            || fwrite(&touched_images, sizeof touched_images, 1, records) != 1 || fseek(records, end, SEEK_SET) != 0) {
            stop_recording();
            return;
        }
    }
    // The stream's error flag sticks, so it also reports any write above that failed.
    if (fflush(records) != 0 || ferror(records)) stop_recording();
}

// Swift Testing runs tests concurrently unless the scheme or the suite serializes them. Scopes
// that run at the same time share one snapshot, so each holds the others' work and misses its
// own from before the last one ended: once a scope starts while another is active, every scope
// that ends until none is active is marked overlapped, and whoever reads the records leaves it
// out of per-test evidence.
static void scope_begin(const char *module, const char *suite, const char *name) {
    pthread_mutex_lock(&lock);
    if (records) {
        discover_images();
        if (active_scopes == 0) {
            write_record(kRecordGap, 0, module, suite, "");
            take_snapshot();
        } else {
            scopes_overlapped = true;
        }
        active_scopes++;
    }
    pthread_mutex_unlock(&lock);
}

static void scope_end(const char *module, const char *suite, const char *name) {
    pthread_mutex_lock(&lock);
    if (records && active_scopes > 0) {
        write_record(kRecordSwiftTesting, scopes_overlapped ? kFlagOverlapped : 0, module, suite, name);
        active_scopes--;
        if (active_scopes == 0) scopes_overlapped = false;
        take_snapshot();
    }
    pthread_mutex_unlock(&lock);
}

// A process records through one copy of the library, the first to load: a second copy (another
// test bundle, or a framework that links it too) would observe the same tests twice. The owner
// publishes its scope functions in the environment, keyed by the process, and the other copies
// forward to them, so the trait works from whichever copy it was linked with.
typedef struct {
    void (*begin)(const char *, const char *, const char *);
    void (*end)(const char *, const char *, const char *);
} scope_functions;

static const scope_functions own_functions = {scope_begin, scope_end};
static const char *const kOwnerVariable = "TEST_COVERAGE_ATTRIBUTION_OWNER";

static const scope_functions *process_owner(void) {
    const char *value = getenv(kOwnerVariable);
    if (!value) return NULL;
    long long pid = 0;
    unsigned long long address = 0;
    if (sscanf(value, "%lld:%llx", &pid, &address) != 2 || pid != getpid()) return NULL;
    return (const scope_functions *)(uintptr_t)address;
}

static const scope_functions *owner(void) {
    if (records) return &own_functions;
    return process_owner();
}

void test_coverage_attribution_scope_begin(const char *module, const char *suite, const char *name) {
    const scope_functions *functions = owner();
    if (functions) functions->begin(module, suite, name);
}

void test_coverage_attribution_scope_end(const char *module, const char *suite, const char *name) {
    const scope_functions *functions = owner();
    if (functions) functions->end(module, suite, name);
}

// XCTest's names: `-[Suite test]` for Objective-C, `-[Module.Suite test]` for Swift; the
// selector of a throwing or asynchronous Swift test ends in `AndReturnError:` or
// `WithCompletionHandler:`. The reader normalizes the selector; this only splits.
static void split_xctest_name(NSString *name, NSString **suite, NSString **method) {
    *suite = @"";
    *method = name ?: @"";
    if (![name hasPrefix:@"-["] || ![name hasSuffix:@"]"]) return;
    NSString *inner = [name substringWithRange:NSMakeRange(2, name.length - 3)];
    NSRange space = [inner rangeOfString:@" "];
    if (space.location == NSNotFound) return;
    NSString *class_name = [inner substringToIndex:space.location];
    NSRange dot = [class_name rangeOfString:@"." options:NSBackwardsSearch];
    *suite = dot.location == NSNotFound ? class_name : [class_name substringFromIndex:dot.location + 1];
    *method = [inner substringFromIndex:space.location + 1];
}

@interface TestCoverageAttributionObserver : NSObject
@end

@implementation TestCoverageAttributionObserver

- (void)testBundleWillStart:(NSBundle *)testBundle {
    pthread_mutex_lock(&lock);
    NSString *name = testBundle.bundleURL.lastPathComponent.stringByDeletingPathExtension ?: @"";
    strlcpy(bundle_name, name.UTF8String, sizeof bundle_name);
    discover_images();
    take_snapshot();
    pthread_mutex_unlock(&lock);
}

- (void)testSuiteWillStart:(id)testSuite {
    [self gapForSuite:nil];
}

- (void)testCaseWillStart:(id)testCase {
    NSString *suite, *method;
    split_xctest_name([testCase name], &suite, &method);
    [self gapForSuite:suite];
}

- (void)testCaseDidFinish:(id)testCase {
    NSString *suite, *method;
    split_xctest_name([testCase name], &suite, &method);
    pthread_mutex_lock(&lock);
    write_record(kRecordXCTest, 0, bundle_name, suite.UTF8String, method.UTF8String);
    take_snapshot();
    pthread_mutex_unlock(&lock);
}

- (void)testSuiteDidFinish:(id)testSuite {
    NSString *name = [testSuite name];
    [self gapForSuite:[name hasSuffix:@".xctest"] || [name isEqualToString:@"All tests"] || [name isEqualToString:@"Selected tests"] ? nil : name];
}

- (void)testBundleDidFinish:(NSBundle *)testBundle {
    [self gapForSuite:nil];
}

- (void)gapForSuite:(NSString *)suite {
    pthread_mutex_lock(&lock);
    write_record(kRecordGap, 0, bundle_name, suite.UTF8String ?: "", "");
    take_snapshot();
    pthread_mutex_unlock(&lock);
}

@end

static TestCoverageAttributionObserver *observer;

// XCTest is looked up at run time so the library links against nothing a process may lack; the
// protocol conformance the center insists on is added the same way. A process without XCTest,
// or an XCTest that refuses the observer, runs its tests as if nothing were linked.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
static void register_observer(void) {
    Class center = NSClassFromString(@"XCTestObservationCenter");
    Protocol *observation = NSProtocolFromString(@"XCTestObservation");
    if (!center || !observation) return;
    class_addProtocol([TestCoverageAttributionObserver class], observation);
    @try {
        observer = [TestCoverageAttributionObserver new];
        id shared = [center performSelector:NSSelectorFromString(@"sharedTestObservationCenter")];
        [shared performSelector:NSSelectorFromString(@"addTestObserver:") withObject:observer];
    } @catch (NSException *exception) {
        observer = nil;
    }
}
#pragma clang diagnostic pop

__attribute__((constructor)) static void test_coverage_attribution_init(void) {
    const char *dir = getenv("TEST_COVERAGE_ATTRIBUTION_DIR");
    if (!dir || !*dir || process_owner()) return;
    mkdir(dir, 0755);
    snprintf(out_dir, sizeof out_dir, "%s/%d", dir, getpid());
    mkdir(out_dir, 0755);
    char file[PATH_MAX];
    snprintf(file, sizeof file, "%s/records.bin", out_dir);
    records = fopen(file, "wb");
    if (!records) return;
    char value[64];
    snprintf(value, sizeof value, "%d:%llx", getpid(), (unsigned long long)(uintptr_t)&own_functions);
    setenv(kOwnerVariable, value, 1);
    // A test bundle loads after XCTest, so the observer joins before the bundle's first test,
    // as a bundle's principal class would. In a process that loads XCTest later, the main queue
    // runs once it is up.
    if (NSClassFromString(@"XCTestObservationCenter")) {
        register_observer();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            register_observer();
        });
    }
}
