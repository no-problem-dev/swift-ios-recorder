import Testing
import Foundation
@testable import iOSRecorderBonjour

@Suite struct FramingTests {
    @Test func frameThenReadLengthRoundTrips() {
        let payload = Data([1, 2, 3, 4, 5])
        let framed = Framing.frame(payload)
        #expect(framed.count == payload.count + 4)
        #expect(Framing.readLength(framed.prefix(4)) == payload.count)
        #expect(Data(framed.suffix(payload.count)) == payload)
    }

    @Test func readsMultiByteLength() {
        #expect(Framing.readLength(Data([0x00, 0x01, 0x00, 0x00])) == 65536)
        #expect(Framing.readLength(Data([0x00, 0x00, 0x01, 0x2C])) == 300)
    }
}
