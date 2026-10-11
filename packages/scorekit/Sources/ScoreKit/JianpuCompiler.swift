import Foundation
import JavaScriptCore

/// Compiles score text (docs/score-format.md) on the device by running the TypeScript parser, bundled into one
/// script by `npm run parser:bundle`, in JavaScriptCore: one implementation of the format for the tools and the app.
/// Evaluating the script touches nothing outside the context, so compiling is a calculation.
public final class JianpuCompiler {
    private let compileToJSON: JSValue

    /// Evaluates the bundle, which defines the global `DiziParser`.
    public init(script: String) throws {
        guard let context = JSContext() else { throw JianpuCompilerError.noContext }
        context.evaluateScript(script)
        context.evaluateScript("var compileToJSON = (text) => JSON.stringify(DiziParser.compile(text))")
        guard context.exception == nil, let compileToJSON = context.objectForKeyedSubscript("compileToJSON"),
            !compileToJSON.isUndefined
        else { throw JianpuCompilerError.badScript(context.exception?.toString() ?? "") }
        self.compileToJSON = compileToJSON
    }

    public func compile(_ text: String) throws -> Compiled {
        guard let json = compileToJSON.call(withArguments: [text])?.toString(), let data = json.data(using: .utf8)
        else { throw JianpuCompilerError.badScript("compile returned nothing") }
        let result = try JSONDecoder().decode(Output.self, from: data)
        return result.score.map(Compiled.score) ?? .failed(result.diagnostics.filter { $0.severity == .error })
    }

    /// The parser's result: a score, or none when any diagnostic is an error.
    private struct Output: Decodable {
        let score: Score?
        let diagnostics: [Diagnostic]
    }
}

/// A compiled score, or the errors that stopped it.
public enum Compiled: Sendable {
    case score(Score)
    case failed([Diagnostic])
}

/// A problem the parser found, at a line and column of the text (both from 1). Messages are English.
public struct Diagnostic: Decodable, Sendable, Equatable {
    public enum Severity: String, Decodable, Sendable { case error, warning }
    public struct Position: Decodable, Sendable, Equatable {
        public let line: Int
        public let column: Int
    }

    public let severity: Severity
    public let position: Position
    public let message: String
}

public enum JianpuCompilerError: Error {
    case noContext
    case badScript(String)
}
