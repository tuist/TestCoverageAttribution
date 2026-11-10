@import XCTest;
#import "Classify.h"

@interface ByteCoverageTests : XCTestCase
@end

@implementation ByteCoverageTests

- (void)testClassify {
    XCTAssertEqual(classify(-3), -1);
    XCTAssertEqual(classify(0), 0);
}

- (void)testSum {
    XCTAssertEqual(sum(4), 10);
}

@end
