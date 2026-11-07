#ifndef TEST_COVERAGE_ATTRIBUTION_OBSERVER_H
#define TEST_COVERAGE_ATTRIBUTION_OBSERVER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Starts a scope: the coverage counters that move until the matching
/// `test_coverage_attribution_scope_end` are attributed to the test named by `module`, `suite`
/// and `name`. Does nothing unless the process collects attribution.
void test_coverage_attribution_scope_begin(const char *module, const char *suite, const char *name);

/// Ends the scope `test_coverage_attribution_scope_begin` started and records it.
void test_coverage_attribution_scope_end(const char *module, const char *suite, const char *name);

/// Opens a context for the test named by `module`, `suite` and `name`, and returns its id, 0 when
/// the process tracks no functions. The caller binds the id to `key`, a `TaskLocal<UInt32>`, for
/// the test's task: the functions entered under it, in code built with
/// `-sanitize-coverage=func,trace-pc-guard,pc-table`, are attributed to the test.
uint32_t test_coverage_attribution_context_begin(const char *module, const char *suite, const char *name, const void *key);

/// Ends the context `test_coverage_attribution_context_begin` opened and records its functions.
void test_coverage_attribution_context_end(uint32_t context);

/// SanitizerCoverage's callbacks (`__sanitizer_cov_trace_pc_guard_init`, `__sanitizer_cov_pcs_init`
/// and `__sanitizer_cov_trace_pc_guard`), which the TestCoverageAttribution module defines and
/// forwards here.
void test_coverage_attribution_trace_pc_guard_init(uint32_t *start, uint32_t *stop);
void test_coverage_attribution_pcs_init(const uintptr_t *start, const uintptr_t *end);
void test_coverage_attribution_trace_pc_guard(uint32_t *guard);

#ifdef __cplusplus
}
#endif

#endif
