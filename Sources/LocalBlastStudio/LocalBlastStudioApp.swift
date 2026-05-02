import AppKit
import Foundation
import LocalBlastCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct LocalBlastStudioApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 720)
                .task {
                    await model.bootstrap()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case run = "Run BLAST"
    case databases = "Databases"
    case tools = "Tools"
    case jobs = "Jobs"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .run: "play.circle"
        case .databases: "internaldrive"
        case .tools: "wrench.and.screwdriver"
        case .jobs: "clock.arrow.circlepath"
        }
    }
}

struct BlastPreferences: Codable, Equatable, Sendable {
    var blastBinDirectory: String
    var databaseDirectory: String
    var outputDirectory: String
    var decompressDownloads: Bool
    var useVersion5Databases: Bool

    static var defaults: BlastPreferences {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LocalBlastStudio", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LocalBlastStudio Results", isDirectory: true)
        return BlastPreferences(
            blastBinDirectory: "",
            databaseDirectory: support.appendingPathComponent("Databases", isDirectory: true).path,
            outputDirectory: documents.path,
            decompressDownloads: true,
            useVersion5Databases: true
        )
    }

    static func load() -> BlastPreferences {
        guard let data = UserDefaults.standard.data(forKey: "BlastPreferences"),
              let preferences = try? JSONDecoder().decode(BlastPreferences.self, from: data) else {
            return defaults
        }
        return preferences
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "BlastPreferences")
        }
    }
}

struct ToolStatus: Identifiable, Hashable {
    var name: String
    var path: String
    var version: String
    var isAvailable: Bool

    var id: String { name }
}

struct BlastJobRecord: Identifiable, Hashable {
    var id = UUID()
    var program: BlastProgram
    var database: String
    var outputPath: String
    var commandPreview: String
    var exitCode: Int32
    var date: Date
}

struct ProcessResult: Sendable {
    var exitCode: Int32
    var output: String
}

final class PipeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func stringValue() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(decoding: snapshot, as: UTF8.self)
    }
}

enum LocalBlastError: Error, LocalizedError {
    case toolMissing(String)
    case cannotCreateDirectory(String)
    case emptyDownloadSelection

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool):
            "Could not find \(tool). Set the BLAST+ bin directory in Tools."
        case .cannotCreateDirectory(let path):
            "Could not create directory: \(path)"
        case .emptyDownloadSelection:
            "Select at least one database to download."
        }
    }
}

enum ProcessClient {
    static let searchTools = BlastProgram.allCases.map(\.executableName)
    static let utilityTools = [
        "makeblastdb", "blastdbcmd", "update_blastdb.pl", "dustmasker", "segmasker",
        "windowmasker", "makeprofiledb", "makembindex", "convert2blastmask"
    ]

    static func resolveExecutable(named name: String, preferences: BlastPreferences) -> URL? {
        let fileManager = FileManager.default
        if !preferences.blastBinDirectory.isEmpty {
            let custom = URL(fileURLWithPath: preferences.blastBinDirectory).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: custom.path) {
                return custom
            }
        }

        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/opt/homebrew/anaconda3/bin",
            "/opt/homebrew/miniconda3/bin",
            "/opt/homebrew/miniforge3/bin",
            "/opt/homebrew/mambaforge/bin",
            "/usr/local/bin",
            "/usr/local/anaconda3/bin",
            "/usr/local/miniconda3/bin",
            "/usr/local/miniforge3/bin",
            "/usr/local/mambaforge/bin",
            "/opt/anaconda3/bin",
            "/opt/miniconda3/bin",
            "/opt/miniforge3/bin",
            "\(homeDirectory)/anaconda3/bin",
            "\(homeDirectory)/miniconda3/bin",
            "\(homeDirectory)/miniforge3/bin",
            "\(homeDirectory)/mambaforge/bin",
            "/usr/bin",
            "/bin"
        ]

        for directory in uniqueDirectories(pathDirectories + commonDirectories) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let applicationURLs = (try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil
        )) ?? []
        for url in applicationURLs where url.lastPathComponent.lowercased().contains("ncbi-blast") {
            let candidate = url.appendingPathComponent("bin").appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func uniqueDirectories(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.filter { directory in
            guard !directory.isEmpty, !seen.contains(directory) else { return false }
            seen.insert(directory)
            return true
        }
    }

    static func runSync(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }
        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            environment.forEach { merged[$0.key] = $0.value }
            process.environment = merged
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let output = PipeOutputBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            output.append(data)
        }

        try process.run()
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        let remaining = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            output.append(remaining)
        }

        return ProcessResult(exitCode: process.terminationStatus, output: output.stringValue())
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: WorkspaceSection = .run
    @Published var preferences: BlastPreferences {
        didSet {
            preferences.save()
            configuration.databaseDirectory = preferences.databaseDirectory
            ensureDefaultOutputPath()
            updateCommandPreview()
        }
    }
    @Published var configuration: BlastSearchConfiguration {
        didSet { updateCommandPreview() }
    }
    @Published var databaseCatalog: [BlastDatabaseEntry] = FallbackDatabaseCatalog.entries
    @Published var installedDatabaseSummary = InstalledDatabaseSummary()
    @Published var selectedDatabaseNames: Set<String> = []
    @Published var databaseSearchText = ""
    @Published var databaseLog = ""
    @Published var runLog = ""
    @Published var helpText = ""
    @Published var commandPreview = ""
    @Published var isRunningSearch = false
    @Published var isRefreshingCatalog = false
    @Published var isDownloading = false
    @Published var toolStatuses: [ToolStatus] = []
    @Published var jobs: [BlastJobRecord] = []
    @Published var customDatabaseInput = ""
    @Published var customDatabaseName = ""
    @Published var customDatabaseType = "nucl"
    @Published var customDatabaseParseSeqIDs = true

    init() {
        let preferences = BlastPreferences.load()
        self.preferences = preferences
        self.configuration = BlastSearchConfiguration(
            program: .blastn,
            databaseName: "nt",
            databaseDirectory: preferences.databaseDirectory
        )
        ensureDefaultOutputPath()
        markInstalledDatabases()
        updateCommandPreview()
    }

    func bootstrap() async {
        ensureWorkingDirectories()
        await refreshTools()
        markInstalledDatabases()
        databaseLog = "Offline startup complete. Local databases were scanned; use Refresh Catalog or Download Selected when you want to contact NCBI."
    }

    func ensureWorkingDirectories() {
        _ = try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: preferences.databaseDirectory),
            withIntermediateDirectories: true
        )
        _ = try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: preferences.outputDirectory),
            withIntermediateDirectories: true
        )
    }

    func ensureDefaultOutputPath() {
        if configuration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let filename = "blast-\(configuration.program.rawValue)-result.txt"
            configuration.outputPath = URL(fileURLWithPath: preferences.outputDirectory)
                .appendingPathComponent(filename)
                .path
        }
    }

    func setProgram(_ program: BlastProgram) {
        configuration.program = program
        configuration.resetOptionsForProgram()
        if let matchingDatabase = databaseCatalog.first(where: { $0.kind == program.databaseKind && $0.isInstalled }) ??
            databaseCatalog.first(where: { $0.kind == program.databaseKind }) {
            configuration.databaseName = matchingDatabase.name
        }
        ensureDefaultOutputPath()
        updateCommandPreview()
    }

    func updateCommandPreview() {
        let queryPath = configuration.queryFilePath.isEmpty ? "<pasted-query.fasta>" : configuration.queryFilePath
        let subjectPath = configuration.subjectFilePath.isEmpty ? "<subject.fasta>" : configuration.subjectFilePath
        do {
            commandPreview = try BlastCommandBuilder.build(
                configuration: configuration,
                queryPath: queryPath,
                subjectPath: subjectPath
            ).preview
        } catch {
            commandPreview = error.localizedDescription
        }
    }

    func refreshTools() async {
        let tools = ProcessClient.searchTools + ProcessClient.utilityTools
        var statuses: [ToolStatus] = []
        for tool in tools {
            guard let url = ProcessClient.resolveExecutable(named: tool, preferences: preferences) else {
                statuses.append(ToolStatus(name: tool, path: "Not found", version: "", isAvailable: false))
                continue
            }
            let version = await Task.detached {
                (try? ProcessClient.runSync(executableURL: url, arguments: ["-version"]).output)
                    ?? (try? ProcessClient.runSync(executableURL: url, arguments: ["--version"]).output)
                    ?? ""
            }.value
            statuses.append(
                ToolStatus(
                    name: tool,
                    path: url.path,
                    version: version.components(separatedBy: .newlines).first ?? "",
                    isAvailable: true
                )
            )
        }
        toolStatuses = statuses
    }

    func refreshDatabaseCatalog() async {
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }
        guard let updater = ProcessClient.resolveExecutable(named: "update_blastdb.pl", preferences: preferences) else {
            databaseLog = "Using the built-in starter catalog because update_blastdb.pl was not found. Install NCBI BLAST+ and refresh to discover the live complete catalog."
            markInstalledDatabases()
            return
        }

        do {
            let result = try await Task.detached {
                try ProcessClient.runSync(executableURL: updater, arguments: ["--showall"])
            }.value
            let parsed = BlastDatabaseParser.parseShowAll(result.output)
            if parsed.isEmpty {
                databaseLog = "update_blastdb.pl --showall returned no database names. Keeping the starter catalog.\n\n\(result.output)"
            } else {
                databaseCatalog = parsed
                databaseLog = "Loaded \(parsed.count) downloadable databases from update_blastdb.pl --showall."
            }
            markInstalledDatabases()
        } catch {
            databaseLog = "Could not refresh from update_blastdb.pl. Using the starter catalog.\n\n\(error.localizedDescription)"
            markInstalledDatabases()
        }
    }

    func markInstalledDatabases() {
        let summary = InstalledBlastDatabaseScanner.summary(directory: URL(fileURLWithPath: preferences.databaseDirectory))
        installedDatabaseSummary = summary
        databaseCatalog = BlastDatabaseParser.markInstalled(databaseCatalog, installedNames: summary.names)
    }

    func downloadSelectedDatabases() async {
        guard !selectedDatabaseNames.isEmpty else {
            databaseLog = LocalBlastError.emptyDownloadSelection.localizedDescription
            return
        }
        guard let updater = ProcessClient.resolveExecutable(named: "update_blastdb.pl", preferences: preferences) else {
            databaseLog = LocalBlastError.toolMissing("update_blastdb.pl").localizedDescription
            return
        }

        ensureWorkingDirectories()
        isDownloading = true
        defer { isDownloading = false }

        let names = selectedDatabaseNames.sorted()
        var arguments: [String] = []
        if preferences.decompressDownloads {
            arguments.append("--decompress")
        }
        if preferences.useVersion5Databases {
            arguments.append(contentsOf: ["--blastdb_version", "5"])
        }
        arguments.append(contentsOf: names)
        databaseLog = "Starting download: \(names.joined(separator: ", "))"
        let databaseDirectory = preferences.databaseDirectory

        do {
            let result = try await Task.detached {
                try ProcessClient.runSync(
                    executableURL: updater,
                    arguments: arguments,
                    currentDirectoryURL: URL(fileURLWithPath: databaseDirectory)
                )
            }.value
            if result.exitCode != 0, self.isUnknownBlastDBVersionOption(result.output) {
                var fallbackArguments = arguments
                if let optionIndex = fallbackArguments.firstIndex(of: "--blastdb_version"),
                   fallbackArguments.indices.contains(optionIndex + 1) {
                    fallbackArguments.removeSubrange(optionIndex...(optionIndex + 1))
                }
                databaseLog = "This update_blastdb.pl does not support --blastdb_version. Retrying without it: \(names.joined(separator: ", "))"
                let fallbackResult = try await Task.detached {
                    try ProcessClient.runSync(
                        executableURL: updater,
                        arguments: fallbackArguments,
                        currentDirectoryURL: URL(fileURLWithPath: databaseDirectory)
                    )
                }.value
                markInstalledDatabases()
                databaseLog = fallbackResult.output.isEmpty
                    ? "Download finished with exit code \(fallbackResult.exitCode)."
                    : fallbackResult.output
                return
            }
            markInstalledDatabases()
            databaseLog = result.output.isEmpty
                ? "Download finished with exit code \(result.exitCode)."
                : result.output
        } catch {
            databaseLog = "Download failed: \(error.localizedDescription)"
        }
    }

    private nonisolated func isUnknownBlastDBVersionOption(_ output: String) -> Bool {
        let lowercased = output.lowercased()
        return lowercased.contains("unknown option")
            && lowercased.contains("blastdb_version")
    }

    func buildCustomDatabase() async {
        guard let makeblastdb = ProcessClient.resolveExecutable(named: "makeblastdb", preferences: preferences) else {
            databaseLog = LocalBlastError.toolMissing("makeblastdb").localizedDescription
            return
        }
        guard !customDatabaseInput.isEmpty, !customDatabaseName.isEmpty else {
            databaseLog = "Choose a FASTA file and provide a database name."
            return
        }

        ensureWorkingDirectories()
        var arguments = [
            "-in", customDatabaseInput,
            "-dbtype", customDatabaseType,
            "-out", URL(fileURLWithPath: preferences.databaseDirectory).appendingPathComponent(customDatabaseName).path
        ]
        if customDatabaseParseSeqIDs {
            arguments.append("-parse_seqids")
        }

        isDownloading = true
        defer { isDownloading = false }

        do {
            let result = try await Task.detached {
                try ProcessClient.runSync(executableURL: makeblastdb, arguments: arguments)
            }.value
            markInstalledDatabases()
            databaseLog = result.output.isEmpty
                ? "Custom database built with exit code \(result.exitCode)."
                : result.output
        } catch {
            databaseLog = "makeblastdb failed: \(error.localizedDescription)"
        }
    }

    func runSearch() async {
        guard let executable = ProcessClient.resolveExecutable(named: configuration.program.executableName, preferences: preferences) else {
            runLog = LocalBlastError.toolMissing(configuration.program.executableName).localizedDescription
            return
        }

        ensureWorkingDirectories()
        ensureDefaultOutputPath()
        isRunningSearch = true
        defer { isRunningSearch = false }

        do {
            let queryPath = try materializedSequencePath(
                filePath: configuration.queryFilePath,
                sequenceText: configuration.queryText,
                filenamePrefix: "query",
                missingError: .missingQuery
            )
            let subjectPath = configuration.alignTwoSequences ? try materializedSequencePath(
                filePath: configuration.subjectFilePath,
                sequenceText: configuration.subjectText,
                filenamePrefix: "subject",
                missingError: .missingSubject
            ) : ""
            let command = try BlastCommandBuilder.build(
                configuration: configuration,
                queryPath: queryPath,
                subjectPath: subjectPath
            )
            runLog = "Running \(command.preview)"
            let databaseDirectory = preferences.databaseDirectory
            let result = try await Task.detached {
                try ProcessClient.runSync(
                    executableURL: executable,
                    arguments: command.arguments,
                    environment: ["BLASTDB": databaseDirectory]
                )
            }.value

            let logText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            runLog = logText.isEmpty ? "Finished with exit code \(result.exitCode)." : logText
            jobs.insert(
                BlastJobRecord(
                    program: configuration.program,
                    database: configuration.databaseName,
                    outputPath: configuration.outputPath,
                    commandPreview: command.preview,
                    exitCode: result.exitCode,
                    date: Date()
                ),
                at: 0
            )
        } catch {
            runLog = error.localizedDescription
        }
    }

    func loadHelpForSelectedProgram() async {
        guard let executable = ProcessClient.resolveExecutable(named: configuration.program.executableName, preferences: preferences) else {
            helpText = LocalBlastError.toolMissing(configuration.program.executableName).localizedDescription
            return
        }
        do {
            let result = try await Task.detached {
                try ProcessClient.runSync(executableURL: executable, arguments: ["-help"])
            }.value
            helpText = result.output
        } catch {
            helpText = error.localizedDescription
        }
    }

    private func materializedSequencePath(
        filePath: String,
        sequenceText: String,
        filenamePrefix: String,
        missingError: BlastCommandBuildError
    ) throws -> String {
        let filePath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filePath.isEmpty {
            return filePath
        }

        let sequence = sequenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sequence.isEmpty else {
            throw missingError
        }

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalBlastStudio", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("\(filenamePrefix)-\(UUID().uuidString).fasta")
        try sequence.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(WorkspaceSection.allCases, selection: $model.section) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            switch model.section {
            case .run:
                RunBlastView()
            case .databases:
                DatabasesView()
            case .tools:
                ToolsView()
            case .jobs:
                JobsView()
            }
        }
    }
}

struct RunBlastView: View {
    @EnvironmentObject private var model: AppModel

    var availableDatabases: [BlastDatabaseEntry] {
        model.databaseCatalog
            .filter { $0.kind == model.configuration.program.databaseKind || model.configuration.program.databaseKind == .mixed || $0.kind == .mixed }
            .sorted { lhs, rhs in
                if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled && !rhs.isInstalled }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "Local BLAST",
                subtitle: "\(model.configuration.program.summary) Everything runs through local BLAST+ binaries."
            ) {
                Button {
                    Task { await model.loadHelpForSelectedProgram() }
                } label: {
                    Label("Load CLI Help", systemImage: "questionmark.circle")
                }
                .help("Load the full -help output for the selected BLAST+ program.")
            }

            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            runControls
                            runSidebar
                        }
                        .padding(20)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            runControls
                                .padding(20)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        Divider()

                        ScrollView {
                            runSidebar
                                .padding(20)
                        }
                        .frame(width: min(max(proxy.size.width * 0.38, 420), 620))
                    }
                }
            }
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            programSection
            querySection
            if model.configuration.alignTwoSequences {
                subjectSection
            } else {
                databaseSection
            }
            ParameterEditorView(program: model.configuration.program, values: $model.configuration.optionValues)
            advancedSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            commandPreview
            outputSection
            logSection
            helpSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var programSection: some View {
        Panel(title: "Program", systemImage: "function") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(BlastProgram.allCases) { program in
                    ProgramChoiceButton(
                        program: program,
                        isSelected: model.configuration.program == program
                    ) {
                        model.setProgram(program)
                    }
                }
            }

            LabeledContent("Query") {
                Text(model.configuration.program.queryKind.rawValue)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Database") {
                Text(model.configuration.alignTwoSequences ? "Subject sequence" : model.configuration.program.databaseKind.rawValue)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var querySection: some View {
        Panel(title: "Query", systemImage: "doc.text.magnifyingglass") {
            HStack {
                TextField("FASTA file", text: $model.configuration.queryFilePath)
                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["fa", "fasta", "faa", "fna", "fas", "txt"]) {
                        model.configuration.queryFilePath = path
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Choose a FASTA query file.")
            }

            SequenceTextEditor(
                text: $model.configuration.queryText,
                placeholder: "Paste FASTA here when no query file is selected"
            )

            HStack {
                TextField("Query range, e.g. 1-250", text: $model.configuration.querySubrange)
                    .textFieldStyle(.roundedBorder)
                Toggle("Align two sequences", isOn: $model.configuration.alignTwoSequences)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var subjectSection: some View {
        Panel(title: "Subject", systemImage: "arrow.left.arrow.right") {
            HStack {
                TextField("Subject FASTA file", text: $model.configuration.subjectFilePath)
                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["fa", "fasta", "faa", "fna", "fas", "txt"]) {
                        model.configuration.subjectFilePath = path
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Choose a FASTA subject file.")
            }

            SequenceTextEditor(
                text: $model.configuration.subjectText,
                placeholder: "Paste the second FASTA sequence here"
            )

            TextField("Subject range, e.g. 10-300", text: $model.configuration.subjectSubrange)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var databaseSection: some View {
        Panel(title: "Search Set", systemImage: "externaldrive.connected.to.line.below") {
            Picker("Database", selection: $model.configuration.databaseName) {
                ForEach(availableDatabases) { database in
                    Text("\(database.name)\(database.isInstalled ? "" : " - not installed")")
                        .tag(database.name)
                }
            }

            HStack {
                TextField("Database directory", text: $model.preferences.databaseDirectory)
                Button {
                    if let path = OpenPanel.chooseDirectory() {
                        model.preferences.databaseDirectory = path
                        model.markInstalledDatabases()
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Choose the BLASTDB directory.")
            }
        }
    }

    private var advancedSection: some View {
        Panel(title: "Advanced", systemImage: "terminal") {
            TextField("Raw BLAST+ arguments, e.g. -dbsize 1000000 -parse_deflines", text: $model.configuration.rawArguments)
                .textFieldStyle(.roundedBorder)
            Text("Raw arguments are appended last, so they can cover BLAST+ switches that are not exposed as structured controls yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var commandPreview: some View {
        Panel(title: "Command Preview", systemImage: "chevron.left.forwardslash.chevron.right") {
            ScrollView(.horizontal) {
                Text(model.commandPreview)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button {
                    Task { await model.runSearch() }
                } label: {
                    Label(model.isRunningSearch ? "Running" : "Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunningSearch)

                Button {
                    if let path = OpenPanel.saveFile(defaultName: "blast-result.txt") {
                        model.configuration.outputPath = path
                    }
                } label: {
                    Label("Output", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private var outputSection: some View {
        Panel(title: "Output", systemImage: "doc.badge.gearshape") {
            TextField("Output file", text: $model.configuration.outputPath)
        }
    }

    private var logSection: some View {
        Panel(title: "Run Log", systemImage: "text.bubble") {
            ScrollView {
                Text(model.runLog.isEmpty ? "No run started." : model.runLog)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140)
        }
    }

    @ViewBuilder
    private var helpSection: some View {
        if !model.helpText.isEmpty {
            Panel(title: "\(model.configuration.program.displayName) Help", systemImage: "list.bullet.rectangle") {
                ScrollView {
                    Text(model.helpText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)
            }
        }
    }
}

struct ParameterEditorView: View {
    var program: BlastProgram
    @Binding var values: [String: String]

    var body: some View {
        ForEach(BlastParameterCatalog.groups, id: \.self) { group in
            let groupOptions = BlastParameterCatalog.options(for: program).filter { $0.group == group }
            if !groupOptions.isEmpty {
                Panel(title: group, systemImage: icon(for: group)) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        ForEach(groupOptions) { option in
                            GridRow {
                                Text(option.title)
                                    .frame(width: 190, alignment: .leading)
                                control(for: option)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !option.help.isEmpty {
                                GridRow {
                                    Color.clear.frame(width: 190, height: 0)
                                    Text(option.help)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func control(for option: BlastOption) -> some View {
        switch option.control {
        case .checkbox:
            Toggle("", isOn: Binding(
                get: { values[option.id]?.booleanValue ?? false },
                set: { values[option.id] = $0 ? "true" : "false" }
            ))
            .labelsHidden()
        case .picker:
            Picker(option.title, selection: Binding(
                get: { values[option.id] ?? option.defaultValue },
                set: { values[option.id] = $0 }
            )) {
                ForEach(option.choices, id: \.value) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
            .labelsHidden()
        case .integer, .decimal, .text:
            TextField(option.flag, text: Binding(
                get: { values[option.id] ?? option.defaultValue },
                set: { values[option.id] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        case .multiline:
            TextEditor(text: Binding(
                get: { values[option.id] ?? option.defaultValue },
                set: { values[option.id] = $0 }
            ))
            .frame(minHeight: 80)
        }
    }

    private func icon(for group: String) -> String {
        switch group {
        case "General": "slider.horizontal.3"
        case "Scoring": "sum"
        case "Filters": "line.3.horizontal.decrease.circle"
        case "Algorithm": "gearshape.2"
        case "Results": "target"
        case "Output": "doc.text"
        case "PSI-BLAST": "repeat"
        default: "switch.2"
        }
    }
}

struct ProgramChoiceButton: View {
    var program: BlastProgram
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(program.displayName)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : Color(nsColor: .controlColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .help(program.summary)
    }
}

struct SequenceTextEditor: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 160)
    }
}

struct DatabasesView: View {
    @EnvironmentObject private var model: AppModel

    private var installedNames: [String] {
        model.installedDatabaseSummary.names.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var notInstalledDatabases: [BlastDatabaseEntry] {
        model.databaseCatalog
            .filter { !$0.isInstalled }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var installedSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: model.installedDatabaseSummary.byteSize, countStyle: .file)
    }

    var filteredDatabases: [BlastDatabaseEntry] {
        let query = model.databaseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? model.databaseCatalog : model.databaseCatalog.filter {
            $0.name.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled && !rhs.isInstalled }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "NCBI Databases",
                subtitle: "Discover the live catalog, download selected databases, and build custom local databases."
            ) {
                Button {
                    Task { await model.refreshDatabaseCatalog() }
                } label: {
                    Label("Refresh Catalog", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshingCatalog)
            }

            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            databaseMainColumn
                            databaseSideColumn
                        }
                        .padding(20)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            databaseMainColumn
                                .padding(20)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        ScrollView {
                            databaseSideColumn
                                .padding(20)
                        }
                        .frame(width: min(max(proxy.size.width * 0.38, 420), 620))
                    }
                }
            }
        }
    }

    private var databaseMainColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Panel(title: "Storage", systemImage: "internaldrive") {
                HStack {
                    TextField("Database directory", text: $model.preferences.databaseDirectory)
                    Button {
                        if let path = OpenPanel.chooseDirectory() {
                            model.preferences.databaseDirectory = path
                            model.markInstalledDatabases()
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                }
                Toggle("Decompress after download", isOn: $model.preferences.decompressDownloads)
                Toggle("Use version 5 accession-aware databases", isOn: $model.preferences.useVersion5Databases)
            }

            installedSummaryPanel
            downloadCatalogPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var databaseSideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            missingCatalogPanel
            customDatabasePanel
            Panel(title: "Database Log", systemImage: "text.bubble") {
                ScrollView {
                    Text(model.databaseLog.isEmpty ? "No database operation started." : model.databaseLog)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadCatalogPanel: some View {
        Panel(title: "Download Catalog", systemImage: "tray.and.arrow.down") {
            TextField("Search databases", text: $model.databaseSearchText)
            HStack {
                Button {
                    for database in filteredDatabases {
                        model.selectedDatabaseNames.insert(database.name)
                    }
                } label: {
                    Label("Select Visible", systemImage: "checklist.checked")
                }

                Button {
                    model.selectedDatabaseNames.removeAll()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }

                Button {
                    Task { await model.downloadSelectedDatabases() }
                } label: {
                    Label(model.isDownloading ? "Working" : "Download Selected", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isDownloading)
            }

            List(filteredDatabases) { database in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { model.selectedDatabaseNames.contains(database.name) },
                        set: { selected in
                            if selected {
                                model.selectedDatabaseNames.insert(database.name)
                            } else {
                                model.selectedDatabaseNames.remove(database.name)
                            }
                        }
                    ))
                    .labelsHidden()
                    Image(systemName: database.isInstalled ? "checkmark.seal.fill" : "circle")
                        .foregroundStyle(database.isInstalled ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(database.name)
                            .font(.headline)
                        Text(database.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(database.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .frame(minHeight: 360)
        }
    }

    private var installedSummaryPanel: some View {
        Panel(title: "Installed Databases", systemImage: "checkmark.seal") {
            HStack(spacing: 16) {
                SummaryMetric(label: "Databases", value: "\(installedNames.count)")
                SummaryMetric(label: "Files", value: "\(model.installedDatabaseSummary.fileCount)")
                SummaryMetric(label: "Storage", value: installedSizeLabel)
            }

            if installedNames.isEmpty {
                ContentUnavailableView(
                    "No installed databases found",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Choose the folder that contains your decompressed BLAST database files.")
                )
                .frame(minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(installedNames, id: \.self) { name in
                        Label(name, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var missingCatalogPanel: some View {
        Panel(title: "Not Installed From Catalog", systemImage: "tray") {
            if notInstalledDatabases.isEmpty {
                Label("Every catalog entry currently visible to the app is installed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(notInstalledDatabases.count) catalog entries are not installed in this folder.")
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notInstalledDatabases.prefix(24)) { database in
                            HStack {
                                Text(database.name)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text(database.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if notInstalledDatabases.count > 24 {
                            Text("+ \(notInstalledDatabases.count - 24) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 170)
            }
        }
    }

    private var customDatabasePanel: some View {
        Panel(title: "Custom Database", systemImage: "hammer") {
            HStack {
                TextField("Input FASTA", text: $model.customDatabaseInput)
                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["fa", "fasta", "faa", "fna", "fas", "txt"]) {
                        model.customDatabaseInput = path
                        if model.customDatabaseName.isEmpty {
                            model.customDatabaseName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                }
            }
            TextField("Database name", text: $model.customDatabaseName)
            Picker("Type", selection: $model.customDatabaseType) {
                Text("Nucleotide").tag("nucl")
                Text("Protein").tag("prot")
            }
            Toggle("Parse sequence IDs", isOn: $model.customDatabaseParseSeqIDs)
            Button {
                Task { await model.buildCustomDatabase() }
            } label: {
                Label("Build with makeblastdb", systemImage: "play")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isDownloading)
        }
    }
}

struct SummaryMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 94, alignment: .leading)
    }
}

struct ToolsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "BLAST+ Tools",
                subtitle: "Point the app at an NCBI BLAST+ bin folder, then verify the full local suite."
            ) {
                Button {
                    Task { await model.refreshTools() }
                } label: {
                    Label("Recheck", systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Panel(title: "Location", systemImage: "folder.badge.gearshape") {
                        HStack {
                            TextField("Optional BLAST+ bin directory", text: $model.preferences.blastBinDirectory)
                            Button {
                                if let path = OpenPanel.chooseDirectory() {
                                    model.preferences.blastBinDirectory = path
                                    Task { await model.refreshTools() }
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                        }
                        Text("Leave this empty to search PATH plus common Homebrew and /Applications NCBI BLAST+ locations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Panel(title: "Suite Status", systemImage: "checklist") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Tool").bold()
                                Text("Status").bold()
                                Text("Path").bold()
                                Text("Version").bold()
                            }
                            ForEach(model.toolStatuses) { status in
                                GridRow {
                                    Text(status.name)
                                        .font(.system(.body, design: .monospaced))
                                    Label(status.isAvailable ? "Ready" : "Missing", systemImage: status.isAvailable ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                        .foregroundStyle(status.isAvailable ? .green : .red)
                                    Text(status.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(status.version)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    Panel(title: "Install Notes", systemImage: "info.circle") {
                        Text("Install NCBI BLAST+ from NCBI, Homebrew, or a managed lab image. LocalBlastStudio does not bundle NCBI binaries or databases; it orchestrates them locally so versioning and data provenance stay visible.")
                            .foregroundStyle(.secondary)
                        Link("NCBI BLAST+ command line manual", destination: URL(string: "https://www.ncbi.nlm.nih.gov/books/NBK279690/")!)
                        Link("NCBI BLAST database downloads", destination: URL(string: "https://www.ncbi.nlm.nih.gov/books/NBK569850/")!)
                    }
                }
                .padding(20)
            }
        }
    }
}

struct JobsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Job History", subtitle: "Recent local runs from this session.") { }
            List(model.jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.program.displayName)
                            .font(.headline)
                        Text(job.database)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(job.date, style: .time)
                        Label("Exit \(job.exitCode)", systemImage: job.exitCode == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(job.exitCode == 0 ? .green : .orange)
                    }
                    Text(job.outputPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(job.commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 6)
            }
            .overlay {
                if model.jobs.isEmpty {
                    ContentUnavailableView("No BLAST jobs yet", systemImage: "clock", description: Text("Run a search to populate this history."))
                }
            }
        }
    }
}

struct HeaderBar<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}

struct Panel<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum OpenPanel {
    @MainActor
    static func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    @MainActor
    static func chooseFile(allowedExtensions: [String]) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    @MainActor
    static func saveFile(defaultName: String) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
