#ifndef TEST_COVERAGE_ATTRIBUTION_OBSERVER_H
#define TEST_COVERAGE_ATTRIBUTION_OBSERVER_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Starts a scope: the coverage counters that move until the matching
/// `test_coverage_attribution_scope_end` are attributed to the test named by `module`, `suite`
/// and `name`. Does nothing unless the process collects attribution.
void test_coverage_attribution_scope_begin(const char *module, const char *suite, const char *name);

/// Ends the scope `test_coverage_attribution_scope_begin` started and records it.
void test_coverage_attribution_scope_end(const char *module, const char *suite, const char *name);

/// Whether the skip list (`TEST_COVERAGE_ATTRIBUTION_SKIP_FILE`) names the test, matched the way
/// XCTest tests are.
bool test_coverage_attribution_is_skipped(const char *module, const char *suite, const char *name);

/// Reports that the test the skip list names won't run, in `skipped.tsv` beside the process's
/// output: call it once the skip is certain, as right before cancelling the test. Does nothing
/// unless the process has a skip list and `TEST_COVERAGE_ATTRIBUTION_DIR`.
void test_coverage_attribution_report_skipped(const char *module, const char *suite, const char *name);

#ifdef __cplusplus
}
#endif

#endif
