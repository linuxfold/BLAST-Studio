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
    case rnaSeq = "RNA-Seq"
    case databases = "Databases"
    case tools = "Tools"
    case jobs = "Jobs"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .run: "play.circle"
        case .rnaSeq: "waveform.path.ecg"
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
        return Date().timeIntervalSince(startedAt)
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
        "windowmasker", "makeprofiledb", "makembindex", "convert2blastmask", "gzip"
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
    @Published var preferences: BlastPreferences {
        didSet {
            preferences.save()
            configuration.databaseDirectory = preferences.databaseDirectory
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
    @Published var isRefreshingCatalog = false
    @Published var isDownloading = false
    @Published var downloadProgress = DownloadProgressSnapshot()
    @Published var rnaSeqProgress = RNASeqProgressSnapshot()
    @Published var toolStatuses: [ToolStatus] = []
    @Published var jobs: [BlastJobRecord] = []
    @Published var customDatabaseInput = ""
    @Published var customDatabaseName = ""
    @Published var customDatabaseType = "nucl"
    @Published var customDatabaseParseSeqIDs = true

    private var downloadProgressTask: Task<Void, Never>?
    private var downloadProgressBaseline = DownloadDirectoryScan()
    private var downloadProgressDirectory = ""
    private var downloadProgressNames: [String] = []
    private var rnaSeqProgressTask: Task<Void, Never>?

    init() {
        let preferences = BlastPreferences.load()
        self.preferences = preferences
        self.configuration = BlastSearchConfiguration(
            program: .blastn,
            databaseName: RecommendedBlastDatabases.blastn,
            databaseDirectory: preferences.databaseDirectory
        )
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

    func ensureDefaultRNASeqOutputPath() {
        if rnaSeqConfiguration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rnaSeqConfiguration.outputPath = URL(fileURLWithPath: preferences.outputDirectory)
                .appendingPathComponent("rnaseq-annotations.tsv")
                .path
        }
    }

    func setProgram(_ program: BlastProgram) {
        configuration.program = program
        configuration.resetOptionsForProgram()
        if let recommendedDatabaseName = program.recommendedDatabaseName {
            configuration.databaseName = recommendedDatabaseName
        } else if let matchingDatabase = databaseCatalog.first(where: { $0.kind == program.databaseKind && $0.isInstalled }) ??
            databaseCatalog.first(where: { $0.kind == program.databaseKind }) {
            configuration.databaseName = matchingDatabase.name
        }
        ensureDefaultOutputPath()
        updateCommandPreview()
    }

    func setRNASeqProgram(_ program: BlastProgram) {
        rnaSeqConfiguration.program = program
        rnaSeqConfiguration.databaseName = preferredRNASeqDatabaseName(for: program)
        updateRNASeqCommandPreview()
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
        let outputPath = rnaSeqConfiguration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputDirectory = outputURL.deletingLastPathComponent()
        let inputFiles = rnaSeqConfiguration.inputFiles
        let keepConvertedFasta = rnaSeqConfiguration.keepConvertedFasta
        let needsGzip = inputFiles.contains(where: RNASeqFastqConverter.isGzipFASTQ)
        let gzipURL = needsGzip ? ProcessClient.resolveExecutable(named: "gzip", preferences: preferences) : nil

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
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            } catch {
                throw RNASeqAnalysisError.cannotCreateOutputDirectory(outputDirectory.path)
            }

            isRunningRNASeq = true
            rnaSeqLog = "Preparing RNA-Seq annotation."
            let startedAt = Date()
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
            rnaSeqLog = "Running \(command.preview)"
            startRNASeqOutputMonitor(outputPath: outputPath, convertedReads: convertedReads)
            let result = try await Task.detached {
                try ProcessClient.runSync(
                    executableURL: executable,
                    arguments: command.arguments,
                    environment: command.environment
                )
            }.value
            stopRNASeqProgressMonitor()

            if !keepConvertedFasta {
                try? FileManager.default.removeItem(at: convertedFastaURL)
            }

            let outputBytes = fileSize(path: outputPath)
            let logText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            rnaSeqLog = logText.isEmpty
                ? "RNA-Seq annotation finished with exit code \(result.exitCode)."
                : logText
            rnaSeqProgress = RNASeqProgressSnapshot(
                hasActivity: true,
                isActive: false,
                stage: result.exitCode == 0 ? .finished : .failed,
                status: result.exitCode == 0 ? "Annotation finished" : "BLAST exited with code \(result.exitCode)",
                inputFileCount: inputFiles.count,
                totalInputBytes: totalBytes,
                processedInputBytes: totalBytes,
                convertedReads: convertedReads,
                outputBytes: outputBytes,
                startedAt: startedAt,
                lastUpdated: Date()
            )
            jobs.insert(
                BlastJobRecord(
                    program: rnaSeqConfiguration.program,
                    database: rnaSeqConfiguration.databaseName,
                    outputPath: outputPath,
                    commandPreview: command.preview,
                    exitCode: result.exitCode,
                    date: Date()
                ),
                at: 0
            )
        } catch {
            stopRNASeqProgressMonitor()
            rnaSeqLog = error.localizedDescription
            var snapshot = rnaSeqProgress
            snapshot.hasActivity = true
            snapshot.isActive = false
            snapshot.stage = .failed
            snapshot.status = error.localizedDescription
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

    private func fileSize(path: String) -> Int64 {
        Self.fileSize(path: path)
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
            let result = try await Task.detached {
                try ProcessClient.runSync(
                    executableURL: executable,
                    arguments: command.arguments,
                    environment: command.environment
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
            case .rnaSeq:
                RNASeqView()
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

private func databaseEntrySort(_ lhs: BlastDatabaseEntry, _ rhs: BlastDatabaseEntry) -> Bool {
    let lhsRank = RecommendedBlastDatabases.rank(for: lhs.name)
    let rhsRank = RecommendedBlastDatabases.rank(for: rhs.name)
    if lhsRank != rhsRank { return lhsRank < rhsRank }
    if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled && !rhs.isInstalled }
    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
}

struct RunBlastView: View {
    @EnvironmentObject private var model: AppModel

    var availableDatabases: [BlastDatabaseEntry] {
        model.databaseCatalog
            .filter { $0.kind == model.configuration.program.databaseKind || model.configuration.program.databaseKind == .mixed || $0.kind == .mixed }
            .sorted(by: databaseEntrySort)
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
        .frame(minHeight: 160)
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
            HeaderBar(
                title: "RNA-Seq Annotation",
                subtitle: "Stream large trimmed and merged FASTQ files into local BLAST annotation jobs."
            ) { }

            GeometryReader { proxy in
                if proxy.size.width < 1050 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            mainColumn
                            sideColumn
                        }
                        .padding(20)
                    }
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            mainColumn
                                .padding(20)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)

                        Divider()

                        ScrollView {
                            sideColumn
                                .padding(20)
                        }
                        .frame(width: min(max(proxy.size.width * 0.38, 420), 620))
                    }
                }
            }
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                if model.rnaSeqConfiguration.program == .blastn {
                    GridRow {
                        Text("BLASTN task")
                            .frame(width: 150, alignment: .leading)
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
                        .frame(width: 150, alignment: .leading)
                    TextField("1e-5", text: $model.rnaSeqConfiguration.evalue)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Max hits/read")
                        .frame(width: 150, alignment: .leading)
                    TextField("10", text: $model.rnaSeqConfiguration.maxTargetSequences)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("CPU threads")
                        .frame(width: 150, alignment: .leading)
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

            HStack(spacing: 16) {
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
            if model.downloadProgress.hasActivity {
                downloadProgressPanel
            }
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

                HStack(spacing: 16) {
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
