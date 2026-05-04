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

    let pairwiseReportText = """
    BLASTN 2.16.0+

    Query= Query_1
    Length=426

    Database: core_nt
               1,234 sequences; 5,678 total letters

    Sequences producing significant alignments:                          Score     E
    Subject_alpha hypothetical protein                                   751       0.0
    Subject_beta predicted transcript                                    312       2e-80

    >Subject_alpha hypothetical protein
    Length=500
     Score = 751 bits (406),  Expect = 0.0
     Identities = 426/426 (100%), Gaps = 0/426 (0%)
     Strand=Plus/Plus

    Query  1    ACGT  4
                ||||
    Sbjct  2    ACGT  5

    Lambda      K        H
    """
    let pairwiseReport = BlastResultParser.parse(pairwiseReportText)
    require(pairwiseReport.format == .pairwise, "pairwise report format not detected")
    require(pairwiseReport.program == "BLASTN 2.16.0+", "program line not parsed")
    require(pairwiseReport.query == "Query_1", "query name not parsed")
    require(pairwiseReport.queryLength == 426, "query length not parsed")
    require(pairwiseReport.database == "core_nt", "database name not parsed")
    require(pairwiseReport.hits.count == 2, "description hit table not parsed")
    require(pairwiseReport.alignments.count == 1, "alignment block not parsed")
    require(pairwiseReport.alignments[0].identities == "426/426 (100%)", "identity metric not parsed")

    let databaseFirstReportText = """
    BLASTN 2.16.0+

    Database: core_nt
               1,234 sequences; 5,678 total letters

    Query= Query_1
    Length=426

    ***** No hits found *****

    Lambda      K        H
    """
    let databaseFirstReport = BlastResultParser.parse(databaseFirstReportText)
    require(databaseFirstReport.query == "Query_1", "database-first query name not parsed")
    require(databaseFirstReport.queryLength == 426, "database-first query length not parsed")
    require(databaseFirstReport.database == "core_nt", "database-first database name not parsed")
    require(databaseFirstReport.noHits, "database-first no-hit report not detected")

    let tabularReportText = """
    # BLASTN 2.16.0+
    # Fields: qseqid, sseqid, pident, length, mismatch, gapopen, qstart, qend, sstart, send, evalue, bitscore
    Query_1\tSubject_alpha\t99.0\t426\t1\t0\t1\t426\t2\t427\t1e-120\t425
    """
    let tabularReport = BlastResultParser.parse(tabularReportText)
    require(tabularReport.format == .tabular, "tabular report format not detected")
    require(tabularReport.tabularRows.count == 1, "tabular row not parsed")
    require(tabularReport.hits[0].accession == "Subject_alpha", "tabular subject not parsed")
    require(tabularReport.hits[0].identity == "99.0%", "tabular identity not parsed")

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
