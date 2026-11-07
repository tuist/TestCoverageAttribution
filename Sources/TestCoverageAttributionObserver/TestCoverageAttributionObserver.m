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
//   launches.tsv   one line per process a UI test launched, see record_launch()
//   functions.tsv  one line per image built with function-entry tracking, see list_function_images()
//   functions.bin  one record per Swift Testing test case and for the floor, see write_functions_record()
//
// Swift Testing runs a process's tests in parallel, which the process-wide counters can't tell
// apart. Code compiled with `-sanitize-coverage=func,trace-pc-guard,pc-table` calls back on every
// function entry, and the callback attributes the function to the test whose task is running, read
// from the trait's TaskLocal: async hops, child tasks and `Task {}` keep it. See "Functions per task".
//
// Skipping: $TEST_COVERAGE_ATTRIBUTION_SKIP_FILE (through xcodebuild,
// TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE), an absolute path, names a file of XCTest tests
// not to run, which are removed before XCTest runs them. See load_skip_list(). It works with or
// without recording.
#import <Foundation/Foundation.h>
#import "TestCoverageAttributionObserver.h"
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

enum { kRecordGap = 0, kRecordXCTest = 1, kRecordSwiftTesting = 2, kRecordFunctions = 3 };
enum { kFlagOverlapped = 1, kFlagFloor = 2 };
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
static uint8_t *record_buffer;
static size_t record_capacity;
static size_t record_length;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned active_scopes;
static bool scopes_overlapped;
static char bundle_name[NAME_MAX];
static FILE *launches;
static bool launches_failed;
static NSString *current_suite;
static NSString *current_test;
static NSMutableSet<NSNumber *> *listed_launches;

static const uint8_t *section(const struct mach_header_64 *h, const char *name, unsigned long *size) {
    const uint8_t *p = getsectiondata(h, "__DATA", name, size);
    if (!p) p = getsectiondata(h, "__DATA_CONST", name, size);
    if (!p) p = getsectiondata(h, "__DATA_DIRTY", name, size);
    return p;
}

// Recording stops at the first thing that fails, and what was written for the process is removed:
// a reader then finds no output for it, rather than records whose counters it can't map, which
// would read as tests that ran nothing. The tests run on as if nothing were linked.
static FILE *function_list;
static FILE *function_records;

static void stop_recording(void) {
    if (!records) return;
    fclose(records);
    records = NULL;
    if (function_list) fclose(function_list);
    if (function_records) fclose(function_records);
    function_list = function_records = NULL;
    char file[PATH_MAX];
    for (const char **name = (const char *[]){"images.tsv", "records.bin", "functions.tsv", "functions.bin", NULL}; *name; name++) {
        snprintf(file, sizeof file, "%s/%s", out_dir, *name);
        unlink(file);
    }
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

// A record is built in memory and appended in one write, so whatever reaches the file is a prefix
// of the finished record. A reader stops at a cut-off one; a record whose image count were written
// before its images would read as a test that ran nothing.
// The buffer is kept between records and starts small, so the tests' records exercise its growth.
static bool append(const void *bytes, size_t size) {
    if (size == 0) return true;
    if (record_length + size > record_capacity) {
        size_t capacity = record_capacity ? record_capacity : 64;
        while (capacity < record_length + size) capacity *= 2;
        uint8_t *grown = realloc(record_buffer, capacity);
        if (!grown) return false;
        record_buffer = grown;
        record_capacity = capacity;
    }
    memcpy(record_buffer + record_length, bytes, size);
    record_length += size;
    return true;
}

static bool append_string(const char *s) {
    uint32_t len = s ? (uint32_t)strlen(s) : 0;
    return append(&len, sizeof len) && append(s, len);
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
    uint32_t touched_images = 0;
    record_length = 0;
    bool ok = append(header, sizeof header) && append_string(module) && append_string(suite) && append_string(name);
    size_t count_offset = record_length;
    ok = ok && append(&touched_images, sizeof touched_images);
    for (unsigned i = 0; ok && i < images_count; i++) {
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
        ok = append(&index, sizeof index) && append(&count, sizeof count)
            && append(scratch, count * sizeof(uint32_t)) && append(scratch_deltas, count * sizeof(uint64_t));
        touched_images++;
    }
    if (ok) {
        memcpy(record_buffer + count_offset, &touched_images, sizeof touched_images);
        ok = fwrite(record_buffer, 1, record_length, records) == record_length && fflush(records) == 0;
    }
    if (!ok) stop_recording();
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

// MARK: Functions per task
//
// SanitizerCoverage numbers a guard per function of every image compiled with
// `func,trace-pc-guard,pc-table` and calls the guard callback on each entry. The callbacks
// SanitizerCoverage names are defined in the TestCoverageAttribution module, which every test target
// links directly, and forward here (see SanitizerCoverage.swift). The callback reads the
// running task's context, the TaskLocal the trait binds around each Swift Testing test case, and
// sets the function's bit in that context's set. A test's child tasks, its `Task {}`s and the actors
// it awaits run under its task's TaskLocals, so their functions count for it however many tests run
// at once. When a context ends, its functions are written as one record.
//
// What no test's task runs, work on a GCD queue or a thread, a `Task.detached`, a suite's setup
// outside any test, goes to the floor, context 0, written whenever no context is open: any test of
// the process may depend on it. Nothing is tracked before the first context opens or while an
// XCTest test runs, whose counters say what it ran.
//
// The task and its TaskLocal are read through the Swift concurrency runtime, looked up at run time
// so this library links no Swift. No cache: a task's address is reused once it ends.

typedef void *(*current_task_function)(void) __attribute__((swiftcall));
typedef void *(*task_local_value_function)(const void *key) __attribute__((swiftcall));

typedef struct {
    uint32_t first_guard;
    uint32_t guard_count;
    uintptr_t base;
    const uintptr_t *pcs;
    char *path;
} function_image;

enum { kMaxFunctionImages = 4096, kMaxContexts = 1 << 20, kNoContext = UINT32_MAX };

static function_image function_images[kMaxFunctionImages];
static unsigned function_images_count;
static unsigned function_images_listed;
static uint32_t guards_numbered;
static pthread_mutex_t guards_lock = PTHREAD_MUTEX_INITIALIZER;
// Guards above this aren't tracked: zero until the first context opens, so the callback costs one
// comparison until then; guards numbered later (an image loaded late) are left out.
static _Atomic uint32_t tracked_guards;
static size_t bitset_words;
static _Atomic(uint64_t *) *context_bits;
static char **context_names;
static uint32_t *late_contexts;
static size_t late_count;
static size_t late_capacity;
static uint64_t *floor_written;
static uint32_t next_context = 1;
static unsigned open_contexts;
static const void *_Atomic context_key;
static current_task_function get_current_task;
static task_local_value_function task_local_value;
static atomic_bool xctest_running;
// A context whose test ended: a hit after that (a task the test left running) reopens it.
static uint64_t *const closed_context = (uint64_t *)1;

static uint64_t *new_bitset(void) {
    return calloc(bitset_words, sizeof(uint64_t));
}

static void own_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
    if (start == stop || *start) return;
    pthread_mutex_lock(&guards_lock);
    uint32_t first = guards_numbered + 1;
    for (uint32_t *guard = start; guard < stop; guard++) *guard = ++guards_numbered;
    Dl_info info;
    if (function_images_count < kMaxFunctionImages && dladdr(start, &info) && info.dli_fbase) {
        function_images[function_images_count++] = (function_image){
            first, (uint32_t)(stop - start), (uintptr_t)info.dli_fbase, NULL, strdup(info.dli_fname ?: ""),
        };
    }
    pthread_mutex_unlock(&guards_lock);
}

// The PC table holds a (PC, flags) pair per guard, in guard order, for the image whose guards
// were numbered last with as many guards.
static void own_pcs_init(const uintptr_t *start, const uintptr_t *end) {
    uint32_t count = (uint32_t)((end - start) / 2);
    Dl_info info;
    if (!dladdr(start, &info)) return;
    pthread_mutex_lock(&guards_lock);
    for (unsigned i = function_images_count; i > 0; i--) {
        function_image *image = &function_images[i - 1];
        if (!image->pcs && image->guard_count == count && image->base == (uintptr_t)info.dli_fbase) {
            image->pcs = start;
            break;
        }
    }
    pthread_mutex_unlock(&guards_lock);
}

static uint32_t current_context(void) {
    if (atomic_load_explicit(&xctest_running, memory_order_relaxed)) return kNoContext;
    void *task = get_current_task ? get_current_task() : NULL;
    const void *key = atomic_load_explicit(&context_key, memory_order_relaxed);
    if (task && key) {
        const uint32_t *value = task_local_value(key);
        if (value && *value) return *value;
    }
    return 0;
}

static uint64_t *reopen_context(uint32_t context);

static void own_trace_pc_guard(uint32_t *guard) {
    uint32_t number = *guard;
    if (number == 0 || number > atomic_load_explicit(&tracked_guards, memory_order_relaxed)) return;
    uint32_t context = current_context();
    if (context >= kMaxContexts) return;
    uint64_t *bits = atomic_load_explicit(&context_bits[context], memory_order_acquire);
    if (!bits || bits == closed_context) bits = reopen_context(context);
    if (!bits) return;
    uint64_t mask = 1ull << (number & 63);
    _Atomic uint64_t *word = (_Atomic uint64_t *)&bits[number >> 6];
    if (!(atomic_load_explicit(word, memory_order_relaxed) & mask)) atomic_fetch_or_explicit(word, mask, memory_order_relaxed);
}

// The floor's set, made when it's first hit, and a finished context's, made again for a hit that
// arrives after its record was written. Both are written the next time no context is open.
static uint64_t *reopen_context(uint32_t context) {
    pthread_mutex_lock(&lock);
    uint64_t *bits = atomic_load(&context_bits[context]);
    if (!bits || bits == closed_context) {
        bool late = bits == closed_context;
        bits = new_bitset();
        if (bits && late) {
            if (late_count == late_capacity) {
                size_t capacity = late_capacity ? late_capacity * 2 : 16;
                uint32_t *grown = realloc(late_contexts, capacity * sizeof(uint32_t));
                if (!grown) {
                    free(bits);
                    pthread_mutex_unlock(&lock);
                    return NULL;
                }
                late_contexts = grown;
                late_capacity = capacity;
            }
            late_contexts[late_count++] = context;
        }
        if (bits) atomic_store_explicit(&context_bits[context], bits, memory_order_release);
    }
    pthread_mutex_unlock(&lock);
    return bits;
}

// functions.tsv: `index\tguards\tpath`, one line per image with function-entry tracking, written
// before the first record that names it. Function records go to a file of their own, functions.bin,
// so a reader of records.bin that predates them never meets one.
static bool list_function_images(void) {
    char file[PATH_MAX];
    if (!function_records) {
        snprintf(file, sizeof file, "%s/functions.bin", out_dir);
        function_records = fopen(file, "wb");
        if (!function_records) return false;
    }
    if (function_images_listed == function_images_count) return true;
    if (!function_list) {
        snprintf(file, sizeof file, "%s/functions.tsv", out_dir);
        function_list = fopen(file, "w");
        if (!function_list) return false;
    }
    bool ok = true;
    for (; ok && function_images_listed < function_images_count; function_images_listed++) {
        function_image *image = &function_images[function_images_listed];
        ok = fprintf(function_list, "%u\t%u\t%s\n", function_images_listed, image->guard_count, image->path) >= 0;
    }
    return ok && fflush(function_list) == 0;
}

// functions.bin record: the header and names as write_record()'s, kind 3, then u32 image count and per image the
// u32 index functions.tsv gives it, u32 count and count u32 offsets from the image's base, each the
// address the PC table gives the function a test entered. `written`, when given, limits it to the
// bits not written before and marks them written. Called with the lock held.
static void write_functions_record(uint8_t flags, const char *module, const char *suite, const char *name, const uint64_t *bits,
                                   uint64_t *written) {
    if (!records) return;
    record_length = 0;
    uint8_t header[4] = {kRecordFunctions, flags, kRecordVersion, 0};
    uint32_t touched_images = 0;
    bool ok = list_function_images() && append(header, sizeof header) && append_string(module) && append_string(suite)
        && append_string(name);
    size_t count_offset = record_length;
    ok = ok && append(&touched_images, sizeof touched_images);
    uint32_t tracked = atomic_load(&tracked_guards);
    for (unsigned i = 0; ok && i < function_images_count; i++) {
        function_image *image = &function_images[i];
        if (!image->pcs) continue;
        size_t index_offset = record_length;
        uint32_t index = i, count = 0;
        ok = append(&index, sizeof index) && append(&count, sizeof count);
        for (uint32_t g = 0; ok && g < image->guard_count; g++) {
            uint32_t number = image->first_guard + g;
            if (number > tracked) break;
            uint64_t mask = 1ull << (number & 63);
            uint64_t word = atomic_load_explicit((_Atomic uint64_t *)&bits[number >> 6], memory_order_relaxed);
            if (!(word & mask) || (written && (written[number >> 6] & mask))) continue;
            if (written) written[number >> 6] |= mask;
            uint32_t offset = (uint32_t)(image->pcs[2 * g] - image->base);
            ok = append(&offset, sizeof offset);
            count++;
        }
        if (!ok) break;
        if (count == 0) {
            record_length = index_offset;
        } else {
            memcpy(record_buffer + index_offset + sizeof index, &count, sizeof count);
            touched_images++;
        }
    }
    if (ok && touched_images == 0 && (flags & kFlagFloor)) return;
    if (ok) {
        memcpy(record_buffer + count_offset, &touched_images, sizeof touched_images);
        ok = fwrite(record_buffer, 1, record_length, function_records) == record_length && fflush(function_records) == 0;
    }
    if (!ok) stop_recording();
}

// Names a context's record: module, suite and name, as the trait passes them for its scope.
static char *context_name(const char *module, const char *suite, const char *name) {
    size_t size = strlen(module) + strlen(suite) + strlen(name) + 3;
    char *joined = malloc(size);
    if (joined) snprintf(joined, size, "%s%c%s%c%s", module, 0, suite, 0, name);
    return joined;
}

static void write_context(uint32_t context, const uint64_t *bits) {
    const char *module = context_names[context];
    if (!module) return;
    const char *suite = module + strlen(module) + 1;
    const char *name = suite + strlen(suite) + 1;
    write_functions_record(0, module, suite, name, bits, NULL);
}

// Called with the lock held, when no context is open: what the floor gained since it was last
// written, and the functions finished tests' tasks entered after their records.
static void write_floor_and_late_contexts(void) {
    uint64_t *floor_bits = atomic_load(&context_bits[0]);
    if (floor_bits) {
        if (!floor_written) floor_written = new_bitset();
        if (floor_written) write_functions_record(kFlagFloor, "", "", "", floor_bits, floor_written);
    }
    for (size_t i = 0; i < late_count; i++) {
        uint32_t context = late_contexts[i];
        uint64_t *bits = atomic_exchange(&context_bits[context], closed_context);
        if (bits && bits != closed_context) {
            write_context(context, bits);
            free(bits);
        }
    }
    late_count = 0;
}

static uint32_t own_context_begin(const char *module, const char *suite, const char *name, const void *key) {
    pthread_mutex_lock(&lock);
    uint32_t context = 0;
    if (records && guards_numbered > 0 && next_context < kMaxContexts) {
        if (!context_bits) {
            get_current_task = (current_task_function)dlsym(RTLD_DEFAULT, "swift_task_getCurrent");
            task_local_value = (task_local_value_function)dlsym(RTLD_DEFAULT, "swift_task_localValueGet");
            bitset_words = guards_numbered / 64 + 1;
            context_bits = calloc(kMaxContexts, sizeof *context_bits);
            context_names = calloc(kMaxContexts, sizeof *context_names);
            if (!context_bits || !context_names || !get_current_task || !task_local_value) {
                free(context_bits);
                free(context_names);
                context_bits = NULL;
                context_names = NULL;
                pthread_mutex_unlock(&lock);
                return 0;
            }
            atomic_store(&context_key, key);
            atomic_store(&tracked_guards, guards_numbered);
        }
        uint64_t *bits = new_bitset();
        if (bits) {
            context = next_context++;
            context_names[context] = context_name(module, suite, name);
            atomic_store_explicit(&context_bits[context], bits, memory_order_release);
            open_contexts++;
        }
    }
    pthread_mutex_unlock(&lock);
    return context;
}

static void own_context_end(uint32_t context) {
    if (context == 0 || context >= kMaxContexts || !context_bits) return;
    pthread_mutex_lock(&lock);
    uint64_t *bits = atomic_exchange(&context_bits[context], closed_context);
    if (bits && bits != closed_context) {
        write_context(context, bits);
        free(bits);
    }
    if (open_contexts > 0 && --open_contexts == 0) write_floor_and_late_contexts();
    pthread_mutex_unlock(&lock);
}

// UI tests: the app a test drives runs in a process of its own, which the observer can't see.
// Xcode profiles that process on its own (`<uuid>-<pid>.profraw` beside the run's merged profile),
// so recording which test launched which process is enough for a reader to attribute it. Each
// time -[XCUIApplication launch] or -activate returns, the app's pid is appended to launches.tsv
// as `pid\tmodule\tsuite\tname`: the running test, or an empty name for a launch outside one, such
// as a class setUp. A pid is written once, with the scope that launched it: activating a running app
// returns its pid again, and the process's single profile can't be split between the scopes that
// later activate it. The pid comes from the private `processID` property; without it nothing is
// written.
static void write_launch(pid_t pid) {
    if (launches_failed || !out_dir[0]) return;
    if (!launches) {
        char file[PATH_MAX];
        snprintf(file, sizeof file, "%s/launches.tsv", out_dir);
        launches = fopen(file, "a");
        if (!launches) {
            launches_failed = true;
            return;
        }
    }
    const char *suite = current_suite.UTF8String ?: "";
    const char *name = current_test.UTF8String ?: "";
    if (fprintf(launches, "%d\t%s\t%s\t%s\n", pid, bundle_name, suite, name) < 0 || fflush(launches) != 0) {
        fclose(launches);
        launches = NULL;
        launches_failed = true;
    }
}

static void record_launch(id application) {
    pid_t pid = 0;
    @try {
        pid = [[application valueForKey:@"processID"] intValue];
    } @catch (NSException *exception) {
        return;
    }
    if (pid <= 0) return;
    pthread_mutex_lock(&lock);
    if (!listed_launches) listed_launches = [NSMutableSet set];
    if (![listed_launches containsObject:@(pid)]) {
        [listed_launches addObject:@(pid)];
        write_launch(pid);
    }
    pthread_mutex_unlock(&lock);
}

static IMP original_launch;
static IMP original_activate;

static void launch_hook(id self, SEL _cmd) {
    ((void (*)(id, SEL))original_launch)(self, _cmd);
    record_launch(self);
}

static void activate_hook(id self, SEL _cmd) {
    ((void (*)(id, SEL))original_activate)(self, _cmd);
    record_launch(self);
}

// The original is kept before the hook is installed, so a call racing the installation still has
// one to forward to. A method the class inherits gets an override that forwards to the inherited one.
static void hook(Class cls, NSString *selector_name, IMP replacement, IMP *original) {
    SEL selector = NSSelectorFromString(selector_name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(method, replacement);
    }
}

static void observe_launches(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class application = NSClassFromString(@"XCUIApplication");
        if (!application) return;
        hook(application, @"launch", (IMP)launch_hook, &original_launch);
        hook(application, @"activate", (IMP)activate_hook, &original_activate);
    });
}

// A process records through one copy of the library: a second copy (another test bundle, or a
// framework that links it too) would observe the same tests twice, and number the guards of the
// images linked against it on its own. The owner is the first copy that needs one, from its
// constructor or from a guard init that runs before any constructor. It publishes its functions in
// the environment, keyed by the process, and the other copies forward to them, so the trait and
// the guard callbacks work from whichever copy an image was linked with.
//
// `size` is the table's size in the copy that published it, so a copy reads only the functions the
// owner has. Copies before function tracking publish a table of scope functions only, under
// kLegacyOwnerVariable; a copy that finds one forwards its scopes there and tracks no functions.
typedef struct {
    void (*begin)(const char *, const char *, const char *);
    void (*end)(const char *, const char *, const char *);
} scope_functions;

typedef struct {
    size_t size;
    void (*scope_begin)(const char *, const char *, const char *);
    void (*scope_end)(const char *, const char *, const char *);
    void (*trace_pc_guard_init)(uint32_t *, uint32_t *);
    void (*pcs_init)(const uintptr_t *, const uintptr_t *);
    void (*trace_pc_guard)(uint32_t *);
    uint32_t (*context_begin)(const char *, const char *, const char *, const void *);
    void (*context_end)(uint32_t);
} owner_functions;

static const scope_functions own_scope_functions = {scope_begin, scope_end};
static const owner_functions own_functions = {
    sizeof(owner_functions), scope_begin, scope_end, own_trace_pc_guard_init, own_pcs_init, own_trace_pc_guard,
    own_context_begin, own_context_end,
};
static const char *const kLegacyOwnerVariable = "TEST_COVERAGE_ATTRIBUTION_OWNER";
static const char *const kOwnerVariable = "TEST_COVERAGE_ATTRIBUTION_OWNER_2";
static const owner_functions *_Atomic resolved_owner;
static const scope_functions *legacy_owner;
static pthread_mutex_t owner_lock = PTHREAD_MUTEX_INITIALIZER;

static const void *published(const char *variable) {
    const char *value = getenv(variable);
    if (!value) return NULL;
    long long pid = 0;
    unsigned long long address = 0;
    if (sscanf(value, "%lld:%llx", &pid, &address) != 2 || pid != getpid()) return NULL;
    return (const void *)(uintptr_t)address;
}

static void publish(const char *variable, const void *table) {
    char value[64];
    snprintf(value, sizeof value, "%d:%llx", getpid(), (unsigned long long)(uintptr_t)table);
    setenv(variable, value, 1);
}

static const owner_functions *process_owner(void) {
    const owner_functions *functions = atomic_load(&resolved_owner);
    if (functions) return functions;
    pthread_mutex_lock(&owner_lock);
    functions = atomic_load(&resolved_owner);
    if (!functions) {
        functions = published(kOwnerVariable);
        if (!functions) {
            legacy_owner = published(kLegacyOwnerVariable);
            if (!legacy_owner) publish(kLegacyOwnerVariable, &own_scope_functions);
            publish(kOwnerVariable, &own_functions);
            functions = &own_functions;
        }
        atomic_store(&resolved_owner, functions);
    }
    pthread_mutex_unlock(&owner_lock);
    return functions;
}

#define OWNER_HAS(functions, field) ((functions)->size >= offsetof(owner_functions, field) + sizeof((functions)->field))

void test_coverage_attribution_scope_begin(const char *module, const char *suite, const char *name) {
    const owner_functions *functions = process_owner();
    if (functions == &own_functions && legacy_owner) legacy_owner->begin(module, suite, name);
    else functions->scope_begin(module, suite, name);
}

void test_coverage_attribution_scope_end(const char *module, const char *suite, const char *name) {
    const owner_functions *functions = process_owner();
    if (functions == &own_functions && legacy_owner) legacy_owner->end(module, suite, name);
    else functions->scope_end(module, suite, name);
}

uint32_t test_coverage_attribution_context_begin(const char *module, const char *suite, const char *name, const void *key) {
    const owner_functions *functions = process_owner();
    return OWNER_HAS(functions, context_begin) ? functions->context_begin(module, suite, name, key) : 0;
}

void test_coverage_attribution_context_end(uint32_t context) {
    const owner_functions *functions = process_owner();
    if (OWNER_HAS(functions, context_end)) functions->context_end(context);
}

void test_coverage_attribution_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
    const owner_functions *functions = process_owner();
    if (OWNER_HAS(functions, trace_pc_guard_init)) functions->trace_pc_guard_init(start, stop);
}

void test_coverage_attribution_pcs_init(const uintptr_t *start, const uintptr_t *end) {
    const owner_functions *functions = process_owner();
    if (OWNER_HAS(functions, pcs_init)) functions->pcs_init(start, end);
}

void test_coverage_attribution_trace_pc_guard(uint32_t *guard) {
    const owner_functions *functions = atomic_load_explicit(&resolved_owner, memory_order_relaxed);
    if (functions == &own_functions) {
        own_trace_pc_guard(guard);
        return;
    }
    if (!functions) functions = process_owner();
    if (OWNER_HAS(functions, trace_pc_guard)) functions->trace_pc_guard(guard);
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

// The suites XCTest runs a class's tests in, as opposed to the bundle's and the run's.
static bool is_class_suite(NSString *name) {
    return name && ![name hasSuffix:@".xctest"] && ![name isEqualToString:@"All tests"]
        && ![name isEqualToString:@"Selected tests"];
}

// Skip list: one test per line, `module/suite/name`, the way xcodebuild's -skip-testing names a
// test and the records name it: the test bundle, the class without its Swift module, and the test
// as the result bundle names it (`testAdd()`) or as its selector (`testAdd`,
// `testAddAndReturnError:`, `testAddWithCompletionHandler:`). Blank lines, lines without exactly
// three components (a whole module is skipped with -skip-testing, and a suite can gain tests the
// list doesn't know) and tests that don't exist are ignored. An unreadable file skips nothing.
//
// The listed tests are removed from +[XCTestCase defaultTestSuite], the suite XCTest builds for
// each class, both when it lists the tests (parallel runs hand the listed tests out to their
// clones) and when it runs them. A removed test isn't in the result bundle, and a class whose
// tests are all removed doesn't run its class setUp. Only XCTest is affected: Swift Testing tests
// don't go through XCTest's suites.
static NSSet<NSString *> *skipped_tests;
static IMP original_default_test_suite;

static NSString *skip_identifier(NSString *module, NSString *suite, NSString *name) {
    for (NSString *suffix in @[@"()", @"AndReturnError:", @"WithCompletionHandler:"]) {
        if ([name hasSuffix:suffix]) {
            name = [name substringToIndex:name.length - suffix.length];
            break;
        }
    }
    return [NSString stringWithFormat:@"%@/%@/%@", module, suite, name];
}

static void load_skip_list(void) {
    const char *path = getenv("TEST_COVERAGE_ATTRIBUTION_SKIP_FILE");
    if (!path || !*path) return;
    NSString *contents = [NSString stringWithContentsOfFile:@(path) encoding:NSUTF8StringEncoding error:nil];
    NSMutableSet<NSString *> *tests = [NSMutableSet set];
    for (NSString *line in [contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSString *> *components = [[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
            componentsSeparatedByString:@"/"];
        if (components.count != 3 || components[0].length == 0 || components[1].length == 0
            || components[2].length == 0)
            continue;
        [tests addObject:skip_identifier(components[0], components[1], components[2])];
    }
    if (tests.count > 0) skipped_tests = tests;
}

// A class's suite holds its tests. When some are listed, the suite is kept and its tests replaced
// through XCTestSuite's private -setTests:, since the suite is what runs the class setUp and
// tearDown; an XCTest without it runs every test. When all are listed, an empty suite takes its
// place, so the class setUp doesn't run.
static id suite_without_skipped_tests(Class test_class, id suite) {
    Class test_case = NSClassFromString(@"XCTestCase");
    NSArray *tests = [suite valueForKey:@"tests"];
    if (!test_case || ![tests isKindOfClass:[NSArray class]]) return suite;
    NSString *module = [NSBundle bundleForClass:test_class].bundleURL.lastPathComponent.stringByDeletingPathExtension ?: @"";
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:tests.count];
    for (id test in tests) {
        if ([test isKindOfClass:test_case]) {
            NSString *test_suite, *method;
            split_xctest_name([test name], &test_suite, &method);
            if ([skipped_tests containsObject:skip_identifier(module, test_suite, method)]) continue;
        }
        [kept addObject:test];
    }
    if (kept.count == tests.count) return suite;
    if (kept.count == 0) {
        Class xctest_suite = NSClassFromString(@"XCTestSuite");
        SEL with_name = NSSelectorFromString(@"testSuiteWithName:");
        if (![xctest_suite respondsToSelector:with_name]) return suite;
        return ((id (*)(Class, SEL, NSString *))objc_msgSend)(xctest_suite, with_name, [suite name]);
    }
    SEL set_tests = NSSelectorFromString(@"setTests:");
    if (![suite respondsToSelector:set_tests]) return suite;
    ((void (*)(id, SEL, NSArray *))objc_msgSend)(suite, set_tests, kept);
    return suite;
}

static id default_test_suite_hook(Class self, SEL _cmd) {
    id suite = ((id (*)(Class, SEL))original_default_test_suite)(self, _cmd);
    @try {
        return suite_without_skipped_tests(self, suite);
    } @catch (NSException *exception) {
        return suite;
    }
}

static void skip_listed_tests(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class test_case = NSClassFromString(@"XCTestCase");
        Method method = test_case ? class_getClassMethod(test_case, NSSelectorFromString(@"defaultTestSuite")) : NULL;
        if (!method) return;
        original_default_test_suite = method_getImplementation(method);
        method_setImplementation(method, (IMP)default_test_suite_hook);
    });
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
    observe_launches();
}

- (void)testSuiteWillStart:(id)testSuite {
    NSString *name = [testSuite name];
    [self setScopeSuite:is_class_suite(name) ? name : nil test:nil];
    [self gapForSuite:nil];
}

- (void)testCaseWillStart:(id)testCase {
    NSString *suite, *method;
    split_xctest_name([testCase name], &suite, &method);
    [self gapForSuite:suite];
    [self setScopeSuite:suite test:method];
    atomic_store(&xctest_running, true);
}

- (void)testCaseDidFinish:(id)testCase {
    NSString *suite, *method;
    split_xctest_name([testCase name], &suite, &method);
    pthread_mutex_lock(&lock);
    write_record(kRecordXCTest, 0, bundle_name, suite.UTF8String, method.UTF8String);
    take_snapshot();
    pthread_mutex_unlock(&lock);
    atomic_store(&xctest_running, false);
    [self setScopeSuite:suite test:nil];
}

- (void)testSuiteDidFinish:(id)testSuite {
    NSString *name = [testSuite name];
    [self gapForSuite:is_class_suite(name) ? name : nil];
    [self setScopeSuite:nil test:nil];
}

- (void)testBundleDidFinish:(NSBundle *)testBundle {
    [self gapForSuite:nil];
}

- (void)setScopeSuite:(NSString *)suite test:(NSString *)test {
    pthread_mutex_lock(&lock);
    current_suite = suite;
    current_test = test;
    pthread_mutex_unlock(&lock);
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

// A test bundle loads after XCTest, so its classes are hooked before XCTest asks them for their
// tests. In a process that loads XCTest later, the main queue runs once it is up.
static void start_skipping(void) {
    load_skip_list();
    if (!skipped_tests) return;
    if (NSClassFromString(@"XCTestCase")) {
        skip_listed_tests();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            skip_listed_tests();
        });
    }
}

__attribute__((constructor)) static void test_coverage_attribution_init(void) {
    start_skipping();
    const char *dir = getenv("TEST_COVERAGE_ATTRIBUTION_DIR");
    if (!dir || !*dir || process_owner() != &own_functions || legacy_owner) return;
    mkdir(dir, 0755);
    snprintf(out_dir, sizeof out_dir, "%s/%d", dir, getpid());
    mkdir(out_dir, 0755);
    char file[PATH_MAX];
    snprintf(file, sizeof file, "%s/records.bin", out_dir);
    records = fopen(file, "wb");
    if (!records) return;
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
