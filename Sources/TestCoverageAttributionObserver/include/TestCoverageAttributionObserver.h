#ifndef TEST_COVERAGE_ATTRIBUTION_OBSERVER_H
#define TEST_COVERAGE_ATTRIBUTION_OBSERVER_H

#ifdef __cplusplus
extern "C" {
#endif

/// Starts a scope: the coverage counters that move until the matching
/// `test_coverage_attribution_scope_end` are attributed to the test named by `module`, `suite`
/// and `name`. Does nothing unless the process collects attribution.
void test_coverage_attribution_scope_begin(const char *module, const char *suite, const char *name);

/// Ends the scope `test_coverage_attribution_scope_begin` started and records it.
void test_coverage_attribution_scope_end(const char *module, const char *suite, const char *name);

#ifdef __cplusplus
}
#endif

#endif
