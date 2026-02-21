import Testing
import Foundation
@testable import PostKit

struct TimingBreakdownTests {
    @Test func timingBreakdownIsCodable() throws {
        let timing = TimingBreakdown(
            dnsLookup: 0.05,
            tcpConnection: 0.03,
            tlsHandshake: 0.02,
            transferStart: 0.01,
            download: 0.10,
            total: 0.21,
            redirectTime: 0.05
        )
        
        let data = try JSONEncoder().encode(timing)
        let decoded = try JSONDecoder().decode(TimingBreakdown.self, from: data)
        
        #expect(decoded.dnsLookup == timing.dnsLookup)
        #expect(decoded.tcpConnection == timing.tcpConnection)
        #expect(decoded.tlsHandshake == timing.tlsHandshake)
        #expect(decoded.transferStart == timing.transferStart)
        #expect(decoded.download == timing.download)
        #expect(decoded.total == timing.total)
        #expect(decoded.redirectTime == timing.redirectTime)
    }
    
    @Test func timingBreakdownIsSendable() {
        let timing = TimingBreakdown(
            dnsLookup: 0.01,
            tcpConnection: 0.02,
            tlsHandshake: 0.03,
            transferStart: 0.04,
            download: 0.05,
            total: 0.15,
            redirectTime: 0
        )
        let _: Sendable = timing
        #expect(true)
    }
}
