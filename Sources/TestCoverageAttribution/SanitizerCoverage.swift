#if canImport(TestCoverageAttributionObserver)
    import TestCoverageAttributionObserver

    // The callbacks code built with `-sanitize-coverage=func,trace-pc-guard,pc-table` calls. They're
    // defined here rather than in the observer because a test target links this module directly,
    // however the package is linked, so the code it links statically finds them; the observer
    // records. See "Functions per task" in TestCoverageAttributionObserver.m.

    @_cdecl("__sanitizer_cov_trace_pc_guard_init")
    public func sanitizerCoverageTracePCGuardInit(_ start: UnsafeMutablePointer<UInt32>?, _ stop: UnsafeMutablePointer<UInt32>?) {
        test_coverage_attribution_trace_pc_guard_init(start, stop)
    }

    @_cdecl("__sanitizer_cov_pcs_init")
    public func sanitizerCoveragePCsInit(_ start: UnsafePointer<UInt>?, _ end: UnsafePointer<UInt>?) {
        test_coverage_attribution_pcs_init(start, end)
    }

    @_cdecl("__sanitizer_cov_trace_pc_guard")
    public func sanitizerCoverageTracePCGuard(_ guard: UnsafeMutablePointer<UInt32>?) {
        test_coverage_attribution_trace_pc_guard(`guard`)
    }
#endif
