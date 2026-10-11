import Foundation
import Testing

@testable import ScoreKit

/// The bundle `npm run parser:bundle` writes for the app, and the spec's example score.
private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ScoreKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // scorekit
    .deletingLastPathComponent()  // packages
    .deletingLastPathComponent()

private func compiler() throws -> JianpuCompiler {
    try JianpuCompiler(
        script: String(contentsOf: repository.appending(path: "apps/ios/Dizi/Parser/parser.js"), encoding: .utf8))
}

@Test func compilesTheExampleAsTheToolsDo() throws {
    let text = try String(contentsOf: repository.appending(path: "docs/examples/molihua.jianpu"), encoding: .utf8)
    guard case .score(let score) = try compiler().compile(text) else {
        Issue.record("the example did not compile")
        return
    }
    let expected = try molihua()

    #expect(score.meta.title == expected.meta.title)
    #expect(score.measures.map(\.start) == expected.measures.map(\.start))
    #expect(score.playOrder == expected.playOrder)
}

@Test func reportsWhereTheTextIsWrong() throws {
    let compiled = try compiler().compile("key: 1=D\ntime: 2/4\ntempo: 72\n\n1 2 3 |\n")

    guard case .failed(let errors) = compiled else {
        Issue.record("a bar of three beats in 2/4 compiled")
        return
    }
    #expect(errors.first?.position.line == 5)
}
