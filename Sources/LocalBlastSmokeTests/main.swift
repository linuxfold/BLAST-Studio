import Foundation
import LocalBlastCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("Smoke test failed: \(message)\n".utf8))
        Foundation.exit(1)
    }
}

do {
    let defaultConfiguration = BlastSearchConfiguration()
    require(defaultConfiguration.databaseName == RecommendedBlastDatabases.blastn, "BLASTN should default to core_nt")
    require(BlastProgram.blastn.recommendedDatabaseName == RecommendedBlastDatabases.blastn, "BLASTN recommended database is wrong")
    require(BlastProgram.blastp.recommendedDatabaseName == RecommendedBlastDatabases.blastp, "BLASTP recommended database is wrong")
    require(RecommendedBlastDatabases.rank(for: RecommendedBlastDatabases.blastn) < RecommendedBlastDatabases.rank(for: "nt"), "core_nt should sort before nt")

    var configuration = BlastSearchConfiguration(
        program: .blastn,
        databaseName: "nt",
        databaseDirectory: "/blast/db",
        outputPath: "/tmp/result.txt"
    )
    configuration.optionValues["dust"] = "false"
    configuration.optionValues["maxTargetSeqs"] = "25"
    configuration.rawArguments = "-outfmt '6 qseqid sseqid evalue' -dbsize 1000"

    let command = try BlastCommandBuilder.build(configuration: configuration, queryPath: "/tmp/query.fa")
    require(command.executableName == "blastn", "wrong executable")
    require(command.arguments.contains("-db") && command.arguments.contains("nt"), "missing database name")
    require(!command.arguments.contains("/blast/db/nt"), "database path should be supplied through BLASTDB")
    require(command.environment["BLASTDB"] == "/blast/db", "missing BLASTDB environment")
    require(command.preview.hasPrefix("BLASTDB=/blast/db blastn "), "preview should show BLASTDB assignment")
    require(command.arguments.contains("-dust") && command.arguments.contains("no"), "missing dust override")
    require(command.arguments.contains("-max_target_seqs") && command.arguments.contains("25"), "missing max target override")
    require(command.arguments.contains("6 qseqid sseqid evalue"), "quoted outfmt was not preserved")

    configuration.databaseDirectory = "/Users/home/Library/Application Support/LocalBlastStudio/Databases"
    let spacedPathCommand = try BlastCommandBuilder.build(configuration: configuration, queryPath: "/tmp/query.fa")
    require(spacedPathCommand.arguments.contains("nt"), "database name changed for spaced BLASTDB path")
    require(spacedPathCommand.environment["BLASTDB"] == configuration.databaseDirectory, "spaced BLASTDB path not preserved")
    require(spacedPathCommand.preview.hasPrefix("BLASTDB='/Users/home/Library/Application Support/LocalBlastStudio/Databases' blastn "), "spaced BLASTDB path was not shell-escaped")

    var pairwise = BlastSearchConfiguration(
        program: .blastp,
        databaseName: "nr",
        outputPath: "/tmp/pairwise.txt"
    )
    pairwise.alignTwoSequences = true
    pairwise.querySubrange = "1-20"
    pairwise.subjectSubrange = "3-30"
    let pairwiseCommand = try BlastCommandBuilder.build(
        configuration: pairwise,
        queryPath: "/tmp/query.faa",
        subjectPath: "/tmp/subject.faa"
    )
    require(pairwiseCommand.executableName == "blastp", "pairwise command uses wrong executable")
    require(pairwiseCommand.arguments.contains("-subject"), "pairwise command did not use -subject")
    require(!pairwiseCommand.arguments.contains("-db"), "pairwise command should not include -db")
    require(pairwiseCommand.arguments.contains("-query_loc"), "pairwise command missing query range")
    require(pairwiseCommand.arguments.contains("-subject_loc"), "pairwise command missing subject range")

    let split = try BlastCommandBuilder.splitShellArguments(#"-outfmt "6 qacc sacc bitscore" -html"#)
    require(split == ["-outfmt", "6 qacc sacc bitscore", "-html"], "quoted raw args split incorrectly")

    let showAll = """
    nr
    nt
    refseq_rna
    # ignored
    swissprot
    """
    let entries = BlastDatabaseParser.parseShowAll(showAll)
    require(!entries.contains { $0.name == "Connected" }, "status chatter was parsed as a database")
    require(entries.contains { $0.name == "core_nt" && $0.kind == .nucleotide }, "recommended core_nt not present")
    require(entries.contains { $0.name == "nr_cluster_seq" && $0.kind == .protein }, "recommended nr_cluster_seq not present")
    require(entries.contains { $0.name == "nr" && $0.kind == .protein }, "nr not parsed")
    require(entries.contains { $0.name == "nt" && $0.kind == .nucleotide }, "nt not parsed")
    require(entries.contains { $0.name == "swissprot" && $0.kind == .protein }, "swissprot not parsed")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    FileManager.default.createFile(atPath: directory.appendingPathComponent("nr.00.pin").path, contents: Data())
    FileManager.default.createFile(atPath: directory.appendingPathComponent("nt.nsq").path, contents: Data())
    FileManager.default.createFile(atPath: directory.appendingPathComponent("taxdb.bti").path, contents: Data())
    FileManager.default.createFile(atPath: directory.appendingPathComponent("refseq_rna.01.nhd").path, contents: Data())
    let summary = InstalledBlastDatabaseScanner.summary(directory: directory)
    let installed = summary.names
    require(installed.contains("nr"), "volume suffix not stripped")
    require(installed.contains("nt"), "plain database name not detected")
    require(installed.contains("taxdb"), "taxonomy database not detected")
    require(installed.contains("refseq_rna"), "BLAST v5 nucleotide extension not detected")
    require(summary.fileCount == 4, "summary file count is wrong")

    print("LocalBlastSmokeTests passed")
} catch {
    FileHandle.standardError.write(Data("Smoke test failed: \(error.localizedDescription)\n".utf8))
    Foundation.exit(1)
}
