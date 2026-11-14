import Testing

/// Swift Testing suites nested in others: `Fixtures/Concurrency`'s `SuitePathTests.swift`.
extension AttributionTests {
    /// A Swift Testing test is recorded under every suite it's nested in, outermost first, as the
    /// result bundle and `-only-testing` name it: a suite nested in another, ten levels deep, in an
    /// extension of it or in an enum namespace.
    @Test func recordsSwiftTestingTestsUnderTheirWholeSuitePath() throws {
        let records = try runFixture(.swiftPM, attributing: true, fixture: "Concurrency", filter: "SuitePath")
        let tests = records.filter { $0.kind == .swiftTesting }

        #expect(Set(tests.map(\.module)) == ["ConcurrencyTests"])
        #expect(tests.map { "\($0.suite)/\($0.name)" }.sorted() == [
            "SuitePathNamespace/Inner/inNamespace()",
            "SuitePathNamespace/Inner/unskippable()",
            "SuitePathTests/InExtension/inExtension()",
            "SuitePathTests/InExtension/unskippable()",
            "SuitePathTests/Nested/Third/Fourth/Fifth/Sixth/Seventh/Eighth/Ninth/Tenth/listedByInnermostSuite()",
            "SuitePathTests/Nested/Third/Fourth/Fifth/Sixth/Seventh/Eighth/Ninth/Tenth/listedByWholePath()",
            "SuitePathTests/Nested/nested()",
            "SuitePathTests/Nested/unskippable()",
            "SuitePathTests/topLevel()",
        ])
    }

    /// The list names a Swift Testing test under every suite it's nested in, outermost first, as
    /// the records and `-skip-testing` do, or, as Tuist did before it recorded whole paths, under
    /// its innermost suite alone; a path whose outer suites differ names nothing. Built with Swift
    /// 6.3 or later, the listed tests leave no record; before, they run. Either way
    /// `unskippable.tsv` says which unskippable tests the list names.
    @Test func skipsTheListedSwiftTestingTestsOfNestedSuites() throws {
        var unskippable: [String] = []
        let records = try runFixture(
            .swiftPM,
            attributing: true,
            fixture: "Concurrency",
            filter: "SuitePath",
            skipList: """
            ConcurrencyTests/SuitePathTests/topLevel()
            ConcurrencyTests/SuitePathTests/Nested/nested()
            ConcurrencyTests/SuitePathTests/Nested/unskippable()
            ConcurrencyTests/InExtension/inExtension()
            ConcurrencyTests/SuitePathNamespace/Inner/inNamespace()
            ConcurrencyTests/Inner/unskippable()
            ConcurrencyTests/Elsewhere/InExtension/unskippable()
            ConcurrencyTests/SuitePathTests/Nested/Third/Fourth/Fifth/Sixth/Seventh/Eighth/Ninth/Tenth/listedByWholePath()
            ConcurrencyTests/Tenth/listedByInnermostSuite()
            """,
        ) { unskippable = try Self.unskippableTests(in: $0) }
        let tests = records.filter { $0.kind == .swiftTesting }.map { "\($0.suite)/\($0.name)" }.sorted()

        #if compiler(>=6.3)
            #expect(tests == [
                "SuitePathNamespace/Inner/unskippable()",
                "SuitePathTests/InExtension/unskippable()",
                "SuitePathTests/Nested/unskippable()",
            ])
        #else
            #expect(tests.count == 9)
        #endif
        #expect(unskippable == [
            "ConcurrencyTests\tSuitePathNamespace/Inner\tunskippable()\t1",
            "ConcurrencyTests\tSuitePathTests/InExtension\tunskippable()\t0",
            "ConcurrencyTests\tSuitePathTests/Nested\tunskippable()\t1",
        ])
    }
}
