import AppKit
import Darwin
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
    case sequence = "Sequence"
    case rnaSeq = "RNA-Seq"
    case results = "Results"
    case databases = "Databases"
    case tools = "Tools"

    static let topBarSections: [WorkspaceSection] = [.run, .sequence, .results, .rnaSeq, .databases, .tools]

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .run: "play.circle"
        case .sequence: "circle.hexagongrid"
        case .rnaSeq: "waveform.path.ecg"
        case .results: "doc.text.magnifyingglass"
        case .databases: "internaldrive"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

enum SequenceToolKind: String, CaseIterable, Identifiable {
    case translate = "Translate"
    case reverseComplement = "Reverse Complement"
    case backTranslate = "Back-translate"
    case protParam = "ProtParam"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .translate: "arrow.right.square"
        case .reverseComplement: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .backTranslate: "arrow.uturn.backward.square"
        case .protParam: "atom"
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

enum BlastJobKind: String, Codable, Hashable, Sendable {
    case blastSearch = "BLAST Search"
    case multipleAlignment = "Multiple Alignment"
    case rnaSeq = "RNA-Seq"
    case imported = "Imported Result"
}

enum BlastJobStatus: String, Hashable {
    case running = "Running"
    case finished = "Finished"
    case failed = "Failed"
    case killed = "Killed"
    case imported = "Imported"
}

struct BlastJobRecord: Identifiable, Hashable {
    var id = UUID()
    var kind: BlastJobKind = .blastSearch
    var title: String = ""
    var program: BlastProgram
    var database: String
    var outputPath: String
    var commandPreview: String
    var exitCode: Int32?
    var date: Date
    var status: BlastJobStatus
    var duration: TimeInterval?
    var outputBytes: Int64 = 0
    var hitCount: Int?
    var noHits = false
    var linkedGroup: String = ""
    var reservedThreads: Int = 1
    var reusableConfiguration: BlastSearchConfiguration?

    var displayTitle: String {
        title.isEmpty ? URL(fileURLWithPath: outputPath).lastPathComponent : title
    }

    static func == (lhs: BlastJobRecord, rhs: BlastJobRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct BlastRunReuseMetadata: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var kind: BlastJobKind
    var title: String
    var program: BlastProgram
    var database: String
    var commandPreview: String
    var date: Date
    var configuration: BlastSearchConfiguration
}

enum RNASeqOutputField: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case qseqid
    case sseqid
    case stitle
    case pident
    case length
    case qstart
    case qend
    case sstart
    case send
    case evalue
    case bitscore
    case qcovhsp
    case staxids

    var id: String { rawValue }

    var label: String {
        switch self {
        case .qseqid: "Read ID"
        case .sseqid: "Subject ID"
        case .stitle: "Subject title"
        case .pident: "Identity %"
        case .length: "Alignment length"
        case .qstart: "Query start"
        case .qend: "Query end"
        case .sstart: "Subject start"
        case .send: "Subject end"
        case .evalue: "E-value"
        case .bitscore: "Bit score"
        case .qcovhsp: "Query coverage"
        case .staxids: "Taxonomy IDs"
        }
    }

    static let defaults: Set<RNASeqOutputField> = [
        .qseqid, .sseqid, .stitle, .pident, .length,
        .qstart, .qend, .sstart, .send, .evalue, .bitscore
    ]
}

struct RNASeqAnalysisConfiguration: Codable, Equatable, Sendable {
    var inputFiles: [String] = []
    var program: BlastProgram = .blastn
    var databaseName: String = "refseq_rna"
    var outputPath: String = ""
    var blastnTask: String = "blastn"
    var evalue: String = "1e-5"
    var maxTargetSequences: String = "10"
    var numThreads: String = "4"
    var outputFields: Set<RNASeqOutputField> = RNASeqOutputField.defaults
    var rawArguments: String = ""
    var keepConvertedFasta: Bool = false

    var outputFieldString: String {
        RNASeqOutputField.allCases
            .filter { outputFields.contains($0) }
            .map(\.rawValue)
            .joined(separator: " ")
    }
}

enum RNASeqAnalysisStage: String, Codable, Sendable {
    case idle = "Idle"
    case preparing = "Preparing"
    case converting = "Converting FASTQ"
    case annotating = "Annotating"
    case finished = "Finished"
    case failed = "Failed"
}

enum SearchStage: String, Codable, Sendable {
    case idle = "Idle"
    case submitted = "Submitted"
    case searching = "Searching"
    case formatting = "Formatting"
    case finished = "Finished"
    case failed = "Failed"
}

struct SearchProgressSnapshot: Equatable, Sendable {
    var hasActivity = false
    var isActive = false
    var stage: SearchStage = .idle
    var status = "Idle"
    var program = ""
    var database = ""
    var queryLength: Int?
    var outputPath = ""
    var outputBytes: Int64 = 0
    var hitCount = 0
    var noHits = false
    var startedAt: Date?
    var lastUpdated: Date?

    var fractionComplete: Double? {
        switch stage {
        case .finished:
            1
        default:
            nil
        }
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        let endDate = isActive ? Date() : lastUpdated ?? Date()
        return endDate.timeIntervalSince(startedAt)
    }
}

struct RNASeqProgressSnapshot: Equatable, Sendable {
    var hasActivity = false
    var isActive = false
    var stage: RNASeqAnalysisStage = .idle
    var status = "Idle"
    var inputFileCount = 0
    var currentFileName = ""
    var totalInputBytes: Int64 = 0
    var processedInputBytes: Int64 = 0
    var convertedReads: Int64 = 0
    var outputBytes: Int64 = 0
    var isConversionProgressDeterminate = true
    var startedAt: Date?
    var lastUpdated: Date?

    var fractionComplete: Double? {
        switch stage {
        case .converting:
            guard isConversionProgressDeterminate else { return nil }
            guard totalInputBytes > 0 else { return nil }
            return min(max(Double(processedInputBytes) / Double(totalInputBytes), 0), 1)
        case .finished:
            return 1
        default:
            return nil
        }
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        let endDate = isActive ? Date() : lastUpdated ?? Date()
        return endDate.timeIntervalSince(startedAt)
    }
}

struct RNASeqConversionProgress: Sendable {
    var currentFilePath: String
    var totalInputBytes: Int64
    var processedInputBytes: Int64
    var convertedReads: Int64
    var outputBytes: Int64
    var isDeterminate: Bool
}

enum RNASeqAnalysisError: Error, LocalizedError {
    case noInputFiles
    case missingDatabase
    case missingOutputPath
    case noOutputFields
    case gzipUnavailable
    case gzipFailed(file: String, message: String)
    case cannotCreateOutputDirectory(String)
    case malformedFASTQ(file: String, line: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .noInputFiles:
            "Add at least one FASTQ file."
        case .missingDatabase:
            "Choose a database for RNA-Seq annotation."
        case .missingOutputPath:
            "Choose an RNA-Seq annotation output file."
        case .noOutputFields:
            "Select at least one output field."
        case .gzipUnavailable:
            "Could not find gzip, which is required to stream .fq.gz and .fastq.gz inputs."
        case .gzipFailed(let file, let message):
            "gzip failed while reading \(URL(fileURLWithPath: file).lastPathComponent): \(message)"
        case .cannotCreateOutputDirectory(let path):
            "Could not create output directory: \(path)"
        case .malformedFASTQ(let file, let line, let reason):
            "Malformed FASTQ in \(URL(fileURLWithPath: file).lastPathComponent) near line \(line): \(reason)"
        }
    }
}

struct ProcessResult: Sendable {
    var exitCode: Int32
    var output: String
}

struct DownloadProgressSnapshot: Equatable, Sendable {
    var hasActivity = false
    var isActive = false
    var databaseNames: [String] = []
    var startedAt: Date?
    var lastUpdated: Date?
    var expectedCompressedBytes: Int64?
    var observedCompressedBytes: Int64 = 0
    var addedCompressedBytes: Int64 = 0
    var archiveCount = 0
    var verifiedArchiveCount = 0
    var matchingFileCount = 0
    var activeDatabaseName = ""
    var activeFileName = ""
    var activeFileBytes: Int64 = 0
    var status = "Idle"

    var fractionComplete: Double? {
        guard let expectedCompressedBytes, expectedCompressedBytes > 0 else { return nil }
        return min(max(Double(observedCompressedBytes) / Double(expectedCompressedBytes), 0), 1)
    }

    var remainingCompressedBytes: Int64? {
        guard let expectedCompressedBytes else { return nil }
        return max(expectedCompressedBytes - observedCompressedBytes, 0)
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var bytesPerSecond: Double {
        guard elapsed > 0 else { return 0 }
        return Double(addedCompressedBytes) / elapsed
    }

    var estimatedTimeRemaining: TimeInterval? {
        guard let remainingCompressedBytes, bytesPerSecond > 1 else { return nil }
        return Double(remainingCompressedBytes) / bytesPerSecond
    }

    var estimatedFinishDate: Date? {
        guard let estimatedTimeRemaining else { return nil }
        return Date().addingTimeInterval(estimatedTimeRemaining)
    }
}

private struct DownloadDirectoryScan: Equatable, Sendable {
    var observedCompressedBytes: Int64 = 0
    var archiveCount = 0
    var verifiedArchiveCount = 0
    var matchingFileCount = 0
    var activeDatabaseName = ""
    var activeFileName = ""
    var activeFileBytes: Int64 = 0
    var lastModified: Date?
}

private struct DownloadArchiveInfo: Sendable {
    var databaseName: String
    var fileName: String
    var byteSize: Int64
    var modifiedAt: Date
}

private enum DownloadDirectoryScanner {
    static func scan(directory: String, databaseNames: [String]) -> DownloadDirectoryScan {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys)) else {
            return DownloadDirectoryScan()
        }

        let sortedNames = databaseNames.sorted { $0.count > $1.count }
        var archives: [DownloadArchiveInfo] = []
        var md5Files = Set<String>()
        var matchingFileCount = 0
        var lastModified: Date?

        for fileURL in urls {
            let fileName = fileURL.lastPathComponent
            guard let databaseName = matchingDatabaseName(for: fileName, databaseNames: sortedNames) else {
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: keys)
            guard values?.isRegularFile != false else { continue }
            matchingFileCount += 1

            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if lastModified == nil || modifiedAt > lastModified! {
                lastModified = modifiedAt
            }

            if fileName.hasSuffix(".tar.gz") {
                archives.append(
                    DownloadArchiveInfo(
                        databaseName: databaseName,
                        fileName: fileName,
                        byteSize: Int64(values?.fileSize ?? 0),
                        modifiedAt: modifiedAt
                    )
                )
            } else if fileName.hasSuffix(".tar.gz.md5") {
                md5Files.insert(String(fileName.dropLast(4)))
            }
        }

        let activeArchive = archives
            .filter { !md5Files.contains($0.fileName) }
            .max { $0.modifiedAt < $1.modifiedAt }
            ?? archives.max { $0.modifiedAt < $1.modifiedAt }

        return DownloadDirectoryScan(
            observedCompressedBytes: archives.reduce(Int64(0)) { $0 + $1.byteSize },
            archiveCount: archives.count,
            verifiedArchiveCount: archives.filter { md5Files.contains($0.fileName) }.count,
            matchingFileCount: matchingFileCount,
            activeDatabaseName: activeArchive?.databaseName ?? "",
            activeFileName: activeArchive?.fileName ?? "",
            activeFileBytes: activeArchive?.byteSize ?? 0,
            lastModified: lastModified
        )
    }

    private static func matchingDatabaseName(for fileName: String, databaseNames: [String]) -> String? {
        databaseNames.first { name in
            fileName == name || fileName.hasPrefix("\(name).")
        }
    }
}

private struct BlastDatabaseMetadataRecord: Decodable {
    var dbname: String
    var bytesTotal: Int64?
    var files: [String]?

    enum CodingKeys: String, CodingKey {
        case dbname
        case bytesTotal = "bytes-total"
        case files
    }
}

private let clusteredNRMetadataURL = URL(
    string: "https://ftp.ncbi.nlm.nih.gov/blast/db/v5/v5/experimental/nr_cluster_seq-prot-metadata.json"
)

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
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool):
            if tool == MultipleSequenceAlignmentCommandBuilder.executableName {
                return "Could not find Clustal Omega (clustalo). Install Clustal Omega, then set the tool binary directory in Tools to the folder containing clustalo or make sure it is on PATH."
            }
            return "Could not find \(tool). Set the tool binary directory in Tools."
        case .cannotCreateDirectory(let path):
            return "Could not create directory: \(path)"
        case .emptyDownloadSelection:
            return "Select at least one database to download."
        case .processFailed(let message):
            return message
        }
    }
}

final class TrackedProcessHandle: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let currentDirectoryURL: URL?
    private let lock = NSLock()
    private var process: Process?
    private var shouldTerminate = false

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }

    func runAndWait() throws -> ProcessResult {
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

        lock.lock()
        self.process = process
        let terminateImmediately = shouldTerminate
        lock.unlock()

        try process.run()
        if terminateImmediately {
            terminate()
        }
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        let remaining = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            output.append(remaining)
        }

        lock.lock()
        self.process = nil
        lock.unlock()

        return ProcessResult(exitCode: process.terminationStatus, output: output.stringValue())
    }

    func terminate() {
        lock.lock()
        shouldTerminate = true
        let activeProcess = process
        lock.unlock()

        guard let activeProcess, activeProcess.isRunning else { return }
        let pid = activeProcess.processIdentifier
        Darwin.kill(pid, SIGTERM)

        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.forceKillIfStillRunning(processID: pid)
        }
    }

    private func forceKillIfStillRunning(processID: Int32) {
        lock.lock()
        let activeProcess = process
        lock.unlock()

        guard let activeProcess,
              activeProcess.processIdentifier == processID,
              activeProcess.isRunning else { return }
        Darwin.kill(processID, SIGKILL)
    }
}

enum ProcessClient {
    static let searchTools = BlastProgram.allCases.map(\.executableName)
    static let utilityTools = [
        "makeblastdb", "blastdbcmd", "update_blastdb.pl", "dustmasker", "segmasker",
        "windowmasker", "makeprofiledb", "makembindex", "convert2blastmask", "gzip", "clustalo"
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

private final class FastqLineReader {
    private let handle: FileHandle
    private let closesHandle: Bool
    private var buffer = Data()
    private var reachedEnd = false

    var bytesRead: Int64 = 0

    init(url: URL) throws {
        self.handle = try FileHandle(forReadingFrom: url)
        self.closesHandle = true
    }

    init(handle: FileHandle, closesHandle: Bool = true) {
        self.handle = handle
        self.closesHandle = closesHandle
    }

    deinit {
        if closesHandle {
            try? handle.close()
        }
    }

    func nextLine() throws -> Data? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newlineIndex]).trimmingTrailingCarriageReturn()
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                return line
            }

            if reachedEnd {
                guard !buffer.isEmpty else { return nil }
                let line = buffer.trimmingTrailingCarriageReturn()
                buffer.removeAll(keepingCapacity: false)
                return line
            }

            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                reachedEnd = true
            } else {
                bytesRead += Int64(chunk.count)
                buffer.append(chunk)
            }
        }
    }
}

private final class GzipFastqLineReader {
    private let filePath: String
    private let process: Process
    private let standardErrorPipe = Pipe()
    private let standardError = PipeOutputBuffer()
    private let lineReader: FastqLineReader

    var bytesRead: Int64 { lineReader.bytesRead }

    init(filePath: String, gzipURL: URL) throws {
        self.filePath = filePath
        self.process = Process()
        let outputPipe = Pipe()
        process.executableURL = gzipURL
        process.arguments = ["-dc", filePath]
        process.standardOutput = outputPipe
        process.standardError = standardErrorPipe
        lineReader = FastqLineReader(handle: outputPipe.fileHandleForReading)
        standardErrorPipe.fileHandleForReading.readabilityHandler = { [standardError] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            standardError.append(data)
        }
        try process.run()
    }

    deinit {
        standardErrorPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    func nextLine() throws -> Data? {
        try lineReader.nextLine()
    }

    func finish() throws {
        process.waitUntilExit()
        standardErrorPipe.fileHandleForReading.readabilityHandler = nil
        let remaining = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            standardError.append(remaining)
        }
        guard process.terminationStatus == 0 else {
            let message = standardError.stringValue().trimmingCharacters(in: .whitespacesAndNewlines)
            throw RNASeqAnalysisError.gzipFailed(
                file: filePath,
                message: message.isEmpty ? "exit code \(process.terminationStatus)" : message
            )
        }
    }
}

private enum RNASeqFastqConverter {
    static func convert(
        inputFiles: [String],
        outputURL: URL,
        gzipURL: URL?,
        progress: @escaping @Sendable (RNASeqConversionProgress) -> Void
    ) throws -> Int64 {
        let fileManager = FileManager.default
        let usesGzip = inputFiles.contains(where: isGzipFASTQ)
        let totalBytes = inputFiles.reduce(Int64(0)) { total, path in
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }

        fileManager.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        var processedBeforeCurrentFile: Int64 = 0
        var convertedReads: Int64 = 0
        var fastaOutputBytes: Int64 = 0
        var lastProgressBytes: Int64 = -1

        for inputFile in inputFiles {
            let inputURL = URL(fileURLWithPath: inputFile)
            let fileSize = (try? fileManager.attributesOfItem(atPath: inputFile)[.size] as? NSNumber)?.int64Value ?? 0
            let gzipReader: GzipFastqLineReader?
            let plainReader: FastqLineReader?
            if isGzipFASTQ(inputFile) {
                guard let gzipURL else { throw RNASeqAnalysisError.gzipUnavailable }
                gzipReader = try GzipFastqLineReader(filePath: inputFile, gzipURL: gzipURL)
                plainReader = nil
            } else {
                gzipReader = nil
                plainReader = try FastqLineReader(url: inputURL)
            }
            var recordIndex = 0

            func nextLine() throws -> Data? {
                if let gzipReader {
                    return try gzipReader.nextLine()
                }
                return try plainReader?.nextLine()
            }

            func readerBytesRead() -> Int64 {
                if let gzipReader {
                    return gzipReader.bytesRead
                }
                return plainReader?.bytesRead ?? 0
            }

            while let headerLine = try nextLine() {
                recordIndex += 1
                let sequenceLineNumber = (recordIndex - 1) * 4 + 2
                guard let sequenceLine = try nextLine() else {
                    throw RNASeqAnalysisError.malformedFASTQ(file: inputFile, line: sequenceLineNumber, reason: "missing sequence line")
                }
                guard let plusLine = try nextLine() else {
                    throw RNASeqAnalysisError.malformedFASTQ(file: inputFile, line: sequenceLineNumber + 1, reason: "missing plus line")
                }
                guard try nextLine() != nil else {
                    throw RNASeqAnalysisError.malformedFASTQ(file: inputFile, line: sequenceLineNumber + 2, reason: "missing quality line")
                }
                guard headerLine.first == 64 else {
                    throw RNASeqAnalysisError.malformedFASTQ(file: inputFile, line: sequenceLineNumber - 1, reason: "header does not start with @")
                }
                guard plusLine.first == 43 else {
                    throw RNASeqAnalysisError.malformedFASTQ(file: inputFile, line: sequenceLineNumber + 1, reason: "separator does not start with +")
                }

                var header = headerLine
                header.removeFirst()
                if header.isEmpty {
                    header = Data("read_\(convertedReads + 1)".utf8)
                }

                var fastaRecord = Data(capacity: header.count + sequenceLine.count + 4)
                fastaRecord.append(62)
                fastaRecord.append(header)
                fastaRecord.append(10)
                fastaRecord.append(sequenceLine)
                fastaRecord.append(10)
                try outputHandle.write(contentsOf: fastaRecord)
                fastaOutputBytes += Int64(fastaRecord.count)

                convertedReads += 1
                let processedBytes = usesGzip
                    ? min(processedBeforeCurrentFile, totalBytes)
                    : min(processedBeforeCurrentFile + readerBytesRead(), totalBytes)
                let progressBytes = usesGzip ? fastaOutputBytes : processedBytes
                if lastProgressBytes < 0 || progressBytes - lastProgressBytes >= 64 * 1_024 * 1_024 {
                    lastProgressBytes = progressBytes
                    let statusProcessedBytes = isGzipFASTQ(inputFile) ? processedBeforeCurrentFile : processedBytes
                    progress(
                        RNASeqConversionProgress(
                            currentFilePath: inputFile,
                            totalInputBytes: totalBytes,
                            processedInputBytes: statusProcessedBytes,
                            convertedReads: convertedReads,
                            outputBytes: fastaOutputBytes,
                            isDeterminate: !usesGzip
                        )
                    )
                }
            }

            try gzipReader?.finish()
            processedBeforeCurrentFile += fileSize
            progress(
                RNASeqConversionProgress(
                    currentFilePath: inputFile,
                    totalInputBytes: totalBytes,
                    processedInputBytes: min(processedBeforeCurrentFile, totalBytes),
                    convertedReads: convertedReads,
                    outputBytes: fastaOutputBytes,
                    isDeterminate: !usesGzip
                )
            )
        }

        return convertedReads
    }

    static func isGzipFASTQ(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".fq.gz") || lower.hasSuffix(".fastq.gz")
    }
}

private extension Data {
    func trimmingTrailingCarriageReturn() -> Data {
        guard last == 13 else { return self }
        return Data(dropLast())
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: WorkspaceSection = .run
    @Published var sequenceInput: String = ""
    @Published var sequenceTool: SequenceToolKind = .translate
    @Published var sequenceGeneticCodeID: Int = 1
    @Published var sequenceCodonUsageID: String = "human"
    @Published var preferences: BlastPreferences {
        didSet {
            preferences.save()
            configuration.databaseDirectory = preferences.databaseDirectory
            if configuration.igBlast.additionalDatabaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.igBlast.additionalDatabaseDirectory = preferences.databaseDirectory
            }
            ensureDefaultOutputPath()
            ensureDefaultRNASeqOutputPath()
            updateCommandPreview()
            updateRNASeqCommandPreview()
        }
    }
    @Published var configuration: BlastSearchConfiguration {
        didSet { updateCommandPreview() }
    }
    @Published var rnaSeqConfiguration: RNASeqAnalysisConfiguration {
        didSet { updateRNASeqCommandPreview() }
    }
    @Published var databaseCatalog: [BlastDatabaseEntry] = FallbackDatabaseCatalog.entries
    @Published var installedDatabaseSummary = InstalledDatabaseSummary()
    @Published var selectedDatabaseNames: Set<String> = []
    @Published var databaseSearchText = ""
    @Published var databaseLog = ""
    @Published var runLog = ""
    @Published var rnaSeqLog = ""
    @Published var helpText = ""
    @Published var commandPreview = ""
    @Published var rnaSeqCommandPreview = ""
    @Published var isRunningSearch = false
    @Published var isRunningRNASeq = false
    @Published var activeSearchThreadCount = 0
    @Published var isRefreshingCatalog = false
    @Published var isDownloading = false
    @Published var searchProgress = SearchProgressSnapshot()
    @Published var blastResultReport: BlastResultReport?
    @Published var downloadProgress = DownloadProgressSnapshot()
    @Published var rnaSeqProgress = RNASeqProgressSnapshot()
    @Published var toolStatuses: [ToolStatus] = []
    @Published var jobs: [BlastJobRecord] = []
    @Published var selectedJobID: BlastJobRecord.ID?
    @Published var selectedJobIDs: Set<BlastJobRecord.ID> = []
    @Published var selectedResultReport: BlastResultReport?
    @Published var resultLog = ""
    @Published var customDatabaseInput = ""
    @Published var customDatabaseName = ""
    @Published var customDatabaseType = "nucl"
    @Published var customDatabaseParseSeqIDs = true
    @Published var structureInputPath = ""
    @Published var structureChains: [ProteinChainSequence] = []
    @Published var structureImportLog = ""

    private var downloadProgressTask: Task<Void, Never>?
    private var downloadProgressBaseline = DownloadDirectoryScan()
    private var downloadProgressDirectory = ""
    private var downloadProgressNames: [String] = []
    private var searchProgressTasks: [BlastJobRecord.ID: Task<Void, Never>] = [:]
    private var activeSearchProgressJobID: BlastJobRecord.ID?
    private var runningJobHandles: [BlastJobRecord.ID: TrackedProcessHandle] = [:]
    private var runningJobThreads: [BlastJobRecord.ID: Int] = [:]
    private var killedJobIDs: Set<BlastJobRecord.ID> = []
    private var resultSelectionAnchorID: BlastJobRecord.ID?
    private var rnaSeqProgressTask: Task<Void, Never>?
    private let automaticResultExtensions: Set<String> = ["txt", "tsv", "out", "aln", "clu"]
    private let maxAutoLoadedResultBytes: Int64 = 100 * 1_024 * 1_024

    var selectedResultCount: Int {
        selectedResultIDsForAction.count
    }

    private var selectedResultIDsForAction: Set<BlastJobRecord.ID> {
        let liveIDs = Set(jobs.map(\.id))
        let liveSelection = selectedJobIDs.intersection(liveIDs)
        if !liveSelection.isEmpty {
            return liveSelection
        }
        if let selectedJobID, liveIDs.contains(selectedJobID) {
            return [selectedJobID]
        }
        return []
    }

    init() {
        let preferences = BlastPreferences.load()
        self.preferences = preferences
        var searchConfiguration = BlastSearchConfiguration(
            program: .blastn,
            databaseName: RecommendedBlastDatabases.blastn,
            databaseDirectory: preferences.databaseDirectory
        )
        searchConfiguration.igBlast = Self.defaultIgBlastConfiguration(preferences: preferences)
        self.configuration = searchConfiguration
        self.rnaSeqConfiguration = RNASeqAnalysisConfiguration(
            databaseName: "refseq_rna",
            outputPath: URL(fileURLWithPath: preferences.outputDirectory)
                .appendingPathComponent("rnaseq-annotations.tsv")
                .path
        )
        ensureDefaultOutputPath()
        ensureDefaultRNASeqOutputPath()
        markInstalledDatabases()
        updateCommandPreview()
        updateRNASeqCommandPreview()
    }

    func bootstrap() async {
        ensureWorkingDirectories()
        await refreshTools(checkVersions: false)
        markInstalledDatabases()
        refreshResultFiles()
        databaseLog = "Offline startup complete. Local databases and tool paths were scanned without launching external tools; use Refresh Catalog, Download Selected, or Tools > Recheck when you want to run network or tool checks."
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
        _ = try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: Self.defaultIgBlastDatabaseDirectory(), isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func ensureDefaultOutputPath() {
        if configuration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration.outputPath = defaultSearchOutputPath(for: configuration)
        }
    }

    func ensureDefaultRNASeqOutputPath() {
        if rnaSeqConfiguration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rnaSeqConfiguration.outputPath = URL(fileURLWithPath: preferences.outputDirectory)
                .appendingPathComponent("rnaseq-annotations.tsv")
                .path
        }
    }

    private static func defaultIgBlastConfiguration(preferences: BlastPreferences) -> IgBlastConfiguration {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let igDataDirectory = firstExistingDirectory([
            "/opt/homebrew/anaconda3/share/igblast",
            "/opt/homebrew/miniconda3/share/igblast",
            "/opt/homebrew/miniforge3/share/igblast",
            "/usr/local/anaconda3/share/igblast",
            "/usr/local/miniconda3/share/igblast",
            "\(homeDirectory)/anaconda3/share/igblast",
            "\(homeDirectory)/miniconda3/share/igblast",
            "\(homeDirectory)/miniforge3/share/igblast"
        ])
        let databaseDirectory = defaultIgBlastDatabaseDirectory()
        return IgBlastConfiguration(
            organism: "human",
            sequenceType: "Ig",
            igDataDirectory: igDataDirectory,
            germlineVDatabase: blastDatabasePrefixIfPresent(
                directory: databaseDirectory,
                name: "airr_c_human_ig.V"
            ),
            germlineDDatabase: blastDatabasePrefixIfPresent(
                directory: databaseDirectory,
                name: "airr_c_human_igh.D"
            ),
            germlineJDatabase: blastDatabasePrefixIfPresent(
                directory: databaseDirectory,
                name: "airr_c_human_ig.J"
            ),
            cRegionDatabase: blastDatabasePrefixIfPresent(
                directory: databaseDirectory,
                name: "ncbi_human_c_genes"
            ),
            auxiliaryDataPath: firstExistingFile([
                "\(igDataDirectory)/optional_file/human_gl.aux"
            ]),
            additionalDatabaseName: "",
            additionalDatabaseDirectory: preferences.databaseDirectory
        )
    }

    private static func defaultIgBlastDatabaseDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("LocalBlastStudio-IgBlastDatabases", isDirectory: true)
            .path
    }

    private static func blastDatabasePrefixIfPresent(directory: String, name: String) -> String {
        guard !directory.isEmpty else { return "" }
        let prefix = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
        let knownExtensions = ["nhr", "nin", "nsq", "phr", "pin", "psq"]
        let hasDatabaseFiles = knownExtensions.contains { extensionName in
            FileManager.default.fileExists(atPath: "\(prefix).\(extensionName)")
        }
        return hasDatabaseFiles ? prefix : ""
    }

    private static func firstExistingDirectory(_ paths: [String]) -> String {
        paths.first { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        } ?? ""
    }

    private static func firstExistingFile(_ paths: [String]) -> String {
        paths.first { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        } ?? ""
    }

    private func defaultBlastOutputPath(for program: BlastProgram, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "blast-\(program.rawValue)-\(formatter.string(from: date)).txt"
        return URL(fileURLWithPath: preferences.outputDirectory)
            .appendingPathComponent(filename)
            .path
    }

    private func defaultSearchOutputPath(for configuration: BlastSearchConfiguration, date: Date = Date()) -> String {
        guard configuration.alignMultipleSequences else {
            return defaultBlastOutputPath(for: configuration.program, date: date)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "alignment-\(configuration.program.rawValue)-\(formatter.string(from: date)).aln"
        return URL(fileURLWithPath: preferences.outputDirectory)
            .appendingPathComponent(filename)
            .path
    }

    private func reusableOutputPath(for configuration: BlastSearchConfiguration) -> String {
        uniqueOutputPath(defaultSearchOutputPath(for: configuration))
    }

    func setProgram(_ program: BlastProgram) {
        configuration.program = program
        configuration.resetOptionsForProgram()
        if program.isIgBlast {
            configuration.alignTwoSequences = false
            configuration.alignMultipleSequences = false
            if configuration.igBlast.additionalDatabaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuration.igBlast.additionalDatabaseDirectory = preferences.databaseDirectory
            }
        } else {
            if !program.supportsMultipleSequenceAlignment {
                configuration.alignMultipleSequences = false
            }
            if let recommendedDatabaseName = program.recommendedDatabaseName {
                configuration.databaseName = recommendedDatabaseName
            } else if let matchingDatabase = databaseCatalog.first(where: { $0.kind == program.databaseKind && $0.isInstalled }) ??
                databaseCatalog.first(where: { $0.kind == program.databaseKind }) {
                configuration.databaseName = matchingDatabase.name
            } else {
                configuration.databaseName = ""
            }
        }
        refreshStructureQueryTextForSelectedProgram()
        ensureDefaultOutputPath()
        updateCommandPreview()
    }

    // MARK: - Sequence tools

    func openSequenceTool(_ kind: SequenceToolKind, with text: String) {
        sequenceInput = text
        sequenceTool = kind
        section = .sequence
    }

    func useSequenceAsQuery(_ text: String) {
        configuration.queryFilePath = ""
        configuration.queryText = text
        section = .run
    }

    func setPairwiseAlignmentEnabled(_ isEnabled: Bool) {
        configuration.alignTwoSequences = isEnabled
        if isEnabled {
            configuration.alignMultipleSequences = false
        }
        updateCommandPreview()
    }

    func setMultipleSequenceAlignmentEnabled(_ isEnabled: Bool) {
        guard !isEnabled || configuration.program.supportsMultipleSequenceAlignment else {
            configuration.alignMultipleSequences = false
            return
        }
        configuration.alignMultipleSequences = isEnabled
        if isEnabled {
            configuration.alignTwoSequences = false
            if configuration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                URL(fileURLWithPath: configuration.outputPath).pathExtension.lowercased() == "txt" {
                configuration.outputPath = defaultSearchOutputPath(for: configuration)
            }
        }
        updateCommandPreview()
    }

    var logicalSearchThreadCount: Int {
        max(ProcessInfo.processInfo.activeProcessorCount, 1)
    }

    var availableSearchThreadCount: Int {
        max(logicalSearchThreadCount - activeSearchThreadCount, 0)
    }

    var currentSearchThreadRequest: Int {
        reservedThreadCount(for: configuration)
    }

    var canStartSearch: Bool {
        canReserveSearchThreads(currentSearchThreadRequest)
    }

    var searchCapacityLabel: String {
        let active = activeSearchThreadCount.formatted()
        let total = logicalSearchThreadCount.formatted()
        let request = currentSearchThreadRequest.formatted()
        if canStartSearch {
            return "\(active)/\(total) CPU threads active; next search reserves \(request)."
        }
        return "\(active)/\(total) CPU threads active; next search needs \(request), so stop a job or lower CPU threads."
    }

    private func reservedThreadCount(for configuration: BlastSearchConfiguration) -> Int {
        if configuration.alignMultipleSequences {
            return 1
        }
        let rawValue = configuration.optionValues["numThreads"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requested = Int(rawValue).map { max($0, 1) } ?? 1
        return min(requested, logicalSearchThreadCount)
    }

    private func canReserveSearchThreads(_ count: Int) -> Bool {
        activeSearchThreadCount + max(count, 1) <= logicalSearchThreadCount
    }

    var supportsStructureQueryImport: Bool {
        configuration.program == .blastp || configuration.program == .igblastp
    }

    func importStructureFile(_ path: String) {
        do {
            let chains = try ProteinStructureSequenceExtractor.extract(fromFile: path)
            structureInputPath = path
            structureChains = chains
            refreshStructureQueryTextForSelectedProgram()
            let chainSummary = chains
                .map { "\($0.chainID) (\($0.sequence.count.formatted()) aa)" }
                .joined(separator: ", ")
            structureImportLog = "Loaded \(URL(fileURLWithPath: path).lastPathComponent): \(chainSummary)"
            updateCommandPreview()
        } catch {
            structureImportLog = error.localizedDescription
        }
    }

    func clearStructureFile() {
        structureInputPath = ""
        structureChains = []
        structureImportLog = ""
        if supportsStructureQueryImport {
            configuration.queryText = ""
        }
        updateCommandPreview()
    }

    private func refreshStructureQueryTextForSelectedProgram() {
        guard supportsStructureQueryImport, !structureChains.isEmpty else { return }
        configuration.queryFilePath = ""
        switch configuration.program {
        case .igblastp:
            let selected = igBlastPStructureChains()
            configuration.queryText = selected
                .map { chain, label in chain.fastaRecord(label: label) }
                .joined()
        case .blastp:
            configuration.queryText = structureChains
                .map { $0.fastaRecord() }
                .joined()
        default:
            break
        }
    }

    private func igBlastPStructureChains() -> [(chain: ProteinChainSequence, label: String)] {
        let chainA = structureChains.first { $0.chainID.caseInsensitiveCompare("A") == .orderedSame }
        let chainB = structureChains.first { $0.chainID.caseInsensitiveCompare("B") == .orderedSame }
        return [
            chainA.map { ($0, "LC") },
            chainB.map { ($0, "HC") }
        ].compactMap { $0 }
    }

    func setRNASeqProgram(_ program: BlastProgram) {
        rnaSeqConfiguration.program = program
        rnaSeqConfiguration.databaseName = preferredRNASeqDatabaseName(for: program)
        updateRNASeqCommandPreview()
    }

    func updateCommandPreview() {
        if supportsStructureQueryImport, !structureChains.isEmpty, !configuration.alignMultipleSequences {
            switch configuration.program {
            case .igblastp:
                let chains = igBlastPStructureChains()
                if chains.isEmpty {
                    commandPreview = "Drop a PDB/mmCIF with chain A (LC) and/or chain B (HC) for IgBLASTP."
                } else {
                    let chainLabels = chains.map { "\($0.chain.chainID) as \($0.label)" }.joined(separator: ", ")
                    commandPreview = "Structure batch: IgBLASTP will search \(chainLabels) as linked chain jobs."
                }
                return
            case .blastp:
                commandPreview = "Structure batch: BLASTP will search \(structureChains.count.formatted()) chain(s) as linked jobs."
                return
            default:
                break
            }
        }

        let queryPath = configuration.queryFilePath.isEmpty ? "<pasted-query.fasta>" : configuration.queryFilePath
        let subjectPath = configuration.subjectFilePath.isEmpty ? "<subject.fasta>" : configuration.subjectFilePath
        do {
            if configuration.alignMultipleSequences {
                commandPreview = try MultipleSequenceAlignmentCommandBuilder.build(
                    configuration: configuration,
                    inputPath: queryPath
                ).preview
            } else {
                commandPreview = try BlastCommandBuilder.build(
                    configuration: configuration,
                    queryPath: queryPath,
                    subjectPath: subjectPath
                ).preview
            }
        } catch {
            commandPreview = error.localizedDescription
        }
    }

    func updateRNASeqCommandPreview() {
        let queryPath = rnaSeqConfiguration.inputFiles.isEmpty ? "<converted-rnaseq.fasta>" : "<streamed-fastq-as-fasta>"
        do {
            rnaSeqCommandPreview = try buildRNASeqBlastCommand(queryPath: queryPath).preview
        } catch {
            rnaSeqCommandPreview = error.localizedDescription
        }
    }

    func addRNASeqInputFiles(_ paths: [String]) {
        let existing = Set(rnaSeqConfiguration.inputFiles)
        let additions = paths.filter { !existing.contains($0) }
        rnaSeqConfiguration.inputFiles.append(contentsOf: additions)
    }

    func removeRNASeqInputFile(_ path: String) {
        rnaSeqConfiguration.inputFiles.removeAll { $0 == path }
    }

    func clearRNASeqInputFiles() {
        rnaSeqConfiguration.inputFiles.removeAll()
    }

    private func preferredRNASeqDatabaseName(for program: BlastProgram) -> String {
        let preferredNames: [String]
        switch program {
        case .blastn:
            preferredNames = ["refseq_rna", "tsa_nt", "est", RecommendedBlastDatabases.blastn]
        case .blastx:
            preferredNames = ["refseq_protein", RecommendedBlastDatabases.blastp, "nr", "swissprot"]
        default:
            preferredNames = [program.recommendedDatabaseName].compactMap { $0 }
        }

        let matchingKind = databaseCatalog
            .filter { $0.kind == program.databaseKind }
            .sorted(by: databaseEntrySort)
        for name in preferredNames where matchingKind.contains(where: { $0.name == name }) {
            return name
        }
        return matchingKind.first?.name ?? preferredNames.first ?? ""
    }

    private func buildRNASeqBlastCommand(queryPath: String) throws -> BlastCommand {
        guard !rnaSeqConfiguration.inputFiles.isEmpty || queryPath.hasPrefix("<") else {
            throw RNASeqAnalysisError.noInputFiles
        }
        guard !rnaSeqConfiguration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RNASeqAnalysisError.missingDatabase
        }
        guard !rnaSeqConfiguration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RNASeqAnalysisError.missingOutputPath
        }
        guard !rnaSeqConfiguration.outputFieldString.isEmpty else {
            throw RNASeqAnalysisError.noOutputFields
        }

        var optionValues = BlastParameterCatalog.defaultValues(for: rnaSeqConfiguration.program)
        optionValues["evalue"] = rnaSeqConfiguration.evalue
        optionValues["maxTargetSeqs"] = rnaSeqConfiguration.maxTargetSequences
        optionValues["numThreads"] = rnaSeqConfiguration.numThreads
        optionValues["outfmt"] = "6 \(rnaSeqConfiguration.outputFieldString)"
        if rnaSeqConfiguration.program == .blastn {
            optionValues["task"] = rnaSeqConfiguration.blastnTask
        }

        let blastConfiguration = BlastSearchConfiguration(
            program: rnaSeqConfiguration.program,
            databaseName: rnaSeqConfiguration.databaseName,
            databaseDirectory: preferences.databaseDirectory,
            outputPath: rnaSeqConfiguration.outputPath,
            optionValues: optionValues,
            rawArguments: rnaSeqConfiguration.rawArguments
        )
        return try BlastCommandBuilder.build(configuration: blastConfiguration, queryPath: queryPath)
    }

    func refreshTools(checkVersions: Bool = true) async {
        let tools = ProcessClient.searchTools + ProcessClient.utilityTools
        var statuses: [ToolStatus] = []
        for tool in tools {
            guard let url = ProcessClient.resolveExecutable(named: tool, preferences: preferences) else {
                statuses.append(ToolStatus(name: tool, path: "Not found", version: "", isAvailable: false))
                continue
            }
            let version: String
            if checkVersions {
                version = await Task.detached {
                    if let result = try? ProcessClient.runSync(executableURL: url, arguments: ["-version"]),
                       result.exitCode == 0,
                       !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return result.output
                    }
                    return (try? ProcessClient.runSync(executableURL: url, arguments: ["--version"]).output) ?? ""
                }.value
            } else {
                version = "Version check deferred"
            }
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
                databaseCatalog = BlastDatabaseParser.includingRecommended(parsed)
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
        databaseCatalog = BlastDatabaseParser.markInstalled(
            BlastDatabaseParser.includingRecommended(databaseCatalog),
            installedNames: summary.names
        )
    }

    func selectRecommendedStarterDatabases() {
        for name in RecommendedBlastDatabases.starterNames {
            selectedDatabaseNames.insert(name)
        }
    }

    func downloadSelectedDatabases() async {
        guard !selectedDatabaseNames.isEmpty else {
            databaseLog = LocalBlastError.emptyDownloadSelection.localizedDescription
            return
        }

        ensureWorkingDirectories()
        let names = selectedDatabaseNames.sorted()
        let directDownloadNames = names.filter { $0 == RecommendedBlastDatabases.blastp }
        let updaterNames = names.filter { !directDownloadNames.contains($0) }
        let updater = ProcessClient.resolveExecutable(named: "update_blastdb.pl", preferences: preferences)
        if !updaterNames.isEmpty, updater == nil {
            databaseLog = LocalBlastError.toolMissing("update_blastdb.pl").localizedDescription
            return
        }

        let databaseDirectory = preferences.databaseDirectory
        databaseLog = "Preparing download: \(names.joined(separator: ", "))"
        let expectedCompressedBytes = await fetchExpectedCompressedBytes(for: names)

        isDownloading = true
        startDownloadProgress(
            names: names,
            directory: databaseDirectory,
            expectedCompressedBytes: expectedCompressedBytes
        )
        defer { isDownloading = false }

        databaseLog = "Starting download: \(names.joined(separator: ", "))"

        do {
            var outputs: [String] = []
            var exitCode: Int32 = 0

            if !updaterNames.isEmpty, let updater {
                let result = try await runUpdateBlastDatabaseDownload(
                    updater: updater,
                    names: updaterNames,
                    databaseDirectory: databaseDirectory
                )
                exitCode = result.exitCode
                if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    outputs.append(result.output)
                }
            }

            if directDownloadNames.contains(RecommendedBlastDatabases.blastp), exitCode == 0 {
                databaseLog = "Downloading ClusteredNR directly from NCBI experimental metadata."
                let result = try await downloadClusteredNRDatabase(
                    databaseDirectory: databaseDirectory,
                    decompress: preferences.decompressDownloads
                )
                exitCode = result.exitCode
                if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    outputs.append(result.output)
                }
            }

            markInstalledDatabases()
            databaseLog = outputs.isEmpty
                ? "Download finished with exit code \(exitCode)."
                : outputs.joined(separator: "\n\n")
            finishDownloadProgress(exitCode: exitCode)
        } catch {
            databaseLog = "Download failed: \(error.localizedDescription)"
            finishDownloadProgress(exitCode: nil, failureMessage: error.localizedDescription)
        }
    }

    private func runUpdateBlastDatabaseDownload(
        updater: URL,
        names: [String],
        databaseDirectory: String
    ) async throws -> ProcessResult {
        var arguments: [String] = []
        if preferences.decompressDownloads {
            arguments.append("--decompress")
        }
        if preferences.useVersion5Databases {
            arguments.append(contentsOf: ["--blastdb_version", "5"])
        }
        arguments.append(contentsOf: names)

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
            return try await Task.detached {
                try ProcessClient.runSync(
                    executableURL: updater,
                    arguments: fallbackArguments,
                    currentDirectoryURL: URL(fileURLWithPath: databaseDirectory)
                )
            }.value
        }

        return result
    }

    private func downloadClusteredNRDatabase(databaseDirectory: String, decompress: Bool) async throws -> ProcessResult {
        guard let clusteredNRMetadataURL else {
            return ProcessResult(exitCode: 1, output: "ClusteredNR metadata URL is not configured.")
        }
        guard let curl = ProcessClient.resolveExecutable(named: "curl", preferences: preferences) else {
            return ProcessResult(exitCode: 1, output: LocalBlastError.toolMissing("curl").localizedDescription)
        }
        guard let tar = ProcessClient.resolveExecutable(named: "tar", preferences: preferences) else {
            return ProcessResult(exitCode: 1, output: LocalBlastError.toolMissing("tar").localizedDescription)
        }

        let (data, _) = try await URLSession.shared.data(from: clusteredNRMetadataURL)
        let metadata = try JSONDecoder().decode(BlastDatabaseMetadataRecord.self, from: data)
        let fileURLs = (metadata.files ?? [])
            .map { $0.replacingOccurrences(of: "ftp://", with: "https://") }
            .compactMap { URL(string: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard metadata.dbname == RecommendedBlastDatabases.blastp, !fileURLs.isEmpty else {
            return ProcessResult(exitCode: 1, output: "ClusteredNR metadata did not include downloadable archives.")
        }

        var completedArchives = 0
        for fileURL in fileURLs {
            let archiveName = fileURL.lastPathComponent
            let archiveResult = try await Task.detached {
                try ProcessClient.runSync(
                    executableURL: curl,
                    arguments: ["-fL", "-C", "-", "-O", fileURL.absoluteString],
                    currentDirectoryURL: URL(fileURLWithPath: databaseDirectory, isDirectory: true)
                )
            }.value
            guard archiveResult.exitCode == 0 else {
                return ProcessResult(exitCode: archiveResult.exitCode, output: archiveResult.output)
            }

            if let md5URL = URL(string: "\(fileURL.absoluteString).md5") {
                let md5Result = try await Task.detached {
                    try ProcessClient.runSync(
                        executableURL: curl,
                        arguments: ["-fL", "-C", "-", "-O", md5URL.absoluteString],
                        currentDirectoryURL: URL(fileURLWithPath: databaseDirectory, isDirectory: true)
                    )
                }.value
                guard md5Result.exitCode == 0 else {
                    return ProcessResult(exitCode: md5Result.exitCode, output: md5Result.output)
                }
            }

            if decompress {
                let tarResult = try await Task.detached {
                    try ProcessClient.runSync(
                        executableURL: tar,
                        arguments: ["-xzf", archiveName],
                        currentDirectoryURL: URL(fileURLWithPath: databaseDirectory, isDirectory: true)
                    )
                }.value
                guard tarResult.exitCode == 0 else {
                    return ProcessResult(exitCode: tarResult.exitCode, output: tarResult.output)
                }
            }
            completedArchives += 1
        }

        return ProcessResult(
            exitCode: 0,
            output: "ClusteredNR download finished: \(completedArchives) archives processed for \(RecommendedBlastDatabases.blastp)."
        )
    }

    func monitorSelectedDatabases() async {
        guard !selectedDatabaseNames.isEmpty else {
            databaseLog = LocalBlastError.emptyDownloadSelection.localizedDescription
            return
        }

        ensureWorkingDirectories()
        let names = selectedDatabaseNames.sorted()
        databaseLog = "Monitoring selected databases: \(names.joined(separator: ", "))"
        let expectedCompressedBytes = await fetchExpectedCompressedBytes(for: names)
        startDownloadProgress(
            names: names,
            directory: preferences.databaseDirectory,
            expectedCompressedBytes: expectedCompressedBytes,
            status: "Monitoring folder"
        )
    }

    func stopDownloadProgressMonitor() {
        finishDownloadProgress(exitCode: nil, failureMessage: "Monitoring stopped")
    }

    private func fetchExpectedCompressedBytes(for names: [String]) async -> Int64? {
        guard let url = URL(string: "https://ftp.ncbi.nlm.nih.gov/blast/db/blastdb-metadata-1-1.json") else {
            return nil
        }

        let selected = Set(names)
        var matchedNames = Set<String>()
        var total = Int64(0)

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let records = try JSONDecoder().decode([BlastDatabaseMetadataRecord].self, from: data)
            for record in records where selected.contains(record.dbname) {
                if let bytesTotal = record.bytesTotal {
                    total += bytesTotal
                }
                matchedNames.insert(record.dbname)
            }
        } catch {
            total = 0
            matchedNames.removeAll()
        }

        if selected.contains(RecommendedBlastDatabases.blastp),
           !matchedNames.contains(RecommendedBlastDatabases.blastp),
           let clusteredNRMetadataURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: clusteredNRMetadataURL)
                let record = try JSONDecoder().decode(BlastDatabaseMetadataRecord.self, from: data)
                if record.dbname == RecommendedBlastDatabases.blastp, let bytesTotal = record.bytesTotal {
                    total += bytesTotal
                }
            } catch {
                // The regular NCBI manifest is enough for all non-experimental databases.
            }
        }

        return total > 0 ? total : nil
    }

    private func startDownloadProgress(
        names: [String],
        directory: String,
        expectedCompressedBytes: Int64?,
        status: String = "Starting download"
    ) {
        downloadProgressTask?.cancel()
        downloadProgress = DownloadProgressSnapshot()
        downloadProgressNames = names
        downloadProgressDirectory = directory
        downloadProgressBaseline = DownloadDirectoryScanner.scan(directory: directory, databaseNames: names)

        applyDownloadProgressScan(
            downloadProgressBaseline,
            isActive: true,
            names: names,
            expectedCompressedBytes: expectedCompressedBytes,
            status: status
        )

        downloadProgressTask = Task { [weak self, directory, names, expectedCompressedBytes] in
            while !Task.isCancelled {
                let scan = DownloadDirectoryScanner.scan(directory: directory, databaseNames: names)
                await MainActor.run {
                    self?.applyDownloadProgressScan(
                        scan,
                        isActive: true,
                        names: names,
                        expectedCompressedBytes: expectedCompressedBytes,
                        status: "Downloading"
                    )
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func finishDownloadProgress(exitCode: Int32?, failureMessage: String? = nil) {
        downloadProgressTask?.cancel()
        downloadProgressTask = nil

        guard !downloadProgressDirectory.isEmpty, !downloadProgressNames.isEmpty else {
            return
        }

        let scan = DownloadDirectoryScanner.scan(
            directory: downloadProgressDirectory,
            databaseNames: downloadProgressNames
        )
        let status: String
        if let failureMessage {
            status = "Download failed: \(failureMessage)"
        } else if exitCode == 0 {
            status = "Download finished"
        } else if let exitCode {
            status = "Download exited with code \(exitCode)"
        } else {
            status = "Download stopped"
        }

        applyDownloadProgressScan(
            scan,
            isActive: false,
            names: downloadProgressNames,
            expectedCompressedBytes: downloadProgress.expectedCompressedBytes,
            status: status
        )
    }

    private func applyDownloadProgressScan(
        _ scan: DownloadDirectoryScan,
        isActive: Bool,
        names: [String],
        expectedCompressedBytes: Int64?,
        status: String
    ) {
        let startedAt = downloadProgress.startedAt ?? Date()
        let addedBytes = max(scan.observedCompressedBytes - downloadProgressBaseline.observedCompressedBytes, 0)
        downloadProgress = DownloadProgressSnapshot(
            hasActivity: true,
            isActive: isActive,
            databaseNames: names,
            startedAt: startedAt,
            lastUpdated: Date(),
            expectedCompressedBytes: expectedCompressedBytes,
            observedCompressedBytes: scan.observedCompressedBytes,
            addedCompressedBytes: addedBytes,
            archiveCount: scan.archiveCount,
            verifiedArchiveCount: scan.verifiedArchiveCount,
            matchingFileCount: scan.matchingFileCount,
            activeDatabaseName: scan.activeDatabaseName,
            activeFileName: scan.activeFileName,
            activeFileBytes: scan.activeFileBytes,
            status: status
        )
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

    func runRNASeqAnalysis() async {
        guard let executable = ProcessClient.resolveExecutable(named: rnaSeqConfiguration.program.executableName, preferences: preferences) else {
            rnaSeqLog = LocalBlastError.toolMissing(rnaSeqConfiguration.program.executableName).localizedDescription
            return
        }

        ensureWorkingDirectories()
        ensureDefaultRNASeqOutputPath()
        var outputPath = rnaSeqConfiguration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputFiles = rnaSeqConfiguration.inputFiles
        let keepConvertedFasta = rnaSeqConfiguration.keepConvertedFasta
        let needsGzip = inputFiles.contains(where: RNASeqFastqConverter.isGzipFASTQ)
        let gzipURL = needsGzip ? ProcessClient.resolveExecutable(named: "gzip", preferences: preferences) : nil
        var activeJobID: BlastJobRecord.ID?
        let reservedThreads = min(max(Int(rnaSeqConfiguration.numThreads) ?? 1, 1), logicalSearchThreadCount)
        let startedAt = Date()

        guard canReserveSearchThreads(reservedThreads) else {
            rnaSeqLog = "Not enough CPU threads available. \(searchCapacityLabel)"
            return
        }

        do {
            guard !inputFiles.isEmpty else { throw RNASeqAnalysisError.noInputFiles }
            if needsGzip, gzipURL == nil {
                throw RNASeqAnalysisError.gzipUnavailable
            }
            guard !rnaSeqConfiguration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RNASeqAnalysisError.missingDatabase
            }
            guard !outputPath.isEmpty else { throw RNASeqAnalysisError.missingOutputPath }
            guard !rnaSeqConfiguration.outputFieldString.isEmpty else { throw RNASeqAnalysisError.noOutputFields }
            outputPath = try preparedOutputPath(outputPath, program: rnaSeqConfiguration.program)
            rnaSeqConfiguration.outputPath = outputPath
            let outputURL = URL(fileURLWithPath: outputPath)
            let outputDirectory = outputURL.deletingLastPathComponent()

            isRunningRNASeq = true
            rnaSeqLog = "Preparing RNA-Seq annotation."
            let totalBytes = totalFileSize(paths: inputFiles)
            rnaSeqProgress = RNASeqProgressSnapshot(
                hasActivity: true,
                isActive: true,
                stage: .preparing,
                status: "Preparing FASTQ inputs",
                inputFileCount: inputFiles.count,
                totalInputBytes: totalBytes,
                startedAt: startedAt,
                lastUpdated: Date()
            )

            let convertedFastaURL = outputDirectory.appendingPathComponent(
                "\(outputURL.deletingPathExtension().lastPathComponent)-converted-\(UUID().uuidString).fasta"
            )

            rnaSeqLog = "Converting \(inputFiles.count) FASTQ file(s) to FASTA: \(convertedFastaURL.path)"
            let convertedReads = try await Task.detached { [weak self, inputFiles, convertedFastaURL, gzipURL] in
                try RNASeqFastqConverter.convert(inputFiles: inputFiles, outputURL: convertedFastaURL, gzipURL: gzipURL) { progress in
                    Task { @MainActor in
                        self?.applyRNASeqConversionProgress(progress)
                    }
                }
            }.value

            let command = try buildRNASeqBlastCommand(queryPath: convertedFastaURL.path)
            rnaSeqCommandPreview = command.preview
            guard canReserveSearchThreads(reservedThreads) else {
                throw LocalBlastError.processFailed("Not enough CPU threads available. \(searchCapacityLabel)")
            }
            let jobID = UUID()
            activeJobID = jobID
            jobs.insert(
                BlastJobRecord(
                    id: jobID,
                    kind: .rnaSeq,
                    title: "\(inputFiles.count.formatted()) FASTQ file(s)",
                    program: rnaSeqConfiguration.program,
                    database: rnaSeqConfiguration.databaseName,
                    outputPath: outputPath,
                    commandPreview: command.preview,
                    exitCode: nil,
                    date: startedAt,
                    status: .running,
                    duration: nil,
                    outputBytes: 0,
                    hitCount: nil,
                    noHits: false,
                    linkedGroup: "",
                    reservedThreads: reservedThreads
                ),
                at: 0
            )
            selectedJobID = jobID
            rnaSeqLog = "Running \(command.preview)"
            startRNASeqOutputMonitor(outputPath: outputPath, convertedReads: convertedReads)
            let result = try await runTrackedProcess(
                jobID: jobID,
                reservedThreads: reservedThreads,
                executableURL: executable,
                arguments: command.arguments,
                environment: command.environment
            )
            stopRNASeqProgressMonitor()

            if !keepConvertedFasta {
                try? FileManager.default.removeItem(at: convertedFastaURL)
            }

            let outputBytes = fileSize(path: outputPath)
            let logText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let wasKilled = killedJobIDs.contains(jobID)
            rnaSeqLog = wasKilled
                ? "RNA-Seq annotation killed."
                : (logText.isEmpty ? "RNA-Seq annotation finished with exit code \(result.exitCode)." : logText)
            rnaSeqProgress = RNASeqProgressSnapshot(
                hasActivity: true,
                isActive: false,
                stage: wasKilled ? .failed : (result.exitCode == 0 ? .finished : .failed),
                status: wasKilled ? "Job killed" : (result.exitCode == 0 ? "Annotation finished" : "BLAST exited with code \(result.exitCode)"),
                inputFileCount: inputFiles.count,
                totalInputBytes: totalBytes,
                processedInputBytes: totalBytes,
                convertedReads: convertedReads,
                outputBytes: outputBytes,
                startedAt: startedAt,
                lastUpdated: Date()
            )
            let report = readResultReport(at: outputPath)
            if !wasKilled {
                selectedResultReport = report
            }
            updateJob(jobID) { job in
                job.exitCode = result.exitCode
                job.status = wasKilled ? .killed : (result.exitCode == 0 ? .finished : .failed)
                job.duration = Date().timeIntervalSince(startedAt)
                job.outputBytes = outputBytes
                job.hitCount = report?.hitCount
                job.noHits = report?.noHits ?? false
            }
            killedJobIDs.remove(jobID)
            resultLog = wasKilled ? "Killed \(URL(fileURLWithPath: outputPath).lastPathComponent)." : "Loaded \(URL(fileURLWithPath: outputPath).lastPathComponent)."
        } catch {
            var wasKilled = false
            if let activeJobID {
                wasKilled = killedJobIDs.remove(activeJobID) != nil
                updateJob(activeJobID) { job in
                    job.status = wasKilled ? .killed : .failed
                    job.duration = Date().timeIntervalSince(startedAt)
                    job.exitCode = nil
                    job.outputBytes = outputPath.isEmpty ? job.outputBytes : fileSize(path: outputPath)
                }
            }
            stopRNASeqProgressMonitor()
            let message = wasKilled ? "Job killed." : error.localizedDescription
            rnaSeqLog = message
            var snapshot = rnaSeqProgress
            snapshot.hasActivity = true
            snapshot.isActive = false
            snapshot.stage = .failed
            snapshot.status = message
            snapshot.lastUpdated = Date()
            rnaSeqProgress = snapshot
        }

        isRunningRNASeq = false
    }

    private func applyRNASeqConversionProgress(_ progress: RNASeqConversionProgress) {
        let startedAt = rnaSeqProgress.startedAt ?? Date()
        rnaSeqProgress = RNASeqProgressSnapshot(
            hasActivity: true,
            isActive: true,
            stage: .converting,
            status: "Converting FASTQ to FASTA",
            inputFileCount: rnaSeqConfiguration.inputFiles.count,
            currentFileName: URL(fileURLWithPath: progress.currentFilePath).lastPathComponent,
            totalInputBytes: progress.totalInputBytes,
            processedInputBytes: progress.processedInputBytes,
            convertedReads: progress.convertedReads,
            outputBytes: progress.outputBytes,
            isConversionProgressDeterminate: progress.isDeterminate,
            startedAt: startedAt,
            lastUpdated: Date()
        )
    }

    private func startRNASeqOutputMonitor(outputPath: String, convertedReads: Int64) {
        rnaSeqProgressTask?.cancel()
        let startedAt = rnaSeqProgress.startedAt ?? Date()
        let totalBytes = rnaSeqProgress.totalInputBytes
        let inputFileCount = rnaSeqProgress.inputFileCount
        rnaSeqProgress = RNASeqProgressSnapshot(
            hasActivity: true,
            isActive: true,
            stage: .annotating,
            status: "Annotating reads with BLAST",
            inputFileCount: inputFileCount,
            totalInputBytes: totalBytes,
            processedInputBytes: totalBytes,
            convertedReads: convertedReads,
            outputBytes: fileSize(path: outputPath),
            startedAt: startedAt,
            lastUpdated: Date()
        )

        rnaSeqProgressTask = Task { [weak self, outputPath] in
            while !Task.isCancelled {
                let outputBytes = Self.fileSize(path: outputPath)
                await MainActor.run {
                    guard let self else { return }
                    var snapshot = self.rnaSeqProgress
                    snapshot.outputBytes = outputBytes
                    snapshot.lastUpdated = Date()
                    self.rnaSeqProgress = snapshot
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopRNASeqProgressMonitor() {
        rnaSeqProgressTask?.cancel()
        rnaSeqProgressTask = nil
    }

    private func totalFileSize(paths: [String]) -> Int64 {
        paths.reduce(Int64(0)) { total, path in
            total + Self.fileSize(path: path)
        }
    }

    private static func fileSize(path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func fileModificationDate(path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    private func fileSize(path: String) -> Int64 {
        Self.fileSize(path: path)
    }

    private func preparedOutputPath(_ requestedPath: String, program: BlastProgram) throws -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath = trimmed.isEmpty ? defaultBlastOutputPath(for: program) : trimmed
        let resolvedPath = uniqueOutputPath(basePath)
        try createOutputDirectory(for: resolvedPath)
        return resolvedPath
    }

    private func preparedOutputPath(_ requestedPath: String, configuration: BlastSearchConfiguration) throws -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePath = trimmed.isEmpty ? defaultSearchOutputPath(for: configuration) : trimmed
        let resolvedPath = uniqueOutputPath(basePath)
        try createOutputDirectory(for: resolvedPath)
        return resolvedPath
    }

    private func uniqueOutputPath(_ path: String) -> String {
        guard outputPathIsAvailable(path) else {
            return uniqueStampedOutputPath(path)
        }
        return path
    }

    private func uniqueStampedOutputPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? "txt" : url.pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stampedBaseName = "\(baseName)-\(formatter.string(from: Date()))"

        for index in 0..<1_000 {
            let suffix = index == 0 ? "" : "-\(index + 1)"
            let candidate = directory
                .appendingPathComponent("\(stampedBaseName)\(suffix)")
                .appendingPathExtension(fileExtension)
                .path
            if outputPathIsAvailable(candidate) {
                return candidate
            }
        }
        return directory
            .appendingPathComponent("\(stampedBaseName)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
            .path
    }

    private func outputPathIsAvailable(_ path: String) -> Bool {
        !FileManager.default.fileExists(atPath: path) &&
        !jobs.contains { runningJobHandles[$0.id] != nil && $0.outputPath == path }
    }

    private func createOutputDirectory(for path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func refreshResultFiles() {
        ensureWorkingDirectories()
        let directoryURL = URL(fileURLWithPath: preferences.outputDirectory, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            resultLog = "Could not scan \(preferences.outputDirectory)."
            return
        }

        var importedCount = 0
        for url in urls {
            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }
            guard automaticResultExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard !jobs.contains(where: { $0.outputPath == url.path }) else { continue }

            let outputBytes = Int64(resourceValues?.fileSize ?? 0)
            let report = outputBytes <= maxAutoLoadedResultBytes ? readResultReport(at: url.path) : nil
            let metadata = loadReuseMetadata(forOutputPath: url.path)
            let program = metadata?.program ?? Self.program(from: report?.program) ?? .blastn
            jobs.append(
                BlastJobRecord(
                    kind: metadata?.kind ?? .imported,
                    title: metadata?.title.isEmpty == false ? metadata?.title ?? "" : (report?.query.isEmpty == false ? report?.query ?? "" : url.lastPathComponent),
                    program: program,
                    database: metadata?.database ?? report?.database ?? "",
                    outputPath: url.path,
                    commandPreview: metadata?.commandPreview ?? "",
                    exitCode: nil,
                    date: metadata?.date ?? resourceValues?.contentModificationDate ?? Date(),
                    status: .imported,
                    duration: nil,
                    outputBytes: outputBytes,
                    hitCount: report?.hitCount,
                    noHits: report?.noHits ?? false,
                    reusableConfiguration: metadata?.configuration
                )
            )
            importedCount += 1
        }

        jobs.sort { lhs, rhs in
            lhs.date > rhs.date
        }

        if selectedJobID == nil, let firstJob = jobs.first {
            selectJob(firstJob)
        }
        resultLog = importedCount == 0
            ? "Result folder is up to date."
            : "Loaded \(importedCount.formatted()) result file(s) from \(preferences.outputDirectory)."
    }

    func importResultFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let outputBytes = fileSize(path: path)
        let report = outputBytes <= maxAutoLoadedResultBytes ? readResultReport(at: path) : nil
        let metadata = loadReuseMetadata(forOutputPath: path)
        let program = metadata?.program ?? Self.program(from: report?.program) ?? .blastn
        let job = BlastJobRecord(
            kind: metadata?.kind ?? .imported,
            title: metadata?.title.isEmpty == false ? metadata?.title ?? "" : (report?.query.isEmpty == false ? report?.query ?? "" : url.lastPathComponent),
            program: program,
            database: metadata?.database ?? report?.database ?? "",
            outputPath: path,
            commandPreview: metadata?.commandPreview ?? "",
            exitCode: nil,
            date: metadata?.date ?? Self.fileModificationDate(path: path) ?? Date(),
            status: .imported,
            duration: nil,
            outputBytes: outputBytes,
            hitCount: report?.hitCount,
            noHits: report?.noHits ?? false,
            reusableConfiguration: metadata?.configuration
        )

        if let existingIndex = jobs.firstIndex(where: { $0.outputPath == path }) {
            jobs[existingIndex] = job
        } else {
            jobs.insert(job, at: 0)
        }
        selectJob(job)
        resultLog = "Loaded \(url.lastPathComponent)."
    }

    func selectJob(_ job: BlastJobRecord, extendingRange: Bool = false, togglingSelection: Bool = false) {
        if extendingRange,
           let anchorID = resultSelectionAnchorID ?? selectedJobID,
           let anchorIndex = jobs.firstIndex(where: { $0.id == anchorID }),
           let targetIndex = jobs.firstIndex(where: { $0.id == job.id }) {
            let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            selectedJobIDs = Set(jobs[bounds].map(\.id))
            resultSelectionAnchorID = anchorID
        } else if togglingSelection {
            if selectedJobIDs.contains(job.id), selectedJobIDs.count > 1 {
                selectedJobIDs.remove(job.id)
                if selectedJobID == job.id,
                   let nextID = selectedJobIDs.first,
                   let nextJob = jobs.first(where: { $0.id == nextID }) {
                    selectedJobID = nextJob.id
                    loadResult(for: nextJob)
                    return
                }
            } else {
                selectedJobIDs.insert(job.id)
                if resultSelectionAnchorID == nil {
                    resultSelectionAnchorID = job.id
                }
            }
        } else {
            selectedJobIDs = [job.id]
            resultSelectionAnchorID = job.id
        }
        selectedJobID = job.id
        loadResult(for: job)
    }

    func reuseResult(_ job: BlastJobRecord) {
        guard var reusableConfiguration = job.reusableConfiguration else {
            resultLog = "This result does not include saved inputs and settings for reuse."
            return
        }

        if reusableConfiguration.databaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reusableConfiguration.databaseDirectory = preferences.databaseDirectory
        }
        if reusableConfiguration.igBlast.additionalDatabaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reusableConfiguration.igBlast.additionalDatabaseDirectory = preferences.databaseDirectory
        }
        if reusableConfiguration.alignMultipleSequences, !reusableConfiguration.program.supportsMultipleSequenceAlignment {
            reusableConfiguration.alignMultipleSequences = false
        }

        reusableConfiguration.outputPath = reusableOutputPath(for: reusableConfiguration)
        configuration = reusableConfiguration
        section = .run
        runLog = "Loaded settings from \(URL(fileURLWithPath: job.outputPath).lastPathComponent) for a new search."
        resultLog = "Ready to re-run \(job.displayTitle) as a new search."
        updateCommandPreview()
    }

    func deleteSelectedResults() {
        deleteResults(ids: selectedResultIDsForAction)
    }

    func deleteResult(_ job: BlastJobRecord) {
        deleteResults(ids: [job.id])
    }

    func deleteAllResults() {
        deleteResults(ids: Set(jobs.map(\.id)))
    }

    func exportSelectedResults(to directoryPath: String) {
        exportResults(ids: selectedResultIDsForAction, to: directoryPath)
    }

    func exportResult(_ job: BlastJobRecord, to directoryPath: String) {
        exportResults(ids: [job.id], to: directoryPath)
    }

    func exportAllResults(to directoryPath: String) {
        exportResults(ids: Set(jobs.map(\.id)), to: directoryPath)
    }

    private func deleteResults(ids: Set<BlastJobRecord.ID>) {
        let candidates = jobs.filter { ids.contains($0.id) }
        guard !candidates.isEmpty else {
            resultLog = "No results selected."
            return
        }

        let deletableJobs = candidates.filter { !isJobRunning($0.id) }
        guard !deletableJobs.isEmpty else {
            resultLog = "Running results cannot be deleted until they finish or are killed."
            return
        }

        var deletedIDs = Set<BlastJobRecord.ID>()
        var failures: [String] = []
        for job in deletableJobs {
            do {
                try deleteResultFiles(for: job)
                deletedIDs.insert(job.id)
            } catch {
                failures.append("\(URL(fileURLWithPath: job.outputPath).lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !deletedIDs.isEmpty {
            jobs.removeAll { deletedIDs.contains($0.id) }
            selectedJobIDs.subtract(deletedIDs)
            if let selectedJobID, deletedIDs.contains(selectedJobID) {
                selectFallbackResultAfterDeletion()
            } else if selectedJobIDs.isEmpty, let selectedJobID {
                selectedJobIDs = [selectedJobID]
            }
        }

        let skipped = candidates.count - deletableJobs.count
        var message = "Deleted \(deletedIDs.count.formatted()) result\(deletedIDs.count == 1 ? "" : "s")."
        if skipped > 0 {
            message += " Skipped \(skipped.formatted()) running result\(skipped == 1 ? "" : "s")."
        }
        if !failures.isEmpty {
            message += " \(failures.count.formatted()) file\(failures.count == 1 ? "" : "s") could not be deleted."
        }
        resultLog = message
    }

    private func selectFallbackResultAfterDeletion() {
        if let firstSelectedID = selectedJobIDs.first,
           let selectedJob = jobs.first(where: { $0.id == firstSelectedID }) {
            selectedJobID = selectedJob.id
            loadResult(for: selectedJob)
            return
        }

        if let firstJob = jobs.first {
            selectedJobIDs = [firstJob.id]
            resultSelectionAnchorID = firstJob.id
            selectedJobID = firstJob.id
            loadResult(for: firstJob)
        } else {
            selectedJobIDs = []
            resultSelectionAnchorID = nil
            selectedJobID = nil
            selectedResultReport = nil
        }
    }

    private func deleteResultFiles(for job: BlastJobRecord) throws {
        try trashOrRemoveFileIfPresent(at: job.outputPath)
        try? trashOrRemoveFileIfPresent(at: reuseMetadataPath(forOutputPath: job.outputPath))
    }

    private func trashOrRemoveFileIfPresent(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        do {
            _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func exportResults(ids: Set<BlastJobRecord.ID>, to directoryPath: String) {
        let selectedJobs = jobs.filter { ids.contains($0.id) }
        guard !selectedJobs.isEmpty else {
            resultLog = "No results selected for export."
            return
        }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        var exportedCount = 0
        var failures: [String] = []

        for job in selectedJobs {
            let sourceURL = URL(fileURLWithPath: job.outputPath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                failures.append("\(sourceURL.lastPathComponent): file not found")
                continue
            }

            do {
                let destinationURL = availableExportURL(for: sourceURL, in: directoryURL)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                let metadataPath = reuseMetadataPath(forOutputPath: job.outputPath)
                if FileManager.default.fileExists(atPath: metadataPath) {
                    try? FileManager.default.copyItem(
                        at: URL(fileURLWithPath: metadataPath),
                        to: URL(fileURLWithPath: reuseMetadataPath(forOutputPath: destinationURL.path))
                    )
                }
                exportedCount += 1
            } catch {
                failures.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        var message = "Exported \(exportedCount.formatted()) result\(exportedCount == 1 ? "" : "s") to \(directoryPath)."
        if !failures.isEmpty {
            message += " \(failures.count.formatted()) result\(failures.count == 1 ? "" : "s") could not be exported."
        }
        resultLog = message
    }

    private func availableExportURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        let original = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        if !fileManager.fileExists(atPath: original.path) {
            return original
        }

        for index in 2..<10_000 {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName)-\(index)"
                : "\(baseName)-\(index).\(fileExtension)"
            let candidate = directoryURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let fallbackName = fileExtension.isEmpty
            ? "\(baseName)-\(UUID().uuidString)"
            : "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        return directoryURL.appendingPathComponent(fallbackName)
    }

    func loadSelectedJobResult() {
        guard let selectedJobID, let job = jobs.first(where: { $0.id == selectedJobID }) else {
            selectedResultReport = nil
            return
        }
        loadResult(for: job)
    }

    func loadResult(for job: BlastJobRecord) {
        guard FileManager.default.fileExists(atPath: job.outputPath) else {
            selectedResultReport = nil
            resultLog = "Result file was not found: \(job.outputPath)"
            return
        }

        let outputBytes = fileSize(path: job.outputPath)
        guard outputBytes <= maxAutoLoadedResultBytes else {
            selectedResultReport = nil
            resultLog = "Result file is \(ByteCountFormatter.string(fromByteCount: outputBytes, countStyle: .file)); files over \(ByteCountFormatter.string(fromByteCount: maxAutoLoadedResultBytes, countStyle: .file)) are not loaded into the GUI."
            return
        }

        guard let report = readResultReport(at: job.outputPath) else {
            selectedResultReport = nil
            resultLog = "Could not read \(URL(fileURLWithPath: job.outputPath).lastPathComponent)."
            return
        }

        selectedResultReport = report
        resultLog = "Loaded \(URL(fileURLWithPath: job.outputPath).lastPathComponent)."
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index].outputBytes = outputBytes
            jobs[index].hitCount = report.hitCount
            jobs[index].noHits = report.noHits
            if jobs[index].database.isEmpty {
                jobs[index].database = report.database
            }
            if jobs[index].title.isEmpty, !report.query.isEmpty {
                jobs[index].title = report.query
            }
        }
    }

    private func readResultReport(at path: String) -> BlastResultReport? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return BlastResultParser.parse(text)
    }

    private func reuseMetadataPath(forOutputPath outputPath: String) -> String {
        "\(outputPath).localblaststudio.json"
    }

    private func loadReuseMetadata(forOutputPath outputPath: String) -> BlastRunReuseMetadata? {
        let path = reuseMetadataPath(forOutputPath: outputPath)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(BlastRunReuseMetadata.self, from: data)
    }

    private func saveReuseMetadata(
        kind: BlastJobKind,
        title: String,
        program: BlastProgram,
        database: String,
        outputPath: String,
        commandPreview: String,
        date: Date,
        configuration: BlastSearchConfiguration
    ) {
        let metadata = BlastRunReuseMetadata(
            kind: kind,
            title: title,
            program: program,
            database: database,
            commandPreview: commandPreview,
            date: date,
            configuration: configuration
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metadata) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: reuseMetadataPath(forOutputPath: outputPath)), options: .atomic)
    }

    private func updateJob(_ id: BlastJobRecord.ID, _ mutation: (inout BlastJobRecord) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutation(&jobs[index])
    }

    func killJob(_ id: BlastJobRecord.ID) {
        guard let handle = runningJobHandles[id] else { return }
        killedJobIDs.insert(id)
        handle.terminate()
        updateJob(id) { job in
            job.status = .killed
            job.duration = Date().timeIntervalSince(job.date)
            job.outputBytes = fileSize(path: job.outputPath)
        }
        if activeSearchProgressJobID == id {
            failSearchProgress("Stopping job...", outputPath: jobs.first { $0.id == id }?.outputPath ?? "", jobID: id)
        }
        resultLog = "Stopping job."
    }

    func killAllRunningJobs() {
        let ids = Array(runningJobHandles.keys)
        guard !ids.isEmpty else { return }
        ids.forEach { killJob($0) }
        runLog = "Stopping \(ids.count.formatted()) running job(s)."
    }

    func isJobRunning(_ id: BlastJobRecord.ID) -> Bool {
        runningJobHandles[id] != nil
    }

    private func runTrackedProcess(
        jobID: BlastJobRecord.ID,
        reservedThreads: Int,
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ProcessResult {
        let handle = TrackedProcessHandle(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment
        )
        runningJobHandles[jobID] = handle
        runningJobThreads[jobID] = reservedThreads
        refreshRunningSearchState()
        defer {
            runningJobHandles.removeValue(forKey: jobID)
            runningJobThreads.removeValue(forKey: jobID)
            refreshRunningSearchState()
        }

        return try await Task.detached {
            try handle.runAndWait()
        }.value
    }

    private func refreshRunningSearchState() {
        activeSearchThreadCount = runningJobThreads.values.reduce(0, +)
        isRunningSearch = !runningJobHandles.isEmpty
    }

    private func jobTitle(configuration: BlastSearchConfiguration, queryPath: String) -> String {
        if !configuration.queryFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: queryPath).deletingPathExtension().lastPathComponent
        }
        if configuration.alignMultipleSequences {
            return "\(configuration.program.queryKind.rawValue) Multiple Alignment"
        }
        return "\(configuration.program.queryKind.rawValue) Sequence"
    }

    private func searchTargetDescription(for configuration: BlastSearchConfiguration) -> String {
        if configuration.alignMultipleSequences {
            return "3+ sequence alignment"
        }
        if configuration.program.isIgBlast {
            return configuration.igBlast.searchTargetDescription(for: configuration.program)
        }
        return configuration.alignTwoSequences ? "Subject sequence" : configuration.databaseName
    }

    private static func program(from reportProgram: String?) -> BlastProgram? {
        guard let reportProgram else { return nil }
        let normalized = reportProgram.lowercased()
        return BlastProgram.allCases.first {
            normalized.contains($0.rawValue) || normalized.contains($0.displayName.lowercased())
        }
    }

    func runSearch() async {
        let executableName = configuration.alignMultipleSequences
            ? MultipleSequenceAlignmentCommandBuilder.executableName
            : configuration.program.executableName
        guard let executable = ProcessClient.resolveExecutable(named: executableName, preferences: preferences) else {
            runLog = LocalBlastError.toolMissing(executableName).localizedDescription
            return
        }

        if supportsStructureQueryImport, !structureChains.isEmpty, !configuration.alignMultipleSequences {
            await runStructureSearch(executable: executable)
            return
        }

        ensureWorkingDirectories()
        ensureDefaultOutputPath()
        var activeConfiguration = configuration
        var outputPath = activeConfiguration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var activeJobID: BlastJobRecord.ID?
        let reservedThreads = reservedThreadCount(for: activeConfiguration)
        let startedAt = Date()
        blastResultReport = nil

        guard canReserveSearchThreads(reservedThreads) else {
            runLog = "Not enough CPU threads available. \(searchCapacityLabel)"
            return
        }

        do {
            let queryPath = try materializedSequencePath(
                filePath: activeConfiguration.queryFilePath,
                sequenceText: activeConfiguration.queryText,
                filenamePrefix: "query",
                missingError: .missingQuery
            )
            let subjectPath = activeConfiguration.alignTwoSequences && !activeConfiguration.alignMultipleSequences ? try materializedSequencePath(
                filePath: activeConfiguration.subjectFilePath,
                sequenceText: activeConfiguration.subjectText,
                filenamePrefix: "subject",
                missingError: .missingSubject
            ) : ""
            if activeConfiguration.alignMultipleSequences {
                let sequenceCount = fastaRecordCount(filePath: queryPath)
                guard sequenceCount >= 3 else {
                    throw BlastCommandBuildError.missingMultipleSequences
                }
            }
            let queryLength = sequenceResidueCount(filePath: queryPath)
            outputPath = try preparedOutputPath(outputPath, configuration: activeConfiguration)
            activeConfiguration.outputPath = outputPath
            configuration.outputPath = outputPath
            let command = activeConfiguration.alignMultipleSequences
                ? try MultipleSequenceAlignmentCommandBuilder.build(
                    configuration: activeConfiguration,
                    inputPath: queryPath
                )
                : try BlastCommandBuilder.build(
                    configuration: activeConfiguration,
                    queryPath: queryPath,
                    subjectPath: subjectPath
                )
            let jobKind: BlastJobKind = activeConfiguration.alignMultipleSequences ? .multipleAlignment : .blastSearch
            let jobTitle = jobTitle(configuration: activeConfiguration, queryPath: queryPath)
            let jobDatabase = searchTargetDescription(for: activeConfiguration)
            saveReuseMetadata(
                kind: jobKind,
                title: jobTitle,
                program: activeConfiguration.program,
                database: jobDatabase,
                outputPath: outputPath,
                commandPreview: command.preview,
                date: startedAt,
                configuration: activeConfiguration
            )
            let jobID = UUID()
            activeJobID = jobID
            jobs.insert(
                BlastJobRecord(
                    id: jobID,
                    kind: jobKind,
                    title: jobTitle,
                    program: activeConfiguration.program,
                    database: jobDatabase,
                    outputPath: outputPath,
                    commandPreview: command.preview,
                    exitCode: nil,
                    date: startedAt,
                    status: .running,
                    duration: nil,
                    outputBytes: 0,
                    hitCount: nil,
                    noHits: false,
                    linkedGroup: "",
                    reservedThreads: reservedThreads,
                    reusableConfiguration: activeConfiguration
                ),
                at: 0
            )
            selectedJobID = jobID
            beginSearchProgress(
                jobID: jobID,
                configuration: activeConfiguration,
                queryLength: queryLength,
                outputPath: outputPath
            )
            runLog = runningSearchLog(
                command: command,
                configuration: activeConfiguration,
                queryLength: queryLength,
                outputPath: outputPath
            )
            startSearchOutputMonitor(
                jobID: jobID,
                outputPath: outputPath,
                activeStatus: activeConfiguration.alignMultipleSequences ? "Aligning sequences" : "Searching database",
                writingStatus: activeConfiguration.alignMultipleSequences ? "Writing alignment" : "Writing BLAST report"
            )
            let result = try await runTrackedProcess(
                jobID: jobID,
                reservedThreads: reservedThreads,
                executableURL: executable,
                arguments: command.arguments,
                environment: command.environment
            )
            stopSearchProgressMonitor(jobID: jobID)

            if activeSearchProgressJobID == jobID {
                var formattingProgress = searchProgress
                formattingProgress.stage = .formatting
                formattingProgress.status = "Formatting results"
                formattingProgress.lastUpdated = Date()
                searchProgress = formattingProgress
            }

            let logText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultText = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
            let report = resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : BlastResultParser.parse(resultText)
            let wasKilled = killedJobIDs.contains(jobID)
            if !wasKilled {
                blastResultReport = report
                selectedResultReport = report
            }
            finishSearchProgress(exitCode: result.exitCode, report: report, outputPath: outputPath, jobID: jobID)
            killedJobIDs.remove(jobID)
            runLog = wasKilled
                ? "Killed job: \(outputPath)"
                : completedSearchLog(
                    exitCode: result.exitCode,
                    diagnostics: logText,
                    report: report,
                    outputPath: outputPath
                )
            updateJob(jobID) { job in
                job.exitCode = result.exitCode
                job.status = wasKilled ? .killed : (result.exitCode == 0 ? .finished : .failed)
                job.duration = Date().timeIntervalSince(startedAt)
                job.outputBytes = fileSize(path: outputPath)
                job.hitCount = report?.hitCount
                job.noHits = report?.noHits ?? false
                if job.database.isEmpty {
                    job.database = report?.database ?? ""
                }
            }
            selectedJobID = jobID
            resultLog = wasKilled ? "Killed \(URL(fileURLWithPath: outputPath).lastPathComponent)." : "Loaded \(URL(fileURLWithPath: outputPath).lastPathComponent)."
        } catch {
            var wasKilled = false
            if let activeJobID {
                stopSearchProgressMonitor(jobID: activeJobID)
                wasKilled = killedJobIDs.remove(activeJobID) != nil
                updateJob(activeJobID) { job in
                    job.status = wasKilled ? .killed : .failed
                    job.duration = Date().timeIntervalSince(startedAt)
                    job.exitCode = nil
                    job.outputBytes = outputPath.isEmpty ? job.outputBytes : fileSize(path: outputPath)
                }
                failSearchProgress(wasKilled ? "Job killed" : error.localizedDescription, outputPath: outputPath, jobID: activeJobID)
            } else {
                failSearchProgress(error.localizedDescription, outputPath: outputPath)
            }
            let message = wasKilled ? "Job killed." : error.localizedDescription
            runLog = message
            resultLog = message
        }
    }

    private func runStructureSearch(executable: URL) async {
        ensureWorkingDirectories()
        ensureDefaultOutputPath()

        let selectedChains: [(chain: ProteinChainSequence, label: String)]
        switch configuration.program {
        case .igblastp:
            selectedChains = igBlastPStructureChains()
        case .blastp:
            selectedChains = structureChains.map { ($0, "Chain \($0.chainID)") }
        default:
            selectedChains = []
        }

        guard !selectedChains.isEmpty else {
            runLog = configuration.program == .igblastp
                ? "IgBLASTP structure import expects chain A (LC) and/or chain B (HC)."
                : "No protein chains are loaded from the structure file."
            return
        }

        let activeConfigurationTemplate = configuration
        let groupTitle = linkedStructureGroupTitle(program: activeConfigurationTemplate.program)
        let startedAt = Date()
        var completedLogs: [String] = []
        var firstCompletedReport: BlastResultReport?
        var firstCompletedJobID: BlastJobRecord.ID?

        blastResultReport = nil

        for (index, item) in selectedChains.enumerated() {
            var activeConfiguration = activeConfigurationTemplate
            activeConfiguration.queryText = ""
            activeConfiguration.queryFilePath = ""
            activeConfiguration.alignTwoSequences = false
            let chainStartedAt = Date()
            var outputPath = ""
            var activeJobID: BlastJobRecord.ID?
            let reservedThreads = reservedThreadCount(for: activeConfiguration)

            guard canReserveSearchThreads(reservedThreads) else {
                completedLogs.append("Chain \(item.chain.chainID) (\(item.label)) did not start: \(searchCapacityLabel)")
                break
            }

            do {
                let queryPath = try materializedStructureChainPath(chain: item.chain, label: item.label)
                outputPath = try preparedOutputPath(
                    structureOutputPath(
                        basePath: activeConfigurationTemplate.outputPath,
                        chain: item.chain,
                        label: item.label,
                        index: index
                    ),
                    program: activeConfiguration.program
                )
                activeConfiguration.outputPath = outputPath
                let queryLength = item.chain.sequence.count
                let command = try BlastCommandBuilder.build(
                    configuration: activeConfiguration,
                    queryPath: queryPath
                )

                let jobID = UUID()
                activeJobID = jobID
                jobs.insert(
                    BlastJobRecord(
                        id: jobID,
                        kind: .blastSearch,
                        title: structureJobTitle(chain: item.chain, label: item.label),
                        program: activeConfiguration.program,
                        database: searchTargetDescription(for: activeConfiguration),
                        outputPath: outputPath,
                        commandPreview: command.preview,
                        exitCode: nil,
                        date: chainStartedAt,
                        status: .running,
                        duration: nil,
                        outputBytes: 0,
                        hitCount: nil,
                        noHits: false,
                        linkedGroup: groupTitle,
                        reservedThreads: reservedThreads
                    ),
                    at: 0
                )
                selectedJobID = jobID
                beginSearchProgress(
                    jobID: jobID,
                    configuration: activeConfiguration,
                    queryLength: queryLength,
                    outputPath: outputPath
                )
                runLog = """
                \(groupTitle)
                Chain \(item.chain.chainID) (\(item.label)): \(queryLength.formatted()) residues

                Running \(command.preview)
                """
                startSearchOutputMonitor(jobID: jobID, outputPath: outputPath)
                let result = try await runTrackedProcess(
                    jobID: jobID,
                    reservedThreads: reservedThreads,
                    executableURL: executable,
                    arguments: command.arguments,
                    environment: command.environment
                )
                stopSearchProgressMonitor(jobID: jobID)

                if activeSearchProgressJobID == jobID {
                    var formattingProgress = searchProgress
                    formattingProgress.stage = .formatting
                    formattingProgress.status = "Formatting \(item.label)"
                    formattingProgress.lastUpdated = Date()
                    searchProgress = formattingProgress
                }

                let logText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let resultText = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
                let report = resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : BlastResultParser.parse(resultText)
                let wasKilled = killedJobIDs.contains(jobID)
                if !wasKilled, firstCompletedReport == nil {
                    firstCompletedReport = report
                    firstCompletedJobID = jobID
                }
                finishSearchProgress(exitCode: result.exitCode, report: report, outputPath: outputPath, jobID: jobID)
                killedJobIDs.remove(jobID)
                completedLogs.append(
                    wasKilled ? "Chain \(item.chain.chainID) (\(item.label)) killed." : completedSearchLog(
                        exitCode: result.exitCode,
                        diagnostics: logText,
                        report: report,
                        outputPath: outputPath
                    )
                )
                updateJob(jobID) { job in
                    job.exitCode = result.exitCode
                    job.status = wasKilled ? .killed : (result.exitCode == 0 ? .finished : .failed)
                    job.duration = Date().timeIntervalSince(chainStartedAt)
                    job.outputBytes = fileSize(path: outputPath)
                    job.hitCount = report?.hitCount
                    job.noHits = report?.noHits ?? false
                    if job.database.isEmpty {
                        job.database = report?.database ?? ""
                    }
                }
            } catch {
                if let activeJobID {
                    stopSearchProgressMonitor(jobID: activeJobID)
                    let wasKilled = killedJobIDs.remove(activeJobID) != nil
                    updateJob(activeJobID) { job in
                        job.status = wasKilled ? .killed : .failed
                        job.duration = Date().timeIntervalSince(chainStartedAt)
                        job.exitCode = nil
                        job.outputBytes = outputPath.isEmpty ? job.outputBytes : fileSize(path: outputPath)
                    }
                    failSearchProgress(wasKilled ? "Job killed" : error.localizedDescription, outputPath: outputPath, jobID: activeJobID)
                    completedLogs.append(wasKilled ? "Chain \(item.chain.chainID) (\(item.label)) killed." : "Chain \(item.chain.chainID) (\(item.label)) failed: \(error.localizedDescription)")
                } else {
                    failSearchProgress(error.localizedDescription, outputPath: outputPath)
                    completedLogs.append("Chain \(item.chain.chainID) (\(item.label)) failed: \(error.localizedDescription)")
                }
            }
        }

        blastResultReport = firstCompletedReport
        selectedResultReport = firstCompletedReport
        if let firstCompletedJobID {
            selectedJobID = firstCompletedJobID
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        runLog = """
        \(groupTitle)
        Finished \(selectedChains.count.formatted()) linked chain job(s) in \(durationLabel(elapsed)).

        \(completedLogs.joined(separator: "\n\n"))
        """
        resultLog = "Loaded linked structure search: \(groupTitle)."
    }

    private func beginSearchProgress(
        jobID: BlastJobRecord.ID,
        configuration: BlastSearchConfiguration,
        queryLength: Int?,
        outputPath: String
    ) {
        activeSearchProgressJobID = jobID
        searchProgress = SearchProgressSnapshot(
            hasActivity: true,
            isActive: true,
            stage: .submitted,
            status: "Sequence submitted",
            program: configuration.program.displayName,
            database: searchTargetDescription(for: configuration),
            queryLength: queryLength,
            outputPath: outputPath,
            outputBytes: 0,
            startedAt: Date(),
            lastUpdated: Date()
        )
    }

    private func startSearchOutputMonitor(
        jobID: BlastJobRecord.ID,
        outputPath: String,
        activeStatus: String = "Searching database",
        writingStatus: String = "Writing BLAST report"
    ) {
        searchProgressTasks[jobID]?.cancel()
        let baselineModifiedAt = Self.fileModificationDate(path: outputPath)
        var snapshot = searchProgress
        snapshot.stage = .searching
        snapshot.status = activeStatus
        snapshot.outputBytes = 0
        snapshot.lastUpdated = Date()
        searchProgress = snapshot

        searchProgressTasks[jobID] = Task { [weak self, jobID, outputPath, baselineModifiedAt] in
            while !Task.isCancelled {
                let outputBytes = Self.fileSize(path: outputPath)
                let modifiedAt = Self.fileModificationDate(path: outputPath)
                let hasCurrentRunOutput: Bool = {
                    if let baselineModifiedAt {
                        guard let modifiedAt else { return false }
                        return modifiedAt > baselineModifiedAt
                    }
                    return modifiedAt != nil
                }()
                let displayedOutputBytes = hasCurrentRunOutput ? outputBytes : 0
                await MainActor.run {
                    guard let self else { return }
                    self.updateJob(jobID) { job in
                        job.outputBytes = displayedOutputBytes
                    }
                    guard self.activeSearchProgressJobID == jobID else { return }
                    var snapshot = self.searchProgress
                    guard snapshot.isActive else { return }
                    snapshot.stage = .searching
                    snapshot.outputBytes = displayedOutputBytes
                    snapshot.status = displayedOutputBytes > 0 ? writingStatus : activeStatus
                    snapshot.lastUpdated = Date()
                    self.searchProgress = snapshot
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopSearchProgressMonitor(jobID: BlastJobRecord.ID) {
        searchProgressTasks[jobID]?.cancel()
        searchProgressTasks[jobID] = nil
    }

    private func stopSearchProgressMonitor() {
        for task in searchProgressTasks.values {
            task.cancel()
        }
        searchProgressTasks.removeAll()
    }

    private func finishSearchProgress(
        exitCode: Int32,
        report: BlastResultReport?,
        outputPath: String,
        jobID: BlastJobRecord.ID
    ) {
        guard activeSearchProgressJobID == jobID else { return }
        var snapshot = searchProgress
        snapshot.hasActivity = true
        snapshot.isActive = false
        snapshot.stage = killedJobIDs.contains(jobID) ? .failed : (exitCode == 0 ? .finished : .failed)
        snapshot.outputBytes = fileSize(path: outputPath)
        snapshot.hitCount = report?.hitCount ?? 0
        snapshot.noHits = report?.noHits ?? false
        snapshot.status = killedJobIDs.contains(jobID) ? "Job killed" : searchCompletionStatus(exitCode: exitCode, report: report)
        snapshot.lastUpdated = Date()
        searchProgress = snapshot
    }

    private func failSearchProgress(_ message: String, outputPath: String, jobID: BlastJobRecord.ID? = nil) {
        if let jobID, activeSearchProgressJobID != jobID {
            return
        }
        var snapshot = searchProgress
        snapshot.hasActivity = true
        snapshot.isActive = false
        snapshot.stage = .failed
        snapshot.status = message
        snapshot.outputBytes = outputPath.isEmpty ? snapshot.outputBytes : fileSize(path: outputPath)
        snapshot.startedAt = snapshot.startedAt ?? Date()
        snapshot.lastUpdated = Date()
        searchProgress = snapshot
    }

    private func searchCompletionStatus(exitCode: Int32, report: BlastResultReport?) -> String {
        guard exitCode == 0 else {
            return "BLAST exited with code \(exitCode)"
        }
        guard let report else {
            return "Search finished; no result file content was found"
        }
        if report.noHits {
            return "Search complete: no hits found"
        }
        if report.hitCount > 0 {
            return "Search complete: \(report.hitCount.formatted()) hits"
        }
        return "Search complete"
    }

    private func runningSearchLog(
        command: BlastCommand,
        configuration: BlastSearchConfiguration,
        queryLength: Int?,
        outputPath: String
    ) -> String {
        let queryLengthText = queryLength.map { "\($0.formatted()) letters" } ?? "unknown length"
        let searchTarget = searchTargetDescription(for: configuration)
        return """
        Sequence submitted.
        Program: \(configuration.program.displayName)
        Query: \(queryLengthText)
        Search set: \(searchTarget)
        Output: \(outputPath)

        Running \(command.preview)
        """
    }

    private func completedSearchLog(
        exitCode: Int32,
        diagnostics: String,
        report: BlastResultReport?,
        outputPath: String
    ) -> String {
        var lines = [
            "Finished with exit code \(exitCode).",
            "Output: \(outputPath)",
            "Output size: \(ByteCountFormatter.string(fromByteCount: fileSize(path: outputPath), countStyle: .file))"
        ]

        if let report {
            if report.noHits {
                lines.append("Result: no hits found.")
            } else if report.hitCount > 0 {
                lines.append("Result: \(report.hitCount.formatted()) hits parsed.")
            } else {
                lines.append("Result: report loaded.")
            }
        } else {
            lines.append("Result: no result file content was found.")
        }

        if !diagnostics.isEmpty {
            lines.append("")
            lines.append("Diagnostics:")
            lines.append(diagnostics)
        }
        return lines.joined(separator: "\n")
    }

    private func linkedStructureGroupTitle(program: BlastProgram) -> String {
        let fileName = structureInputPath.isEmpty
            ? "Structure"
            : URL(fileURLWithPath: structureInputPath).deletingPathExtension().lastPathComponent
        return "\(fileName) \(program.displayName) chains"
    }

    private func structureJobTitle(chain: ProteinChainSequence, label: String) -> String {
        let fileName = structureInputPath.isEmpty
            ? chain.sourceName
            : URL(fileURLWithPath: structureInputPath).deletingPathExtension().lastPathComponent
        return "\(fileName) chain \(chain.chainID) \(label)"
    }

    private func structureOutputPath(basePath: String, chain: ProteinChainSequence, label: String, index: Int) -> String {
        let trimmed = basePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? defaultBlastOutputPath(for: configuration.program) : trimmed
        let url = URL(fileURLWithPath: base)
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? "txt" : url.pathExtension
        let safeLabel = label
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let safeChain = chain.chainID.isEmpty ? "\(index + 1)" : chain.chainID
        return directory
            .appendingPathComponent("\(baseName)-chain-\(safeChain)-\(safeLabel)")
            .appendingPathExtension(fileExtension)
            .path
    }

    private func materializedStructureChainPath(chain: ProteinChainSequence, label: String) throws -> String {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalBlastStudio", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let safeLabel = label
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let safeChain = chain.chainID.isEmpty ? "unknown" : chain.chainID
        let fileURL = tempDirectory.appendingPathComponent("structure-chain-\(safeChain)-\(safeLabel)-\(UUID().uuidString).fasta")
        try chain.fastaRecord(label: label).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    func loadHelpForSelectedProgram() async {
        let executableName = configuration.alignMultipleSequences
            ? MultipleSequenceAlignmentCommandBuilder.executableName
            : configuration.program.executableName
        guard let executable = ProcessClient.resolveExecutable(named: executableName, preferences: preferences) else {
            helpText = LocalBlastError.toolMissing(executableName).localizedDescription
            return
        }
        do {
            let arguments = configuration.alignMultipleSequences ? ["--help"] : ["-help"]
            let result = try await Task.detached {
                try ProcessClient.runSync(executableURL: executable, arguments: arguments)
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
        let defaultIdentifier = filenamePrefix == "query" ? "Query_1" : "Subject_1"
        try normalizedFASTA(from: sequence, defaultIdentifier: defaultIdentifier)
            .write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    private func normalizedFASTA(from sequence: String, defaultIdentifier: String) -> String {
        let trimmed = sequence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix(">") else {
            return trimmed.hasSuffix("\n") ? trimmed : "\(trimmed)\n"
        }

        let residues = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return ">\(defaultIdentifier)\n\(wrappedSequence(residues))\n"
    }

    private func wrappedSequence(_ sequence: String, width: Int = 80) -> String {
        var lines: [String] = []
        var current = ""
        var count = 0
        for character in sequence {
            current.append(character)
            count += 1
            if count == width {
                lines.append(current)
                current = ""
                count = 0
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines.joined(separator: "\n")
    }

    private func sequenceResidueCount(filePath: String) -> Int? {
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        let count = Self.sequenceResidueCount(in: text)
        return count > 0 ? count : nil
    }

    private func fastaRecordCount(filePath: String) -> Int {
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return 0
        }
        return text
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">") }
            .count
    }

    private static func sequenceResidueCount(in text: String) -> Int {
        text.components(separatedBy: .newlines).reduce(0) { total, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix(">") else { return total }
            return total + trimmed.filter { !$0.isWhitespace }.count
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var resultsSidebarWidth: CGFloat = 300
    @State private var resizeStartWidth: CGFloat?
    @State private var lastAppliedResizeWidth: CGFloat?

    private let resultsMinimumWidth: CGFloat = 260
    private let resultsMaximumWidth: CGFloat = 720
    private let detailMinimumWidth: CGFloat = 540
    private let resizeCoordinateSpace = "ResultsSplitResizeSpace"

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTopBar()
            Divider()
            GeometryReader { proxy in
                let clampedWidth = clampedResultsWidth(for: proxy.size.width)
                HStack(spacing: 0) {
                    ResultsSidebarPanel()
                        .frame(width: clampedWidth)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    SplitResizeHandle()
                        .gesture(resizeGesture(totalWidth: proxy.size.width))
                    workspaceDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                }
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .coordinateSpace(name: resizeCoordinateSpace)
            }
        }
    }

    private func clampedResultsWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(resultsSidebarWidth, resultsMinimumWidth), availableMaximumResultsWidth(for: totalWidth))
    }

    private func availableMaximumResultsWidth(for totalWidth: CGFloat) -> CGFloat {
        max(resultsMinimumWidth, min(resultsMaximumWidth, totalWidth - detailMinimumWidth))
    }

    private func resizeGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(resizeCoordinateSpace))
            .onChanged { value in
                if resizeStartWidth == nil {
                    resizeStartWidth = clampedResultsWidth(for: totalWidth)
                    lastAppliedResizeWidth = resizeStartWidth
                }

                let stableTranslation = value.location.x - value.startLocation.x
                let proposedWidth = ((resizeStartWidth ?? resultsSidebarWidth) + stableTranslation).rounded()
                let nextWidth = min(
                    max(proposedWidth, resultsMinimumWidth),
                    availableMaximumResultsWidth(for: totalWidth)
                )
                guard lastAppliedResizeWidth != nextWidth else { return }

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    resultsSidebarWidth = nextWidth
                    lastAppliedResizeWidth = nextWidth
                }
            }
            .onEnded { _ in
                resizeStartWidth = nil
                lastAppliedResizeWidth = nil
            }
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        switch model.section {
        case .run:
            RunBlastView(showsHeader: false)
        case .sequence:
            SequenceToolsView()
        case .rnaSeq:
            RNASeqView(showsHeader: false)
        case .results:
            ResultsView()
        case .databases:
            DatabasesView(showsHeader: false)
        case .tools:
            ToolsView(showsHeader: false)
        }
    }
}

struct SplitResizeHandle: View {
    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
            .help("Drag to resize results")
    }
}

struct WorkspaceTopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            HStack {
                Label("BLAST Studio", systemImage: "atom")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(WorkspaceSection.topBarSections) { section in
                    Button {
                        model.section = section
                    } label: {
                        Label(section.rawValue, systemImage: section.systemImage)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .buttonStyle(TopBarSectionButtonStyle(isSelected: model.section == section))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.regularMaterial)
    }
}

struct TopBarSectionButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private func databaseEntrySort(_ lhs: BlastDatabaseEntry, _ rhs: BlastDatabaseEntry) -> Bool {
    let lhsRank = RecommendedBlastDatabases.rank(for: lhs.name)
    let rhsRank = RecommendedBlastDatabases.rank(for: rhs.name)
    if lhsRank != rhsRank { return lhsRank < rhsRank }
    if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled && !rhs.isInstalled }
    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

struct ResultsSidebarPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                resultsHeader
                if model.jobs.isEmpty {
                    ContentUnavailableView(
                        "No BLAST jobs yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Run a search or open a saved result file.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.jobs) { job in
                            jobRow(job)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            model.refreshResultFiles()
            model.loadSelectedJobResult()
        }
        .onChange(of: model.selectedJobID) { _, _ in
            model.loadSelectedJobResult()
        }
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Results", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Text("\(model.jobs.count.formatted())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshResultFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh result files")

                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["txt", "tsv", "out", "aln", "clu"]) {
                        model.importResultFile(path)
                        model.section = .results
                    }
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Open result file")
            }

            if model.selectedResultCount > 1 {
                Text("\(model.selectedResultCount.formatted()) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        if let path = OpenPanel.chooseDirectory() {
                            model.exportSelectedResults(to: path)
                        }
                    } label: {
                        Label("Export Selected (\(model.selectedResultCount.formatted()))", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.selectedResultCount == 0)

                    Button {
                        if let path = OpenPanel.chooseDirectory() {
                            model.exportAllResults(to: path)
                        }
                    } label: {
                        Label("Export All", systemImage: "tray.and.arrow.up")
                    }
                    .disabled(model.jobs.isEmpty)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.jobs.isEmpty)
                .help("Export selected or all results")

                Button(role: .destructive) {
                    model.deleteSelectedResults()
                } label: {
                    Label(model.selectedResultCount > 1 ? "Delete \(model.selectedResultCount.formatted())" : "Delete", systemImage: "trash")
                }
                .disabled(model.selectedResultCount == 0)
                .help("Delete selected results")

                Button(role: .destructive) {
                    if AppDialog.confirmDeleteAllResults(count: model.jobs.count) {
                        model.deleteAllResults()
                    }
                } label: {
                    Label("Delete All", systemImage: "trash.circle")
                }
                .disabled(model.jobs.isEmpty)
                .help("Delete all results")
            }
            .controlSize(.small)
        }
    }

    private func jobRow(_ job: BlastJobRecord) -> some View {
        let isSelected = model.selectedJobIDs.contains(job.id)
        let isPrimary = model.selectedJobID == job.id
        let usesSelectionActions = isSelected && model.selectedResultCount > 1
        return HStack(alignment: .center, spacing: 8) {
            ResultJobRow(job: job)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.isJobRunning(job.id) {
                Button(role: .destructive) {
                    model.killJob(job.id)
                } label: {
                    Image(systemName: "xmark.octagon")
                }
                .buttonStyle(.borderless)
                .help("Kill this running job")
            } else {
                Button {
                    model.deleteResult(job)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .help("Delete this result (moves the file to Trash)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .textBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPrimary ? Color.accentColor.opacity(0.65) : (isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12)))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let modifierFlags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            model.selectJob(
                job,
                extendingRange: modifierFlags.contains(.shift),
                togglingSelection: modifierFlags.contains(.command)
            )
            model.section = .results
        }
        .contextMenu {
            Button {
                model.selectJob(job)
                model.section = .results
            } label: {
                Label("Open Result", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                if let path = OpenPanel.chooseDirectory() {
                    if usesSelectionActions {
                        model.exportSelectedResults(to: path)
                    } else {
                        model.exportResult(job, to: path)
                    }
                }
            } label: {
                Label(
                    usesSelectionActions ? "Export Selected (\(model.selectedResultCount.formatted()))" : "Export Result",
                    systemImage: "square.and.arrow.up"
                )
            }

            Divider()

            Button(role: .destructive) {
                if usesSelectionActions {
                    model.deleteSelectedResults()
                } else {
                    model.deleteResult(job)
                }
            } label: {
                Label(
                    usesSelectionActions ? "Delete Selected (\(model.selectedResultCount.formatted()))" : "Delete Result",
                    systemImage: "trash"
                )
            }
            .disabled(!usesSelectionActions && model.isJobRunning(job.id))
        }
    }
}

struct RunBlastView: View {
    @EnvironmentObject private var model: AppModel
    var showsHeader = true
    @State private var isStructureDropTargeted = false

    var availableDatabases: [BlastDatabaseEntry] {
        model.databaseCatalog
            .filter { $0.kind == model.configuration.program.databaseKind || model.configuration.program.databaseKind == .mixed || $0.kind == .mixed }
            .sorted(by: databaseEntrySort)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HeaderBar(
                    title: "Local BLAST",
                    subtitle: "\(model.configuration.program.summary) Everything runs through local BLAST+ binaries."
                ) {
                    Button {
                        Task { await model.loadHelpForSelectedProgram() }
                    } label: {
                        Label("Load CLI Help", systemImage: "questionmark.circle")
                    }
                    .help("Load the full -help output for the selected search tool.")
                }
            }

            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            runControls
                            runSidebar
                        }
                        .padding(16)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            runControls
                                .padding(16)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        Divider()

                        ScrollView {
                            runSidebar
                                .padding(16)
                        }
                        .frame(width: min(max(proxy.size.width * 0.38, 420), 620))
                    }
                }
            }
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            programSection
            querySection
            if model.configuration.program.isIgBlast {
                igBlastSection
            } else if model.configuration.alignMultipleSequences {
                multipleAlignmentSection
            } else if model.configuration.alignTwoSequences {
                subjectSection
            } else {
                databaseSection
            }
            if !model.configuration.alignMultipleSequences {
                ParameterEditorView(program: model.configuration.program, values: $model.configuration.optionValues)
            }
            advancedSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            commandPreview
            if model.searchProgress.hasActivity {
                searchProgressPanel
            }
            outputSection
            blastResultsSection
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
            LabeledContent(model.configuration.alignMultipleSequences ? "Mode" : "Database") {
                Text(databaseKindLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var databaseKindLabel: String {
        if model.configuration.program.isIgBlast {
            return model.configuration.program == .igblastn ? "Germline V(D)J databases" : "Germline V database"
        }
        if model.configuration.alignMultipleSequences {
            return "Multiple alignment"
        }
        return model.configuration.alignTwoSequences ? "Subject sequence" : model.configuration.program.databaseKind.rawValue
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
                queryTransformMenu
            }

            SequenceTextEditor(
                text: $model.configuration.queryText,
                placeholder: model.configuration.alignMultipleSequences
                    ? "Paste FASTA containing three or more sequences"
                    : "Paste FASTA here when no query file is selected"
            )

            if model.supportsStructureQueryImport, !model.configuration.alignMultipleSequences {
                structureImportSection
            }

            HStack {
                TextField("Query range, e.g. 1-250", text: $model.configuration.querySubrange)
                    .textFieldStyle(.roundedBorder)
                if model.configuration.program.supportsPairwiseAlignment {
                    Toggle("Align two sequences", isOn: Binding(
                        get: { model.configuration.alignTwoSequences },
                        set: { model.setPairwiseAlignmentEnabled($0) }
                    ))
                        .toggleStyle(.checkbox)
                    if model.configuration.program.supportsMultipleSequenceAlignment {
                        Toggle("Align 3+ sequences", isOn: Binding(
                            get: { model.configuration.alignMultipleSequences },
                            set: { model.setMultipleSequenceAlignmentEnabled($0) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                } else {
                    Label("Germline assignment", systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentQueryText: String {
        let pasted = model.configuration.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pasted.isEmpty { return model.configuration.queryText }
        return (try? String(contentsOfFile: model.configuration.queryFilePath, encoding: .utf8)) ?? ""
    }

    private var queryTransformMenu: some View {
        Menu {
            Button {
                let rc = SequenceTools.reverseComplement(currentQueryText)
                if !rc.isEmpty {
                    model.configuration.queryFilePath = ""
                    model.configuration.queryText = rc
                }
            } label: {
                Label("Reverse complement (in place)", systemImage: "arrow.left.and.right")
            }
            Divider()
            Button {
                model.openSequenceTool(.translate, with: currentQueryText)
            } label: {
                Label("Translate…", systemImage: "arrow.right.square")
            }
            Button {
                model.openSequenceTool(.reverseComplement, with: currentQueryText)
            } label: {
                Label("Open in Reverse Complement…", systemImage: "arrow.left.and.right")
            }
            Button {
                model.openSequenceTool(.protParam, with: currentQueryText)
            } label: {
                Label("ProtParam…", systemImage: "atom")
            }
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Transform the query sequence with the Sequence tools")
    }

    private var multipleAlignmentSection: some View {
        Panel(title: "Multiple Sequence Alignment", systemImage: "text.alignleft") {
            if let clustalOmegaStatus {
                Label(
                    clustalOmegaStatus.isAvailable ? "Clustal Omega ready" : "Clustal Omega missing",
                    systemImage: clustalOmegaStatus.isAvailable ? "checkmark.circle.fill" : "xmark.octagon.fill"
                )
                .foregroundStyle(clustalOmegaStatus.isAvailable ? .green : .orange)
                .font(.callout.weight(.semibold))
                if clustalOmegaStatus.isAvailable {
                    Text(clustalOmegaStatus.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("Install Clustal Omega (`clustalo`) and use Tools > Recheck. Homebrew: `brew install clustal-omega`. Conda: `conda install -c bioconda clustalo`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Engine")
                        .foregroundStyle(.secondary)
                    Text("Clustal Omega")
                }
                GridRow {
                    Text("Sequence type")
                        .foregroundStyle(.secondary)
                    Text(model.configuration.program == .blastn ? "DNA" : "Protein")
                }
                GridRow {
                    Text("Output format")
                        .foregroundStyle(.secondary)
                    Text("Clustal")
                }
            }
            .font(.callout)
        }
    }

    private var clustalOmegaStatus: ToolStatus? {
        model.toolStatuses.first { $0.name == MultipleSequenceAlignmentCommandBuilder.executableName }
    }

    private var structureImportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PDB/mmCIF Structure", systemImage: "cube")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["pdb", "ent", "cif", "mmcif"]) {
                        model.importStructureFile(path)
                    }
                } label: {
                    Label("Choose", systemImage: "folder")
                }
                if !model.structureChains.isEmpty {
                    Button {
                        model.clearStructureFile()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if model.structureChains.isEmpty {
                    Text(model.configuration.program == .igblastp
                        ? "Drop a PDB or mmCIF file. IgBLASTP will use chain A as LC and chain B as HC."
                        : "Drop a PDB or mmCIF file. BLASTP will run each protein chain as a linked job.")
                    .foregroundStyle(.secondary)
                } else {
                    Text(URL(fileURLWithPath: model.structureInputPath).lastPathComponent)
                        .font(.caption.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(model.structureChains) { chain in
                            Label("Chain \(chain.chainID): \(chain.sequence.count) aa", systemImage: chainRoleIcon(chain))
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    if !model.structureImportLog.isEmpty {
                        Text(model.structureImportLog)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isStructureDropTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isStructureDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isStructureDropTargeted) { providers in
                handleStructureDrop(providers)
            }
        }
    }

    private func chainRoleIcon(_ chain: ProteinChainSequence) -> String {
        if model.configuration.program == .igblastp {
            if chain.chainID.caseInsensitiveCompare("A") == .orderedSame { return "l.circle" }
            if chain.chainID.caseInsensitiveCompare("B") == .orderedSame { return "h.circle" }
        }
        return "circle.hexagongrid"
    }

    private func handleStructureDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in
                model.importStructureFile(url.path)
            }
        }
        return true
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
                    let recommendation = RecommendedBlastDatabases.label(for: database.name).map { " - \($0)" } ?? ""
                    Text("\(database.name)\(recommendation)\(database.isInstalled ? "" : " - not installed")")
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

    private var igBlastSection: some View {
        Panel(title: "IgBLAST Germline Setup", systemImage: "scope") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    Text("Organism")
                        .frame(width: 152, alignment: .leading)
                    TextField("human", text: $model.configuration.igBlast.organism)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Sequence type")
                        .frame(width: 152, alignment: .leading)
                    Picker("Sequence type", selection: $model.configuration.igBlast.sequenceType) {
                        Text("Immunoglobulin").tag("Ig")
                        Text("T cell receptor").tag("TCR")
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("IGDATA directory")
                        .frame(width: 152, alignment: .leading)
                    HStack {
                        TextField("Folder containing internal_data and optional_file", text: $model.configuration.igBlast.igDataDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            if let path = OpenPanel.chooseDirectory() {
                                model.configuration.igBlast.igDataDirectory = path
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose the IgBLAST release support-data folder.")
                    }
                }
                GridRow {
                    Color.clear.frame(width: 152, height: 0)
                    Text("IgBLAST uses IGDATA to find internal_data and optional_file support files. Leave it empty if your shell environment already provides IGDATA.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Germline V database")
                        .frame(width: 152, alignment: .leading)
                    TextField("database/human_gl_V or an absolute database prefix", text: $model.configuration.igBlast.germlineVDatabase)
                        .textFieldStyle(.roundedBorder)
                }
                if model.configuration.program == .igblastn {
                    GridRow {
                        Text("Germline D database")
                            .frame(width: 152, alignment: .leading)
                        TextField("database/human_gl_D", text: $model.configuration.igBlast.germlineDDatabase)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Germline J database")
                            .frame(width: 152, alignment: .leading)
                        TextField("database/human_gl_J", text: $model.configuration.igBlast.germlineJDatabase)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("C region database")
                            .frame(width: 152, alignment: .leading)
                        TextField("Optional constant-region database prefix", text: $model.configuration.igBlast.cRegionDatabase)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Auxiliary data")
                            .frame(width: 152, alignment: .leading)
                        HStack {
                            TextField("optional_file/human_gl.aux", text: $model.configuration.igBlast.auxiliaryDataPath)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                if let path = OpenPanel.chooseFile(allowedExtensions: ["aux", "txt"]) {
                                    model.configuration.igBlast.auxiliaryDataPath = path
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help("Choose an IgBLAST auxiliary data file.")
                        }
                    }
                }
                GridRow {
                    Text("Additional database")
                        .frame(width: 152, alignment: .leading)
                    Picker("Additional database", selection: $model.configuration.igBlast.additionalDatabaseName) {
                        Text("None").tag("")
                        ForEach(availableDatabases) { database in
                            Text("\(database.name)\(database.isInstalled ? "" : " - not installed")")
                                .tag(database.name)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Color.clear.frame(width: 152, height: 0)
                    TextField("Additional database name or path", text: $model.configuration.igBlast.additionalDatabaseName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Additional DB dir")
                        .frame(width: 152, alignment: .leading)
                    HStack {
                        TextField("BLASTDB folder for the optional additional database", text: $model.configuration.igBlast.additionalDatabaseDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            if let path = OpenPanel.chooseDirectory() {
                                model.configuration.igBlast.additionalDatabaseDirectory = path
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                }
                GridRow {
                    Color.clear.frame(width: 152, height: 0)
                    Text("The V database is required. D, J, C, auxiliary data, and an additional search database can be supplied when your IgBLAST release or assay needs them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var advancedSection: some View {
        Panel(title: "Advanced", systemImage: "terminal") {
            TextField(advancedPlaceholder, text: $model.configuration.rawArguments)
                .textFieldStyle(.roundedBorder)
            Text(advancedHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedPlaceholder: String {
        model.configuration.alignMultipleSequences
            ? "Raw Clustal Omega arguments, e.g. --iterations=2"
            : "Raw BLAST+/IgBLAST arguments, e.g. -dbsize 1000000 -parse_deflines"
    }

    private var advancedHelpText: String {
        model.configuration.alignMultipleSequences
            ? "Raw arguments are appended last for clustalo. The app does not add --threads automatically because many Clustal Omega builds do not support OpenMP thread overrides."
            : "Raw arguments are appended last, so they can cover BLAST+ and IgBLAST switches that are not exposed as structured controls yet."
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
                Label(model.searchCapacityLabel, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(model.canStartSearch ? Color.secondary : Color.orange)
                Spacer()
            }
            HStack {
                Button {
                    Task { await model.runSearch() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartSearch)

                if model.isRunningSearch {
                    Button(role: .destructive) {
                        model.killAllRunningJobs()
                    } label: {
                        Label("Kill Running", systemImage: "xmark.octagon")
                    }
                }

                Button {
                    if let path = OpenPanel.saveFile(defaultName: model.configuration.alignMultipleSequences ? "alignment.aln" : "blast-result.txt") {
                        model.configuration.outputPath = path
                    }
                } label: {
                    Label("Output", systemImage: "square.and.arrow.down")
                }

                if !showsHeader {
                    Button {
                        Task { await model.loadHelpForSelectedProgram() }
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("Load the full -help output for the selected search tool.")
                }
            }
        }
    }

    private var outputSection: some View {
        Panel(title: "Output", systemImage: "doc.badge.gearshape") {
            TextField("Output file", text: $model.configuration.outputPath)
        }
    }

    private var searchProgressPanel: some View {
        let progress = model.searchProgress
        return Panel(title: "Search Progress", systemImage: "waveform.path.ecg") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.stage.rawValue)
                        .font(.headline)
                    Text(progress.status)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if progress.isActive {
                    Label("Active", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else if progress.stage == .failed {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                SearchStepIndicator(
                    label: "Submitted",
                    systemImage: "paperplane.fill",
                    isActive: progress.stage == .submitted,
                    isComplete: searchStageRank(progress.stage) > searchStageRank(.submitted)
                )
                SearchStepIndicator(
                    label: "Search",
                    systemImage: "magnifyingglass",
                    isActive: progress.stage == .searching,
                    isComplete: searchStageRank(progress.stage) > searchStageRank(.searching)
                )
                SearchStepIndicator(
                    label: "Results",
                    systemImage: "doc.text.magnifyingglass",
                    isActive: progress.stage == .formatting,
                    isComplete: progress.stage == .finished
                )
            }

            if let fraction = progress.fractionComplete {
                ProgressView(value: fraction)
            } else if progress.isActive {
                ProgressView()
            } else {
                ProgressView(value: progress.stage == .finished ? 1 : 0)
            }

            HStack(spacing: 12) {
                SummaryMetric(label: "Query", value: queryLengthLabel(progress.queryLength))
                SummaryMetric(label: "Database", value: progress.database.isEmpty ? "--" : progress.database)
                SummaryMetric(label: "Output", value: byteLabel(progress.outputBytes))
                SummaryMetric(label: "Elapsed", value: durationLabel(progress.elapsed))
            }

            if progress.hitCount > 0 || progress.noHits {
                Label(progress.noHits ? "No hits found" : "\(progress.hitCount.formatted()) hits parsed", systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(progress.noHits ? Color.secondary : Color.green)
            }
        }
    }

    @ViewBuilder
    private var blastResultsSection: some View {
        if let report = model.blastResultReport, report.hasVisibleResults {
            BlastResultReportView(
                report: report,
                fallbackProgram: model.configuration.program.displayName,
                fallbackDatabase: model.searchProgress.database
            )
        } else if model.searchProgress.hasActivity, !model.isRunningSearch {
            Panel(title: "BLAST Results", systemImage: "target") {
                ContentUnavailableView("No BLAST results", systemImage: "doc.text.magnifyingglass")
                    .frame(minHeight: 120)
            }
        }
    }

    private func resultSummary(_ report: BlastResultReport) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Program").foregroundStyle(.secondary)
                Text(report.program.isEmpty ? model.configuration.program.displayName : report.program)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !report.query.isEmpty || report.queryLength != nil {
                GridRow {
                    Text("Query").foregroundStyle(.secondary)
                    Text(querySummaryLabel(report))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            GridRow {
                Text("Database").foregroundStyle(.secondary)
                Text(report.database.isEmpty ? model.searchProgress.database : report.database)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !report.databaseSummary.isEmpty {
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    Text(report.databaseSummary)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private func hitDescriptions(_ hits: [BlastResultHit]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Descriptions")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Hit").bold()
                    Text("Score").bold()
                    Text("E-value").bold()
                }
                ForEach(Array(hits.prefix(20).enumerated()), id: \.offset) { _, hit in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title)
                                .lineLimit(2)
                            if !hit.identity.isEmpty || !hit.queryCover.isEmpty {
                                Text([hit.identity, hit.queryCover].filter { !$0.isEmpty }.joined(separator: "  "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(hit.scoreBits.isEmpty ? "--" : hit.scoreBits)
                            .font(.system(.caption, design: .monospaced))
                        Text(hit.eValue.isEmpty ? "--" : hit.eValue)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            if hits.count > 20 {
                Text("+ \(hits.count - 20) more descriptions in the raw report")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tabularPreview(_ report: BlastResultReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tabular Hits")
                .font(.headline)
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(report.tabularHeaders.enumerated()), id: \.offset) { _, header in
                            Text(header)
                                .bold()
                                .lineLimit(1)
                        }
                    }
                    ForEach(Array(report.tabularRows.prefix(20).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                Text(value)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            if report.tabularRows.count > 20 {
                Text("+ \(report.tabularRows.count - 20) more rows in the raw report")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alignmentPreview(_ alignments: [BlastAlignmentSection]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alignments")
                .font(.headline)
            ForEach(Array(alignments.prefix(8).enumerated()), id: \.offset) { index, alignment in
                VStack(alignment: .leading, spacing: 6) {
                    Text(alignment.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        if !alignment.scoreBits.isEmpty {
                            Label(alignment.scoreBits, systemImage: "sum")
                        }
                        if !alignment.eValue.isEmpty {
                            Label(alignment.eValue, systemImage: "number")
                        }
                        if !alignment.identities.isEmpty {
                            Label(alignment.identities, systemImage: "equal.circle")
                        }
                        if !alignment.strand.isEmpty {
                            Label(alignment.strand, systemImage: "arrow.left.arrow.right")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ScrollView([.horizontal, .vertical]) {
                        Text(alignment.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                }
                if index < min(alignments.count, 8) - 1 {
                    Divider()
                }
            }
            if alignments.count > 8 {
                Text("+ \(alignments.count - 8) more alignments in the raw report")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private func querySummaryLabel(_ report: BlastResultReport) -> String {
        let length = report.queryLength.map { " (\($0.formatted()) letters)" } ?? ""
        return "\(report.query)\(length)"
    }

    private func queryLengthLabel(_ length: Int?) -> String {
        length.map { "\($0.formatted()) letters" } ?? "--"
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func searchStageRank(_ stage: SearchStage) -> Int {
        switch stage {
        case .idle:
            0
        case .submitted:
            1
        case .searching:
            2
        case .formatting:
            3
        case .finished:
            4
        case .failed:
            4
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
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(groupOptions) { option in
                            GridRow {
                                Text(option.title)
                                    .frame(width: 168, alignment: .leading)
                                    .help(option.help)
                                control(for: option)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .help(option.help)
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
        case "IgBLAST": "scope"
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
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : Color(nsColor: .controlColor))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .help(program.summary)
    }
}

struct SearchStepIndicator: View {
    var label: String
    var systemImage: String
    var isActive: Bool
    var isComplete: Bool

    var body: some View {
        Label(label, systemImage: iconName)
            .font(.caption.weight(isActive ? .semibold : .regular))
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        if isComplete {
            return "checkmark.circle.fill"
        }
        return systemImage
    }

    private var foregroundStyle: Color {
        if isComplete {
            return .green
        }
        if isActive {
            return .blue
        }
        return .secondary
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

            SequencePlainTextView(text: $text)
                .padding(6)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 132)
    }
}

struct SequencePlainTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.font = Self.sequenceFont
        textView.defaultParagraphStyle = Self.sequenceParagraphStyle
        textView.typingAttributes = Self.typingAttributes
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byCharWrapping
        applySequenceAttributes(to: textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = Self.sequenceFont
        textView.defaultParagraphStyle = Self.sequenceParagraphStyle
        textView.typingAttributes = Self.typingAttributes
        textView.textContainer?.lineBreakMode = .byCharWrapping
        applySequenceAttributes(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private static var sequenceFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private static var sequenceParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.hyphenationFactor = 0
        return style
    }

    private static var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: sequenceFont,
            .paragraphStyle: sequenceParagraphStyle
        ]
    }

    private func applySequenceAttributes(to textView: NSTextView) {
        let length = (textView.string as NSString).length
        guard length > 0 else { return }
        textView.textStorage?.addAttributes(Self.typingAttributes, range: NSRange(location: 0, length: length))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

struct RNASeqView: View {
    @EnvironmentObject private var model: AppModel
    var showsHeader = true

    private let supportedPrograms: [BlastProgram] = [.blastn, .blastx]

    private var availableDatabases: [BlastDatabaseEntry] {
        model.databaseCatalog
            .filter { $0.kind == model.rnaSeqConfiguration.program.databaseKind }
            .sorted(by: databaseEntrySort)
    }

    private var inputSize: Int64 {
        model.rnaSeqConfiguration.inputFiles.reduce(Int64(0)) { total, path in
            total + fileSize(path: path)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HeaderBar(
                    title: "RNA-Seq Annotation",
                    subtitle: "Stream large trimmed and merged FASTQ files into local BLAST annotation jobs."
                ) { }
            }

            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            mainColumn
                            sideColumn
                        }
                        .padding(16)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            mainColumn
                                .padding(16)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        Divider()

                        ScrollView {
                            sideColumn
                                .padding(16)
                        }
                        .frame(width: min(max(proxy.size.width * 0.38, 420), 620))
                    }
                }
            }
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputPanel
            searchPanel
            outputSpecPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            progressPanel
            commandPanel
            logPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputPanel: some View {
        Panel(title: "FASTQ Inputs", systemImage: "doc.on.doc") {
            HStack {
                Button {
                    let paths = OpenPanel.chooseFiles(allowedExtensions: ["fq", "fastq", "gz", "txt"])
                    model.addRNASeqInputFiles(paths)
                } label: {
                    Label("Add FASTQ Files", systemImage: "plus")
                }
                Button {
                    model.clearRNASeqInputFiles()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(model.rnaSeqConfiguration.inputFiles.isEmpty || model.isRunningRNASeq)
                Spacer()
                Text(byteLabel(inputSize))
                    .foregroundStyle(.secondary)
            }

            List(model.rnaSeqConfiguration.inputFiles, id: \.self) { path in
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Text(byteLabel(fileSize(path: path)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.removeRNASeqInputFile(path)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRunningRNASeq)
                }
                .padding(.vertical, 3)
            }
            .frame(minHeight: 160)
            .overlay {
                if model.rnaSeqConfiguration.inputFiles.isEmpty {
                    ContentUnavailableView("No FASTQ files selected", systemImage: "doc.badge.plus")
                }
            }
        }
    }

    private var searchPanel: some View {
        Panel(title: "Annotation Search", systemImage: "scope") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(supportedPrograms) { program in
                    ProgramChoiceButton(
                        program: program,
                        isSelected: model.rnaSeqConfiguration.program == program
                    ) {
                        model.setRNASeqProgram(program)
                    }
                }
            }

            Picker("Catalog database", selection: $model.rnaSeqConfiguration.databaseName) {
                ForEach(availableDatabases) { database in
                    Text("\(database.name)\(database.isInstalled ? "" : " - not installed")")
                        .tag(database.name)
                }
            }
            TextField("Database name or path", text: $model.rnaSeqConfiguration.databaseName)
                .textFieldStyle(.roundedBorder)

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

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                if model.rnaSeqConfiguration.program == .blastn {
                    GridRow {
                        Text("BLASTN task")
                            .frame(width: 130, alignment: .leading)
                        Picker("BLASTN task", selection: $model.rnaSeqConfiguration.blastnTask) {
                            Text("blastn").tag("blastn")
                            Text("megablast").tag("megablast")
                            Text("dc-megablast").tag("dc-megablast")
                        }
                        .labelsHidden()
                    }
                }
                GridRow {
                    Text("E-value")
                        .frame(width: 130, alignment: .leading)
                    TextField("1e-5", text: $model.rnaSeqConfiguration.evalue)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Max hits/read")
                        .frame(width: 130, alignment: .leading)
                    TextField("10", text: $model.rnaSeqConfiguration.maxTargetSequences)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("CPU threads")
                        .frame(width: 130, alignment: .leading)
                    TextField("4", text: $model.rnaSeqConfiguration.numThreads)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var outputSpecPanel: some View {
        Panel(title: "Output Specification", systemImage: "tablecells") {
            HStack {
                TextField("Output TSV file", text: $model.rnaSeqConfiguration.outputPath)
                Button {
                    if let path = OpenPanel.saveFile(defaultName: "rnaseq-annotations.tsv") {
                        model.rnaSeqConfiguration.outputPath = path
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(RNASeqOutputField.allCases) { field in
                    Toggle(field.label, isOn: Binding(
                        get: { model.rnaSeqConfiguration.outputFields.contains(field) },
                        set: { selected in
                            if selected {
                                model.rnaSeqConfiguration.outputFields.insert(field)
                            } else {
                                model.rnaSeqConfiguration.outputFields.remove(field)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }

            LabeledContent("BLAST outfmt 6") {
                Text(model.rnaSeqConfiguration.outputFieldString.isEmpty ? "No fields selected" : model.rnaSeqConfiguration.outputFieldString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("Keep converted FASTA beside the output", isOn: $model.rnaSeqConfiguration.keepConvertedFasta)
            TextField("Raw BLAST+ arguments", text: $model.rnaSeqConfiguration.rawArguments)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var progressPanel: some View {
        let progress = model.rnaSeqProgress
        return Panel(title: "Progress", systemImage: "chart.bar") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.stage.rawValue)
                        .font(.headline)
                    Text(progress.status)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if progress.isActive {
                    Label("Active", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            if let fraction = progress.fractionComplete {
                ProgressView(value: fraction)
                Text("\(percentLabel(fraction)) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if progress.isActive {
                ProgressView()
            } else {
                ProgressView(value: 0)
            }

            HStack(spacing: 12) {
                SummaryMetric(label: "Input", value: byteLabel(progress.totalInputBytes))
                SummaryMetric(label: "Processed", value: byteLabel(progress.processedInputBytes))
                SummaryMetric(label: "Reads", value: countLabel(progress.convertedReads))
                SummaryMetric(label: "Output", value: byteLabel(progress.outputBytes))
            }

            if !progress.currentFileName.isEmpty {
                Label(progress.currentFileName, systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Label(durationLabel(progress.elapsed), systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var commandPanel: some View {
        Panel(title: "Command Preview", systemImage: "chevron.left.forwardslash.chevron.right") {
            ScrollView(.horizontal) {
                Text(model.rnaSeqCommandPreview)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await model.runRNASeqAnalysis() }
            } label: {
                Label(model.isRunningRNASeq ? "Annotating" : "Start Annotation", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRunningRNASeq)
        }
    }

    private var logPanel: some View {
        Panel(title: "RNA-Seq Log", systemImage: "text.bubble") {
            ScrollView {
                Text(model.rnaSeqLog.isEmpty ? "No RNA-Seq annotation started." : model.rnaSeqLog)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
        }
    }

    private func fileSize(path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func countLabel(_ value: Int64) -> String {
        value.formatted()
    }

    private func percentLabel(_ fraction: Double) -> String {
        let percent = min(max(fraction * 100, 0), 100)
        return percent >= 10
            ? String(format: "%.0f%%", percent)
            : String(format: "%.1f%%", percent)
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

struct SequenceToolsView: View {
    @EnvironmentObject private var model: AppModel

    private var isProteinTool: Bool {
        model.sequenceTool == .protParam || model.sequenceTool == .backTranslate
    }
    private var cleanedInput: String {
        isProteinTool ? SequenceTools.cleanProtein(model.sequenceInput) : SequenceTools.cleanNucleotides(model.sequenceInput)
    }
    private var geneticCode: GeneticCodeTable { .table(id: model.sequenceGeneticCodeID) }
    private var codonUsage: CodonUsageTable {
        CodonUsageTable.all.first { $0.id == model.sequenceCodonUsageID } ?? .human
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            inputPanel
                            outputPanel
                        }
                        .padding(16)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView { inputPanel.padding(16) }
                            .frame(width: min(max(proxy.size.width * 0.40, 380), 560))
                        Divider()
                        ScrollView { outputPanel.padding(16) }
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $model.sequenceTool) {
                ForEach(SequenceToolKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            if model.sequenceTool == .translate {
                Picker("Genetic code", selection: $model.sequenceGeneticCodeID) {
                    ForEach(GeneticCodeTable.all) { Text($0.displayName).tag($0.id) }
                }
                .frame(maxWidth: 340)
            } else if model.sequenceTool == .backTranslate {
                Picker("Codon usage", selection: $model.sequenceCodonUsageID) {
                    ForEach(CodonUsageTable.all) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 260)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: Input

    private var inputPanel: some View {
        Panel(title: isProteinTool ? "Protein Input" : "Nucleotide Input", systemImage: "square.and.pencil") {
            HStack(spacing: 8) {
                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["fa", "fasta", "faa", "fna", "fas", "txt", "seq"]),
                       let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                        model.sequenceInput = contents
                    }
                } label: {
                    Label("Load FASTA", systemImage: "folder")
                }
                Button {
                    let query = model.configuration.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty {
                        model.sequenceInput = model.configuration.queryText
                    } else if let contents = try? String(contentsOfFile: model.configuration.queryFilePath, encoding: .utf8) {
                        model.sequenceInput = contents
                    }
                } label: {
                    Label("From Query", systemImage: "arrow.down.doc")
                }
                Button {
                    model.sequenceInput = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(model.sequenceInput.isEmpty)
                Spacer()
                Text("\(cleanedInput.count.formatted()) \(isProteinTool ? "aa" : "nt")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)

            SequenceTextEditor(
                text: $model.sequenceInput,
                placeholder: isProteinTool
                    ? "Paste a protein sequence or FASTA (single-letter amino acids)"
                    : "Paste a DNA/RNA sequence or FASTA"
            )
        }
    }

    // MARK: Output

    @ViewBuilder
    private var outputPanel: some View {
        if cleanedInput.isEmpty {
            Panel(title: model.sequenceTool.rawValue, systemImage: model.sequenceTool.systemImage) {
                ContentUnavailableView(
                    isProteinTool ? "Enter a protein sequence" : "Enter a nucleotide sequence",
                    systemImage: model.sequenceTool.systemImage,
                    description: Text("Results update as you type.")
                )
                .frame(minHeight: 220)
            }
        } else {
            switch model.sequenceTool {
            case .translate: translateOutput
            case .reverseComplement: reverseComplementOutput
            case .backTranslate: backTranslateOutput
            case .protParam: protParamOutput
            }
        }
    }

    private var translateOutput: some View {
        let frames = SequenceTools.sixFrameTranslation(model.sequenceInput, code: geneticCode)
        let orfs = SequenceTools.findORFs(model.sequenceInput, code: geneticCode, minLength: 20)
        return VStack(alignment: .leading, spacing: 12) {
            Panel(title: "Six-Frame Translation", systemImage: "arrow.right.square") {
                Text("Genetic code: \(geneticCode.displayName). Stops shown in red, Met in green.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(frames) { frame in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(frame.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            actionMenu(for: frame.protein, defaultName: frame.label)
                        }
                        styledProtein(frame.protein)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if frame.frame != -3 { Divider() }
                }
            }

            Panel(title: "Open Reading Frames", systemImage: "flag") {
                Text("Met-to-stop ORFs ≥ 20 aa across all six frames, longest first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if orfs.isEmpty {
                    Text("No ORFs ≥ 20 aa found.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(orfs.prefix(30)) { orf in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(orf.frame > 0 ? "5'3' F\(orf.frame)" : "3'5' F\(abs(orf.frame))")
                                    .font(.caption.weight(.semibold))
                                Text("nt \(orf.startNucleotide.formatted())–\(orf.endNucleotide.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(orf.length.formatted()) aa")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                actionMenu(for: orf.peptide, defaultName: "ORF \(orf.startNucleotide)-\(orf.endNucleotide)")
                            }
                            Text(orf.peptide)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                        }
                        if orf.id != orfs.prefix(30).last?.id { Divider() }
                    }
                    if orfs.count > 30 {
                        Text("+ \(orfs.count - 30) more ORFs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var reverseComplementOutput: some View {
        VStack(alignment: .leading, spacing: 12) {
            sequenceResultPanel(title: "Reverse Complement", systemImage: "arrow.left.and.right", sequence: SequenceTools.reverseComplement(model.sequenceInput))
            sequenceResultPanel(title: "Complement", systemImage: "equal", sequence: SequenceTools.complement(model.sequenceInput))
            sequenceResultPanel(title: "Reverse", systemImage: "arrow.uturn.left", sequence: SequenceTools.reverse(model.sequenceInput))
        }
    }

    private var backTranslateOutput: some View {
        let dna = SequenceTools.backTranslate(model.sequenceInput, usage: codonUsage)
        return VStack(alignment: .leading, spacing: 12) {
            sequenceResultPanel(title: "Back-translation", systemImage: "arrow.uturn.backward.square", sequence: dna, isNucleotide: true)
            Panel(title: "About", systemImage: "info.circle") {
                Text("Reverse translation is ambiguous. This uses the single most-frequent codon per residue for \(codonUsage.name), suitable as a starting point for gene synthesis — not a recovery of the original coding sequence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sequenceResultPanel(title: String, systemImage: String, sequence: String, isNucleotide: Bool = true) -> some View {
        Panel(title: title, systemImage: systemImage) {
            HStack(spacing: 8) {
                Text("\(sequence.count.formatted()) \(isNucleotide ? "nt" : "aa")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                actionMenu(for: sequence, defaultName: title, isNucleotide: isNucleotide)
            }
            .controlSize(.small)
            Text(formatBlocks(sequence).isEmpty ? "—" : formatBlocks(sequence))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: ProtParam

    @ViewBuilder
    private var protParamOutput: some View {
        if let r = ProtParam.analyze(model.sequenceInput) {
            VStack(alignment: .leading, spacing: 12) {
                Panel(title: "Summary", systemImage: "atom") {
                    HStack(spacing: 16) {
                        SummaryMetric(label: "Residues", value: r.residueCount.formatted())
                        SummaryMetric(label: "Mol. weight", value: String(format: "%.2f", r.molecularWeight))
                        SummaryMetric(label: "Theoretical pI", value: String(format: "%.2f", r.theoreticalPI))
                        SummaryMetric(label: "GRAVY", value: String(format: "%.3f", r.gravy))
                    }
                    keyValue("Formula", r.formula, mono: true)
                    keyValue("Total atoms", r.totalAtoms.formatted())
                    keyValue("Negatively charged (Asp + Glu)", r.negativeResidueCount.formatted())
                    keyValue("Positively charged (Arg + Lys)", r.positiveResidueCount.formatted())
                }

                Panel(title: "Extinction Coefficients (280 nm)", systemImage: "sun.max") {
                    Text("Computed from \(r.tyrosineCount) Tyr, \(r.tryptophanCount) Trp, \(r.cysteineCount) Cys (Edelhoch / Gill & von Hippel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyValue("Assuming all Cys form cystines", "\(r.extinctionCystine.formatted()) M⁻¹cm⁻¹   ·   Abs 0.1% = \(String(format: "%.3f", r.abs01Cystine))", mono: true)
                    keyValue("Assuming all Cys reduced", "\(r.extinctionReduced.formatted()) M⁻¹cm⁻¹   ·   Abs 0.1% = \(String(format: "%.3f", r.abs01Reduced))", mono: true)
                }

                Panel(title: "Stability & Hydropathy", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    keyValue("Instability index", String(format: "%.2f", r.instabilityIndex) + (r.isStable ? "  (stable)" : "  (unstable)"))
                    keyValue("Aliphatic index", String(format: "%.2f", r.aliphaticIndex))
                    keyValue("GRAVY", String(format: "%.3f", r.gravy))
                }

                Panel(title: "Estimated Half-life", systemImage: "clock") {
                    Text("N-terminal residue: \(ProtParam.aaNames[r.nTerminal] ?? String(r.nTerminal)) (\(String(r.nTerminal)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyValue("Mammalian (reticulocytes, in vitro)", r.halfLifeMammalian)
                    keyValue("Yeast (in vivo)", r.halfLifeYeast)
                    keyValue("E. coli (in vivo)", r.halfLifeEcoli)
                }

                Panel(title: "Amino Acid Composition", systemImage: "chart.bar") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 4) {
                        ForEach(r.composition) { entry in
                            HStack(spacing: 6) {
                                Text("\(entry.name) (\(String(entry.code)))")
                                    .font(.caption)
                                Spacer()
                                Text(entry.count.formatted())
                                    .font(.system(.caption, design: .monospaced))
                                Text(String(format: "%.1f%%", entry.percent))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        } else {
            Panel(title: "ProtParam", systemImage: "atom") {
                ContentUnavailableView(
                    "No standard residues found",
                    systemImage: "atom",
                    description: Text("Paste a protein sequence using single-letter amino-acid codes.")
                )
                .frame(minHeight: 200)
            }
        }
    }

    // MARK: Helpers

    private func keyValue(_ key: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
            Text(value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func actionMenu(for sequence: String, defaultName: String, isNucleotide: Bool = false) -> some View {
        HStack(spacing: 6) {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(sequence, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                model.useSequenceAsQuery(fastaWrapped(defaultName, sequence))
            } label: {
                Label("Use as query", systemImage: "play.circle")
            }
            if !isNucleotide {
                Button {
                    model.openSequenceTool(.protParam, with: sequence)
                } label: {
                    Label("ProtParam", systemImage: "atom")
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .labelStyle(.iconOnly)
    }

    private func fastaWrapped(_ name: String, _ sequence: String) -> String {
        ">\(name)\n\(sequence)"
    }

    private func formatBlocks(_ s: String, lineLength: Int = 60, group: Int = 10) -> String {
        guard !s.isEmpty else { return "" }
        let chars = Array(s)
        var lines: [String] = []
        var i = 0
        while i < chars.count {
            let lineEnd = min(i + lineLength, chars.count)
            var line = ""
            var j = i
            while j < lineEnd {
                let groupEnd = min(j + group, lineEnd)
                line += String(chars[j..<groupEnd])
                if groupEnd < lineEnd { line += " " }
                j = groupEnd
            }
            lines.append(line)
            i += lineLength
        }
        return lines.joined(separator: "\n")
    }

    private func styledProtein(_ s: String, lineLength: Int = 60) -> Text {
        guard !s.isEmpty else { return Text("—").foregroundColor(.secondary) }
        var attr = AttributedString()
        var buffer = ""
        var bufferColor: Color? = nil
        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            if let color = bufferColor { piece.foregroundColor = color }
            attr.append(piece)
            buffer.removeAll(keepingCapacity: true)
        }
        var count = 0
        for ch in s {
            let color: Color? = ch == "*" ? .red : (ch == "M" ? .green : nil)
            if color != bufferColor { flush(); bufferColor = color }
            buffer.append(ch)
            count += 1
            if count % lineLength == 0 {
                flush()
                bufferColor = nil
                attr.append(AttributedString("\n"))
            }
        }
        flush()
        return Text(attr)
    }
}

struct DatabasesView: View {
    @EnvironmentObject private var model: AppModel
    var showsHeader = true

    private var installedNames: [String] {
        model.installedDatabaseSummary.names.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var notInstalledDatabases: [BlastDatabaseEntry] {
        model.databaseCatalog
            .filter { !$0.isInstalled }
            .sorted(by: databaseEntrySort)
    }

    private var installedSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: model.installedDatabaseSummary.byteSize, countStyle: .file)
    }

    var filteredDatabases: [BlastDatabaseEntry] {
        let query = model.databaseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? model.databaseCatalog : model.databaseCatalog.filter {
            $0.name.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }
        return filtered.sorted(by: databaseEntrySort)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
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
            }

            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            databaseMainColumn
                            databaseSideColumn
                        }
                        .padding(16)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            databaseMainColumn
                                .padding(16)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        ScrollView {
                            databaseSideColumn
                                .padding(16)
                        }
                        .frame(width: min(max(proxy.size.width * 0.38, 420), 620))
                    }
                }
            }
        }
    }

    private var databaseMainColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if model.downloadProgress.hasActivity {
                downloadProgressPanel
            }
            downloadCatalogPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var databaseSideColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                if !showsHeader {
                    Button {
                        Task { await model.refreshDatabaseCatalog() }
                    } label: {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingCatalog)
                }

                Button {
                    for database in filteredDatabases {
                        model.selectedDatabaseNames.insert(database.name)
                    }
                } label: {
                    Label("Select Visible", systemImage: "checklist.checked")
                }

                Button {
                    model.selectRecommendedStarterDatabases()
                } label: {
                    Label("Select Starters", systemImage: "star.fill")
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

                if model.downloadProgress.isActive && !model.isDownloading {
                    Button {
                        model.stopDownloadProgressMonitor()
                    } label: {
                        Label("Stop Monitor", systemImage: "pause.circle")
                    }
                } else {
                    Button {
                        Task { await model.monitorSelectedDatabases() }
                    } label: {
                        Label("Monitor Selected", systemImage: "waveform.path.ecg")
                    }
                    .disabled(model.isDownloading)
                }
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
                        HStack(spacing: 6) {
                            Text(database.name)
                                .font(.headline)
                            if let recommendation = RecommendedBlastDatabases.label(for: database.name) {
                                Text(recommendation)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
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

    private var downloadProgressPanel: some View {
        let progress = model.downloadProgress
        return Panel(title: "Download Progress", systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progress.status)
                        .font(.headline)
                    Spacer()
                    if progress.isActive {
                        Label("Active", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else {
                        Label("Stopped", systemImage: "pause.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let fraction = progress.fractionComplete {
                    ProgressView(value: fraction)
                    Text("\(percentLabel(fraction)) of expected compressed download size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Expected size is unavailable; showing observed archive growth.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    SummaryMetric(label: "Observed", value: byteLabel(progress.observedCompressedBytes))
                    SummaryMetric(label: "This Run", value: byteLabel(progress.addedCompressedBytes))
                    SummaryMetric(label: "Speed", value: speedLabel(progress.bytesPerSecond))
                    SummaryMetric(label: "Time Left", value: etaLabel(progress.estimatedTimeRemaining))
                    SummaryMetric(label: "Finish", value: finishTimeLabel(progress.estimatedFinishDate))
                }

                if !progress.activeFileName.isEmpty {
                    HStack {
                        Label(progress.activeFileName, systemImage: "doc")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(byteLabel(progress.activeFileBytes))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                HStack(spacing: 12) {
                    Label("\(progress.verifiedArchiveCount) verified archives", systemImage: "checkmark.seal")
                    Label("\(progress.archiveCount) archives seen", systemImage: "archivebox")
                    Label(durationLabel(progress.elapsed), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(selectedDatabasesLabel(progress.databaseNames))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var installedSummaryPanel: some View {
        Panel(title: "Installed Databases", systemImage: "checkmark.seal") {
            HStack(spacing: 12) {
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

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func percentLabel(_ fraction: Double) -> String {
        let percent = min(max(fraction * 100, 0), 100)
        return percent >= 10
            ? String(format: "%.0f%%", percent)
            : String(format: "%.1f%%", percent)
    }

    private func speedLabel(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 1 else { return "--" }
        return "\(byteLabel(Int64(bytesPerSecond)))/s"
    }

    private func etaLabel(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "Calculating" }
        return durationLabel(seconds)
    }

    private func finishTimeLabel(_ date: Date?) -> String {
        guard let date else { return "--" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func selectedDatabasesLabel(_ names: [String]) -> String {
        guard !names.isEmpty else { return "No selected databases." }
        let visible = names.prefix(6).joined(separator: ", ")
        let hiddenCount = names.count - min(names.count, 6)
        if hiddenCount > 0 {
            return "Selected: \(visible), +\(hiddenCount) more"
        }
        return "Selected: \(visible)"
    }
}

struct SummaryMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 76, alignment: .leading)
    }
}

struct ToolsView: View {
    @EnvironmentObject private var model: AppModel
    var showsHeader = true

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HeaderBar(
                    title: "External Tools",
                    subtitle: "Point the app at BLAST+, IgBLAST, and Clustal Omega binaries, then verify the local suite."
                ) {
                    Button {
                        Task { await model.refreshTools() }
                    } label: {
                        Label("Recheck", systemImage: "arrow.clockwise")
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Panel(title: "Location", systemImage: "folder.badge.gearshape") {
                        HStack {
                            TextField("Optional tool bin directory", text: $model.preferences.blastBinDirectory)
                            Button {
                                if let path = OpenPanel.chooseDirectory() {
                                    model.preferences.blastBinDirectory = path
                                    Task { await model.refreshTools() }
                                }
                            } label: {
                                Image(systemName: "folder")
                            }
                        }
                        if !showsHeader {
                            Button {
                                Task { await model.refreshTools() }
                            } label: {
                                Label("Recheck", systemImage: "arrow.clockwise")
                            }
                        }
                        Text("Leave this empty to search PATH plus common Homebrew, Conda, and /Applications locations. For Align 3+ sequences, this folder must contain `clustalo` or `clustalo` must be on PATH.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Panel(title: "Suite Status", systemImage: "checklist") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
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
                        Text("Install NCBI BLAST+, IgBLAST, and Clustal Omega from NCBI, Homebrew, Conda, or a managed lab image. LocalBlastStudio does not bundle external binaries or databases; it orchestrates them locally so versioning and data provenance stay visible.")
                            .foregroundStyle(.secondary)
                        Text("Clustal Omega executable name: clustalo. Homebrew: brew install clustal-omega. Conda: conda install -c bioconda clustalo.")
                            .foregroundStyle(.secondary)
                        Link("NCBI BLAST+ command line manual", destination: URL(string: "https://www.ncbi.nlm.nih.gov/books/NBK279690/")!)
                        Link("NCBI IgBLAST", destination: URL(string: "https://www.ncbi.nlm.nih.gov/igblast/")!)
                        Link("Clustal Omega", destination: URL(string: "http://www.clustal.org/omega/")!)
                        Link("NCBI BLAST database downloads", destination: URL(string: "https://www.ncbi.nlm.nih.gov/books/NBK569850/")!)
                    }
                }
                .padding(16)
            }
        }
    }
}

struct ResultsView: View {
    @EnvironmentObject private var model: AppModel

    private var selectedJob: BlastJobRecord? {
        guard let selectedJobID = model.selectedJobID else { return nil }
        return model.jobs.first { $0.id == selectedJobID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "Results",
                subtitle: "Selected BLAST jobs and alignment files open here with full report details."
            ) {
                Button {
                    model.refreshResultFiles()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    if let path = OpenPanel.chooseFile(allowedExtensions: ["txt", "tsv", "out", "aln", "clu"]) {
                        model.importResultFile(path)
                    }
                } label: {
                    Label("Open Result", systemImage: "doc.badge.plus")
                }
            }

            ScrollView {
                selectedResult
                    .padding(16)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.refreshResultFiles()
            model.loadSelectedJobResult()
        }
        .onChange(of: model.selectedJobID) { _, _ in
            model.loadSelectedJobResult()
        }
    }

    @ViewBuilder
    private var selectedResult: some View {
        if let selectedJob {
            VStack(alignment: .leading, spacing: 12) {
                resultJobHeader(selectedJob)
                if let report = model.selectedResultReport {
                    BlastResultReportView(
                        report: report,
                        fallbackProgram: selectedJob.program.displayName,
                        fallbackDatabase: selectedJob.database
                    )
                } else if selectedJob.status == .running {
                    ContentUnavailableView(
                        "Job is running",
                        systemImage: "hourglass",
                        description: Text("The report will load here when BLAST finishes writing the output file.")
                    )
                    .frame(minHeight: 260)
                } else {
                    ContentUnavailableView(
                        "No GUI report loaded",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(model.resultLog.isEmpty ? selectedJob.outputPath : model.resultLog)
                    )
                    .frame(minHeight: 260)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView(
                "Select a job",
                systemImage: "sidebar.left",
                description: Text("Choose a completed BLAST job or imported file from the persistent Results panel.")
            )
            .frame(maxWidth: .infinity, minHeight: 360)
        }
    }

    private func resultJobHeader(_ job: BlastJobRecord) -> some View {
        Panel(title: job.displayTitle, systemImage: "doc.text") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(job.kind.rawValue) · \(job.program.displayName)")
                        .font(.callout.weight(.semibold))
                    if !job.linkedGroup.isEmpty {
                        Label(job.linkedGroup, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Text(job.outputPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    model.reuseResult(job)
                } label: {
                    Label("Re-use result for new search", systemImage: "arrow.uturn.forward.circle")
                }
                .buttonStyle(.bordered)
                .disabled(job.reusableConfiguration == nil)
                .help(job.reusableConfiguration == nil
                    ? "This result does not include saved inputs and settings for reuse."
                    : "Load this result's original inputs and settings into Run BLAST.")
                if model.isJobRunning(job.id) {
                    Button(role: .destructive) {
                        model.killJob(job.id)
                    } label: {
                        Label("Kill", systemImage: "xmark.octagon")
                    }
                    .buttonStyle(.bordered)
                }
                ResultStatusBadge(job: job)
            }

            HStack(spacing: 12) {
                SummaryMetric(label: "Database", value: job.database.isEmpty ? "--" : job.database)
                SummaryMetric(label: "Hits", value: job.noHits ? "0" : job.hitCount.map { $0.formatted() } ?? "--")
                SummaryMetric(label: "Output", value: ByteCountFormatter.string(fromByteCount: job.outputBytes, countStyle: .file))
                SummaryMetric(label: "Runtime", value: durationLabel(job.duration))
                SummaryMetric(label: "CPU", value: "\(job.reservedThreads) thread\(job.reservedThreads == 1 ? "" : "s")")
            }

            if !job.commandPreview.isEmpty {
                DisclosureGroup("Command") {
                    ScrollView(.horizontal) {
                        Text(job.commandPreview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func durationLabel(_ duration: TimeInterval?) -> String {
        guard let duration else { return "--" }
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

struct ResultJobRow: View {
    var job: BlastJobRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: statusImage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Text(job.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !job.linkedGroup.isEmpty {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Spacer()
                Text(job.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(job.program.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(job.database.isEmpty ? job.kind.rawValue : job.database)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption2)

            HStack(spacing: 8) {
                Text(job.status.rawValue)
                    .foregroundStyle(statusColor)
                Text(job.kind == .multipleAlignment ? "Alignment" : (job.noHits ? "No hits" : hitLabel))
                Text(ByteCountFormatter.string(fromByteCount: job.outputBytes, countStyle: .file))
                Text("\(job.reservedThreads) CPU")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var hitLabel: String {
        guard let hitCount = job.hitCount else { return "-- hits" }
        return "\(hitCount.formatted()) hits"
    }

    private var statusImage: String {
        switch job.status {
        case .running:
            "hourglass"
        case .finished:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .killed:
            "xmark.octagon.fill"
        case .imported:
            "tray.and.arrow.down.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .running:
            .blue
        case .finished:
            .green
        case .failed:
            .orange
        case .killed:
            .red
        case .imported:
            .secondary
        }
    }
}

struct ResultStatusBadge: View {
    var job: BlastJobRecord

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var label: String {
        if let exitCode = job.exitCode {
            return "\(job.status.rawValue) · Exit \(exitCode)"
        }
        return job.status.rawValue
    }

    private var systemImage: String {
        switch job.status {
        case .running:
            "hourglass"
        case .finished:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .killed:
            "xmark.octagon.fill"
        case .imported:
            "tray.and.arrow.down.fill"
        }
    }

    private var color: Color {
        switch job.status {
        case .running:
            .blue
        case .finished:
            .green
        case .failed:
            .orange
        case .killed:
            .red
        case .imported:
            .secondary
        }
    }
}

enum BlastResultPane: String, CaseIterable, Identifiable {
    case descriptions = "Descriptions"
    case alignments = "Alignments"
    case table = "Table"
    case raw = "Raw"

    var id: String { rawValue }
}

struct BlastResultReportView: View {
    var report: BlastResultReport
    var fallbackProgram: String
    var fallbackDatabase: String

    @State private var selectedPane: BlastResultPane

    init(report: BlastResultReport, fallbackProgram: String, fallbackDatabase: String) {
        self.report = report
        self.fallbackProgram = fallbackProgram
        self.fallbackDatabase = fallbackDatabase
        _selectedPane = State(initialValue: Self.defaultPane(for: report, fallbackDatabase: fallbackDatabase))
    }

    var body: some View {
        Panel(title: "BLAST Report", systemImage: "target") {
            reportSummary
            if !report.igBlastDomainRegions.isEmpty {
                domainAnnotationStrip
            }

            Picker("Result view", selection: $selectedPane) {
                ForEach(BlastResultPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedPane {
                case .descriptions:
                    descriptionsPane
                case .alignments:
                    alignmentsPane
                case .table:
                    tablePane
                case .raw:
                    rawPane
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: report.rawText) { _, _ in
            selectedPane = Self.defaultPane(for: report, fallbackDatabase: fallbackDatabase)
        }
    }

    private static func defaultPane(for report: BlastResultReport, fallbackDatabase: String) -> BlastResultPane {
        if report.format == .multipleAlignment || isSubjectSequenceAlignment(report, fallbackDatabase: fallbackDatabase) {
            return .raw
        }
        if !report.tabularRows.isEmpty, report.hits.isEmpty {
            return .table
        }
        return .descriptions
    }

    private static func isSubjectSequenceAlignment(_ report: BlastResultReport, fallbackDatabase: String) -> Bool {
        guard !report.alignments.isEmpty else { return false }
        let context = "\(report.database) \(fallbackDatabase)".lowercased()
        return context.contains("user specified sequence set")
            || context.contains("subject sequence")
            || context.contains("pairwise")
            || context.contains("sequence alignment")
    }

    private var reportSummary: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                summaryLabel("Program")
                summaryValue(report.program.isEmpty ? fallbackProgram : report.program)
                summaryLabel("Database")
                summaryValue(report.database.isEmpty ? fallbackDatabase : report.database)
            }
            GridRow {
                summaryLabel("Query ID")
                summaryValue(report.query.isEmpty ? "--" : report.query)
                summaryLabel("Query Length")
                summaryValue(report.queryLength.map { "\($0.formatted())" } ?? "--")
            }
            GridRow {
                summaryLabel("Hits")
                summaryValue(report.noHits ? "0" : "\(report.hitCount.formatted())")
                summaryLabel("Format")
                summaryValue(report.format.rawValue.capitalized)
            }
            if !report.databaseSummary.isEmpty {
                GridRow {
                    summaryLabel("Database Size")
                    Text(report.databaseSummary)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(3)
                        .lineLimit(2)
                }
            }
        }
        .font(.callout)
    }

    private var domainAnnotationStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IgBLAST Domains")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(report.igBlastDomainRegions) { region in
                        Text(domainBracketLabel(region))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(domainColor(for: region).opacity(0.12))
                            .foregroundStyle(domainColor(for: region))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func domainBracketLabel(_ region: IgBlastDomainRegion) -> String {
        let range = region.rangeLabel.isEmpty ? "" : " \(region.rangeLabel)"
        return "<\(region.displayName)\(range)>"
    }

    private func domainColor(for region: IgBlastDomainRegion) -> Color {
        region.name.hasPrefix("CDR") ? .purple : .blue
    }

    private func summaryLabel(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
    }

    private func summaryValue(_ value: String) -> some View {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var descriptionsPane: some View {
        if report.noHits {
            ContentUnavailableView("No hits found", systemImage: "slash.circle")
                .frame(minHeight: 180)
        } else if report.hits.isEmpty {
            ContentUnavailableView("No description table found", systemImage: "tablecells")
                .frame(minHeight: 180)
        } else {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        tableHeader("Description")
                        tableHeader("Accession")
                        tableHeader("Score")
                        tableHeader("E value")
                        tableHeader("Identity")
                        tableHeader("Query cover")
                    }
                    ForEach(Array(report.hits.prefix(100).enumerated()), id: \.offset) { _, hit in
                        GridRow {
                            Text(hit.title)
                                .frame(minWidth: 320, maxWidth: 520, alignment: .leading)
                                .lineLimit(2)
                            monoCell(hit.accession)
                            monoCell(hit.scoreBits)
                            monoCell(hit.eValue)
                            monoCell(hit.identity)
                            monoCell(hit.queryCover)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if report.hits.count > 100 {
                Text("+ \(report.hits.count - 100) more hits in the raw report")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var alignmentsPane: some View {
        if report.alignments.isEmpty {
            ContentUnavailableView("No pairwise alignments found", systemImage: "text.alignleft")
                .frame(minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(report.alignments.prefix(50).enumerated()), id: \.offset) { index, alignment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(alignment.title)
                            .font(.headline)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            metricLabel("Score", alignment.scoreBits)
                            metricLabel("Expect", alignment.eValue)
                            metricLabel("Identities", alignment.identities)
                            metricLabel("Gaps", alignment.gaps)
                            metricLabel("Strand", alignment.strand)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        MonospacedResultText(text: alignment.text)
                        .frame(minHeight: 260, maxHeight: 520)
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if index < min(report.alignments.count, 50) - 1 {
                        Divider()
                    }
                }
                if report.alignments.count > 50 {
                    Text("+ \(report.alignments.count - 50) more alignments in the raw report")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var tablePane: some View {
        if report.tabularRows.isEmpty {
            ContentUnavailableView("No tabular rows found", systemImage: "tablecells")
                .frame(minHeight: 180)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    GridRow {
                        ForEach(Array(report.tabularHeaders.enumerated()), id: \.offset) { _, header in
                            tableHeader(header)
                        }
                    }
                    ForEach(Array(report.tabularRows.prefix(500).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                monoCell(value)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 220, maxHeight: 520)
            if report.tabularRows.count > 500 {
                Text("+ \(report.tabularRows.count - 500) more rows in the raw report")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rawPane: some View {
        MonospacedResultText(text: rawPaneText)
        .frame(minHeight: 560, idealHeight: 760, maxHeight: 900)
    }

    private var rawPaneText: String {
        let displayRawText = rawTextWithoutOuterBlankLines(rawTextWithoutCitationBlocks(report.rawText))
        guard !report.igBlastDomainRegions.isEmpty else {
            return displayRawText
        }

        let annotatedRawText = rawTextWithIgBlastDomainRulers(displayRawText)
        let brackets = report.igBlastDomainRegions
            .map { domainBracketLabel($0) }
            .joined(separator: " ")
        let rows = report.igBlastDomainRegions
            .map { region in
                let range = region.rangeLabel.isEmpty ? "--" : region.rangeLabel
                return "\(region.displayName)\t\(range)"
            }
            .joined(separator: "\n")

        return """
        LocalBlastStudio parsed IgBLAST domain brackets:
        \(brackets)

        Parsed domain ranges:
        \(rows)

        Native IgBLAST output:
        \(annotatedRawText)
        """
    }

    private func rawTextWithoutOuterBlankLines(_ rawText: String) -> String {
        let normalizedText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalizedText.components(separatedBy: "\n")

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }

    private func rawTextWithoutCitationBlocks(_ rawText: String) -> String {
        let normalizedText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedText.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if isCitationBlockStart(trimmed) {
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextTrimmed.isEmpty {
                        index += 1
                        while index < lines.count,
                              lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            index += 1
                        }
                        break
                    }
                    if isRawReportSectionStart(nextTrimmed) {
                        break
                    }
                    index += 1
                }
                appendSingleBlankLine(to: &output)
                continue
            }
            output.append(lines[index])
            index += 1
        }

        return collapsedBlankLines(output).joined(separator: "\n")
    }

    private func isCitationBlockStart(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("Reference:")
            || trimmedLine.hasPrefix("Reference for ")
            || trimmedLine.hasPrefix("Please cite:")
    }

    private func isRawReportSectionStart(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("Database:")
            || trimmedLine.hasPrefix("Query=")
            || trimmedLine.hasPrefix("RID:")
            || trimmedLine.hasPrefix("Sequences producing significant alignments")
            || trimmedLine.hasPrefix(">")
    }

    private func appendSingleBlankLine(to output: inout [String]) {
        guard !output.isEmpty, output.last?.isEmpty == false else { return }
        output.append("")
    }

    private func collapsedBlankLines(_ lines: [String]) -> [String] {
        var collapsed: [String] = []
        var blankCount = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blankCount += 1
                if blankCount <= 1 {
                    collapsed.append("")
                }
            } else {
                blankCount = 0
                collapsed.append(line)
            }
        }
        return collapsed
    }

    private func rawTextWithIgBlastDomainRulers(_ rawText: String) -> String {
        guard let cdr3Region = report.igBlastDomainRegions.first(where: { $0.name.hasPrefix("CDR3") }) else {
            return rawText
        }
        guard !rawText.contains(domainBracketLabel(cdr3Region)) else {
            return rawText
        }
        guard let cdr3Start = Int(cdr3Region.from), let cdr3End = Int(cdr3Region.to) else {
            return rawText
        }

        let queryID = report.query
        var lines = rawText.components(separatedBy: "\n")
        var alignmentsStarted = false
        var insertions: [(index: Int, line: String)] = []

        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() == "alignments" {
                alignmentsStarted = true
                continue
            }
            guard alignmentsStarted else { continue }

            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 4 else { continue }
            guard queryID.isEmpty || tokens[0] == queryID else { continue }
            guard let queryStart = Int(tokens[1]), let queryEnd = Int(tokens[tokens.count - 1]) else { continue }
            guard queryStart <= cdr3End, queryEnd >= cdr3Start else { continue }

            let sequenceToken = tokens[tokens.count - 2]
            let sequenceColumn = leadingColumnCount(before: sequenceToken, in: line)
            let overlapStart = max(cdr3Start, queryStart)
            let overlapEnd = min(cdr3End, queryEnd)
            let markerStartColumn = sequenceColumn + max(overlapStart - queryStart, 0)
            let markerEndColumn = sequenceColumn + max(overlapEnd - queryStart, 0) + 1
            let includesStart = queryStart <= cdr3Start && cdr3Start <= queryEnd
            let includesEnd = queryStart <= cdr3End && cdr3End <= queryEnd
            let label = includesEnd ? "\(cdr3Region.displayName) \(cdr3Region.rangeLabel)" : ""
            let rulerLine = domainRulerLine(
                startColumn: markerStartColumn,
                endColumn: markerEndColumn,
                includesStart: includesStart,
                includesEnd: includesEnd,
                trailingLabel: label
            )
            if !rulerLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if includesStart, let rulerIndex = previousDomainRulerIndex(before: index, in: lines) {
                    lines[rulerIndex] = overlayRulerLine(rulerLine, onto: lines[rulerIndex])
                } else {
                    insertions.append((index: index, line: rulerLine))
                }
            }
        }

        if !insertions.isEmpty {
            for insertion in insertions.sorted(by: { $0.index > $1.index }) {
                lines.insert(insertion.line, at: insertion.index)
            }
            return lines.joined(separator: "\n")
        }

        if let alignmentIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "alignments"
        }) {
            lines.insert(domainBracketLabel(cdr3Region), at: lines.index(after: alignmentIndex))
            return lines.joined(separator: "\n")
        }

        return rawText
    }

    private func previousDomainRulerIndex(before index: Int, in lines: [String]) -> Int? {
        guard index > 0 else { return nil }
        for candidate in stride(from: index - 1, through: 0, by: -1) {
            let trimmed = lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.contains("<"), trimmed.contains(">") {
                return candidate
            }
            return nil
        }
        return nil
    }

    private func overlayRulerLine(_ overlay: String, onto base: String) -> String {
        var baseCharacters = Array(base)
        let overlayCharacters = Array(overlay)
        if baseCharacters.count < overlayCharacters.count {
            baseCharacters.append(contentsOf: Array(repeating: Character(" "), count: overlayCharacters.count - baseCharacters.count))
        }

        for (index, character) in overlayCharacters.enumerated() where character != " " {
            baseCharacters[index] = character
        }

        var line = String(baseCharacters)
        while line.last == " " {
            line.removeLast()
        }
        return line
    }

    private func domainRulerLine(
        startColumn: Int,
        endColumn: Int,
        includesStart: Bool,
        includesEnd: Bool,
        trailingLabel: String
    ) -> String {
        let safeStartColumn = max(startColumn, 0)
        let safeEndColumn = max(endColumn, safeStartColumn + 1)
        let closeColumn = includesEnd ? max(safeEndColumn - 1, safeStartColumn) : safeEndColumn
        let openColumn = includesStart ? min(safeStartColumn + 1, closeColumn) : safeStartColumn
        let lastColumn = max(openColumn, closeColumn)
        var characters = Array(repeating: Character(" "), count: lastColumn + 1)

        if includesStart {
            characters[openColumn] = "<"
        }

        let dashStart = includesStart ? openColumn + 1 : safeStartColumn
        let dashEnd = includesEnd ? closeColumn : safeEndColumn
        if dashStart < dashEnd {
            for column in dashStart..<dashEnd {
                characters[column] = "-"
            }
        }

        if includesEnd {
            characters[closeColumn] = ">"
        }

        var line = String(characters)
        while line.last == " " {
            line.removeLast()
        }
        if includesEnd, !trailingLabel.isEmpty {
            line += " \(trailingLabel)"
        }
        return line
    }

    private func leadingColumnCount(before token: String, in line: String) -> Int {
        guard let range = line.range(of: token) else {
            return 0
        }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    private func tableHeader(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func monoCell(_ value: String) -> some View {
        Text(value.isEmpty ? "--" : value)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func metricLabel(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            Text("\(label): \(value)")
        }
    }
}

private struct MonospacedResultText: View {
    var text: String

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(minWidth: proxy.size.width, alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }
}

struct HeaderBar<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.regularMaterial)
    }
}

struct Panel<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
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
    static func chooseFiles(allowedExtensions: [String]) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let contentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
        }
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    @MainActor
    static func saveFile(defaultName: String) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

enum AppDialog {
    @MainActor
    static func confirmDeleteAllResults(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete all results?"
        alert.informativeText = "This will move \(count.formatted()) result file\(count == 1 ? "" : "s") and any saved reuse metadata to the Trash. This cannot be undone from Local BLAST Studio."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }
}
