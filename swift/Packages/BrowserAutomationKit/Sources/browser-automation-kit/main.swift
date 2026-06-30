import BrowserAutomationKit
import Darwin
import Foundation

@main
struct BrowserAutomationKitCLI {
    static func main() {
        do {
            try run()
        } catch {
            fputs("browser-automation-kit: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, command != "help", command != "--help" else {
            printHelp()
            return
        }

        let service = BrowserAutomationService(store: DeveloperWorkflowLedgerStore(fileURL: ledgerURL(in: args)))

        switch command {
        case "list-templates":
            let templates = service.listTemplates()
            if hasFlag("--json", in: args) {
                try printJSON(["templates": templates])
            } else {
                templates.forEach { template in
                    print("\(template.id)\t\(template.title)\tentryPoints=\(template.entryPoints.map(\.rawValue).joined(separator: ","))")
                }
            }
        case "list-runs":
            let runs = try service.listRuns()
            if hasFlag("--json", in: args) {
                try printJSON(["runs": runs])
            } else {
                runs.forEach { run in
                    print("\(run.id.uuidString)\t\(run.status.rawValue)\t\(run.title)\t\(run.reviewSummary)")
                }
            }
        case "start-run":
            guard args.count >= 2 else { throw BrowserAutomationKitError.missingArgument("templateID") }
            let entryPoint = try entryPointValue(optionValue("--entry-point", in: args)) ?? .localREPL
            let run = try service.startRun(
                templateID: args[1],
                entryPoint: entryPoint,
                sourceURLString: optionValue("--source-url", in: args),
                snapshotSummary: optionValue("--snapshot", in: args)
            )
            if hasFlag("--json", in: args) {
                try printJSON(["run": run])
            } else {
                print("Started \(run.title) as \(run.id.uuidString)")
                print(run.reviewSummary)
            }
        case "append-evidence":
            guard args.count >= 2 else { throw BrowserAutomationKitError.missingArgument("runID") }
            guard let runID = UUID(uuidString: args[1]) else {
                throw BrowserAutomationKitError.invalidArgument("runID=\(args[1])")
            }
            let evidence = BrowserDeveloperEvidenceItem(
                kind: try evidenceKindValue(requiredOption("--kind", in: args)),
                title: try requiredOption("--title", in: args),
                summary: try requiredOption("--summary", in: args),
                sourceURLString: optionValue("--source-url", in: args),
                localFilePath: optionValue("--file", in: args),
                externalURLString: optionValue("--external-url", in: args),
                redactionState: redactionStateValue(optionValue("--redaction", in: args)) ?? .none,
                privacyBoundary: privacyBoundaryValue(optionValue("--privacy", in: args)) ?? .localOnly
            )
            let run = try service.appendEvidence(evidence, to: runID)
            if hasFlag("--json", in: args) {
                try printJSON(["run": run])
            } else {
                print("Appended evidence to \(run.id.uuidString): \(run.reviewSummary)")
            }
        case "propose-mutation":
            guard args.count >= 3 else { throw BrowserAutomationKitError.missingArgument("runID action") }
            guard let runID = UUID(uuidString: args[1]) else {
                throw BrowserAutomationKitError.invalidArgument("runID=\(args[1])")
            }
            let action = try protectedActionValue(args[2])
            let run = try service.proposeProtectedMutation(
                runID: runID,
                action: action,
                summary: optionValue("--summary", in: args) ?? "Protected mutation requested from local CLI."
            )
            if hasFlag("--json", in: args) {
                try printJSON(["run": run])
            } else {
                print("Blocked \(action.title); \(run.reviewSummary)")
            }
        case "mcp-descriptor":
            let configuration = try BrowserAutomationMCPServerConfiguration(
                transport: .stdio,
                host: optionValue("--host", in: args)
            )
            try printJSON(configuration.descriptor)
        case "serve-mcp":
            let configuration = try BrowserAutomationMCPServerConfiguration(
                transport: .stdio,
                host: optionValue("--host", in: args)
            )
            let server = BrowserAutomationMCPServer(service: service, configuration: configuration)
            while let line = readLine() {
                print(server.handleJSONRPCLine(line))
                fflush(stdout)
            }
        default:
            throw BrowserAutomationKitError.invalidArgument(command)
        }
    }

    private static func ledgerURL(in args: [String]) -> URL? {
        optionValue("--ledger", in: args).map { URL(fileURLWithPath: $0) }
            ?? DeveloperWorkflowLedgerStore.defaultFileURL()
    }

    private static func hasFlag(_ flag: String, in args: [String]) -> Bool {
        args.contains(flag)
    }

    private static func optionValue(_ option: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: option), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func requiredOption(_ option: String, in args: [String]) throws -> String {
        guard let value = optionValue(option, in: args), !value.isEmpty else {
            throw BrowserAutomationKitError.missingArgument(option)
        }
        return value
    }

    private static func entryPointValue(_ rawValue: String?) throws -> BrowserDeveloperWorkflowEntryPoint? {
        guard let rawValue else { return nil }
        guard let value = BrowserDeveloperWorkflowEntryPoint(rawValue: rawValue) else {
            throw BrowserAutomationKitError.invalidArgument("entryPoint=\(rawValue)")
        }
        return value
    }

    private static func evidenceKindValue(_ rawValue: String) throws -> BrowserDeveloperEvidenceKind {
        guard let value = BrowserDeveloperEvidenceKind(rawValue: rawValue) else {
            throw BrowserAutomationKitError.invalidArgument("kind=\(rawValue)")
        }
        return value
    }

    private static func protectedActionValue(_ rawValue: String) throws -> BrowserDeveloperProtectedAction {
        guard let value = BrowserDeveloperProtectedAction(rawValue: rawValue) else {
            throw BrowserAutomationKitError.invalidArgument("action=\(rawValue)")
        }
        return value
    }

    private static func redactionStateValue(_ rawValue: String?) -> BrowserDeveloperEvidenceRedactionState? {
        rawValue.flatMap(BrowserDeveloperEvidenceRedactionState.init(rawValue:))
    }

    private static func privacyBoundaryValue(_ rawValue: String?) -> BrowserDeveloperEvidencePrivacyBoundary? {
        rawValue.flatMap(BrowserDeveloperEvidencePrivacyBoundary.init(rawValue:))
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printHelp() {
        print(
            """
            browser-automation-kit

            Commands:
              list-templates [--json] [--ledger path]
              list-runs [--json] [--ledger path]
              start-run <templateID> [--entry-point mcp|localREPL|routine|copilot] [--source-url url] [--snapshot text] [--json] [--ledger path]
              append-evidence <runID> --kind kind --title title --summary text [--source-url url] [--file path] [--external-url url] [--privacy boundary] [--redaction state] [--json] [--ledger path]
              propose-mutation <runID> <action> [--summary text] [--json] [--ledger path]
              mcp-descriptor [--host localhost]
              serve-mcp [--stdio] [--host localhost] [--ledger path]

            Local-first guarantees:
              Evidence is stored in the local dBrowser developer workflow ledger.
              MCP mode reads JSON-RPC lines over stdio and rejects non-local host bindings.
              Protected external mutations are converted into approval-required local evidence.
            """
        )
    }
}
