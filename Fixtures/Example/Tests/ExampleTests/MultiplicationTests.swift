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
}
