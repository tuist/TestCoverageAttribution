@import XCTest;

/// Declares its unskippable tests from Objective-C. With `-ObjC` every test is listed: they run but
/// `testSkippable`, which the class lets the list skip.
@interface ObjCArchiveTests : XCTestCase
@end

@implementation ObjCArchiveTests

+ (BOOL)isUnskippable {
    return YES;
}

+ (NSArray<NSString *> *)skippableTests {
    return @[@"testSkippable"];
}

- (void)testUnskippable {
}

- (void)testSkippable {
    XCTAssertNil(NSProcessInfo.processInfo.environment[@"TEST_COVERAGE_ATTRIBUTION_SKIP_FILE"]);
}

@end
