import Example
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution, .serialized)
struct MultiplicationTests {
    @Test func multiply() {
        #expect(Calculator.multiply(2, 3) == 6)
    }

    @Test("Multiplying by zero") func multiplyByZero() {
        #expect(Calculator.multiply(0, 3) == 0)
    }

    /// Runs even when the skip list names it.
    @Test(.unskippable) func multiplyByOne() {
        #expect(Calculator.multiply(1, 3) == 3)
    }

    /// Its tests run even when the skip list names them, except the one that opts back in. Nested,
    /// so `.serialized` keeps it from running at the same time as the other tests.
    @Suite(.unskippable)
    struct UnskippableMultiplicationTests {
        @Test func multiplyNegatives() {
            #expect(Calculator.multiply(-2, -3) == 6)
        }

        @Test func multiplyByMinusOne() {
            #expect(Calculator.multiply(-1, 3) == -3)
        }

        @Test(.skippable) func square() {
            #expect(Calculator.multiply(3, 3) == 9)
        }
    }
}
