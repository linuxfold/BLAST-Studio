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

    var multipleAlignment = BlastSearchConfiguration(
        program: .blastp,
        outputPath: "/tmp/alignment.aln"
    )
    multipleAlignment.alignMultipleSequences = true
    multipleAlignment.rawArguments = "--iterations=2"
    let multipleAlignmentCommand = try MultipleSequenceAlignmentCommandBuilder.build(
        configuration: multipleAlignment,
        inputPath: "/tmp/proteins.faa"
    )
    require(multipleAlignmentCommand.executableName == "clustalo", "multiple alignment should use clustalo")
    require(multipleAlignmentCommand.arguments.contains("-i") && multipleAlignmentCommand.arguments.contains("/tmp/proteins.faa"), "multiple alignment missing input")
    require(multipleAlignmentCommand.arguments.contains("--seqtype=Protein"), "protein multiple alignment missing seqtype")
    require(!multipleAlignmentCommand.arguments.contains { $0.hasPrefix("--threads") }, "multiple alignment should not add thread overrides")
    require(multipleAlignmentCommand.arguments.contains("--iterations=2"), "multiple alignment raw args not appended")

    var igBlast = BlastSearchConfiguration(
        program: .igblastn,
        databaseDirectory: "/blast/db",
        outputPath: "/tmp/igblast.tsv",
        optionValues: BlastParameterCatalog.defaultValues(for: .igblastn)
    )
    igBlast.igBlast = IgBlastConfiguration(
        organism: "human",
        sequenceType: "Ig",
        igDataDirectory: "/igblast",
        germlineVDatabase: "database/human_gl_V",
        germlineDDatabase: "database/human_gl_D",
        germlineJDatabase: "database/human_gl_J",
        auxiliaryDataPath: "optional_file/human_gl.aux",
        additionalDatabaseName: "nt",
        additionalDatabaseDirectory: "/blast/db"
    )
    igBlast.optionValues["igOutfmt"] = "19"
    igBlast.optionValues["showTranslation"] = "true"
    let igBlastCommand = try BlastCommandBuilder.build(configuration: igBlast, queryPath: "/tmp/igquery.fa")
    require(igBlastCommand.executableName == "igblastn", "IgBLAST command uses wrong executable")
    require(igBlastCommand.arguments.contains("-germline_db_V") && igBlastCommand.arguments.contains("database/human_gl_V"), "missing IgBLAST V germline database")
    require(igBlastCommand.arguments.contains("-germline_db_D") && igBlastCommand.arguments.contains("database/human_gl_D"), "missing IgBLAST D germline database")
    require(igBlastCommand.arguments.contains("-germline_db_J") && igBlastCommand.arguments.contains("database/human_gl_J"), "missing IgBLAST J germline database")
    require(igBlastCommand.arguments.contains("-auxiliary_data") && igBlastCommand.arguments.contains("optional_file/human_gl.aux"), "missing IgBLAST auxiliary data")
    require(igBlastCommand.arguments.contains("-db") && igBlastCommand.arguments.contains("nt"), "missing IgBLAST additional database")
    require(igBlastCommand.arguments.contains("-outfmt") && igBlastCommand.arguments.contains("19"), "missing IgBLAST AIRR output format")
    require(igBlastCommand.arguments.contains("-show_translation"), "missing IgBLAST show translation flag")
    require(igBlastCommand.environment["IGDATA"] == "/igblast", "missing IgBLAST IGDATA environment")
    require(igBlastCommand.environment["BLASTDB"] == "/blast/db", "missing IgBLAST additional BLASTDB environment")
    require(igBlastCommand.preview.hasPrefix("BLASTDB=/blast/db IGDATA=/igblast igblastn "), "IgBLAST preview should show sorted environment assignments")

    var igBlastProtein = igBlast
    igBlastProtein.program = .igblastp
    igBlastProtein.optionValues = BlastParameterCatalog.defaultValues(for: .igblastp)
    igBlastProtein.outputPath = "/tmp/igblastp.txt"
    let igBlastProteinCommand = try BlastCommandBuilder.build(configuration: igBlastProtein, queryPath: "/tmp/igquery.faa")
    require(igBlastProteinCommand.executableName == "igblastp", "IgBLASTP command uses wrong executable")
    require(!igBlastProteinCommand.arguments.contains("-germline_db_D"), "IgBLASTP command should not include D germline database")
    require(!igBlastProteinCommand.arguments.contains("-germline_db_J"), "IgBLASTP command should not include J germline database")
    require(!igBlastProteinCommand.arguments.contains("-auxiliary_data"), "IgBLASTP command should not include nucleotide auxiliary data")
    let igBlastProteinOutfmt = BlastParameterCatalog.options(for: .igblastp).first { $0.id == "igOutfmt" }
    require(igBlastProteinOutfmt?.choices.contains { $0.value == "19" } == false, "IgBLASTP should not offer AIRR outfmt 19")

    var missingIgBlastV = igBlast
    missingIgBlastV.igBlast.germlineVDatabase = ""
    do {
        _ = try BlastCommandBuilder.build(configuration: missingIgBlastV, queryPath: "/tmp/igquery.fa")
        require(false, "IgBLAST command should require a V germline database")
    } catch BlastCommandBuildError.missingGermlineVDatabase {
        // Expected.
    } catch {
        throw error
    }

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

    let clustalReportText = """
    CLUSTAL O(1.2.4) multiple sequence alignment

    seq1      ACGT
    seq2      A-GT
    seq3      ACG-
    """
    let clustalReport = BlastResultParser.parse(clustalReportText)
    require(clustalReport.format == .multipleAlignment, "Clustal report format not detected")
    require(clustalReport.program.hasPrefix("CLUSTAL"), "Clustal program line not parsed")

    let igBlastDomainReportText = """
    IGBLASTP 1.22.0

    Domain classification requested: imgt

    Alignment summary between query and top germline V gene hit (from, to, length, matches, mismatches, gaps, percent identity)
    FR1-IMGT\t1\t26\t26\t24\t2\t0\t92.3
    CDR1-IMGT\t27\t32\t7\t1\t5\t1\t14.3
    FR2-IMGT\t33\t49\t17\t15\t2\t0\t88.2
    CDR2-IMGT\t50\t52\t3\t1\t2\t0\t33.3
    FR3-IMGT\t53\t88\t36\t34\t2\t0\t94.4
    CDR3-IMGT\t(germline)\t89\t95\t7\t2\t5\t0\t28.6
    Total\tN/A\tN/A\t96\t77\t18\t1\t80.2

    Alignments
    """
    let igBlastDomainReport = BlastResultParser.parse(igBlastDomainReportText)
    require(igBlastDomainReport.igBlastDomainRegions.count == 6, "IgBLAST domain summary not parsed")
    require(igBlastDomainReport.igBlastDomainRegions.last?.displayName == "CDR3-IMGT (germline)", "IgBLAST CDR3 qualifier not parsed")
    require(igBlastDomainReport.igBlastDomainRegions.last?.rangeLabel == "89-95", "IgBLAST CDR3 range not parsed")

    let airrReportText = """
    sequence_id\tproductive\tv_call\td_call\tj_call\tjunction\tjunction_aa
    Query_1\tT\tIGHV1-69*01\tIGHD3-10*01\tIGHJ4*02\tTGTGCGAGAG\tCAR
    """
    let airrReport = BlastResultParser.parse(airrReportText)
    require(airrReport.format == .tabular, "AIRR report format not detected")
    require(airrReport.tabularHeaders.first == "sequence_id", "AIRR header not parsed")
    require(airrReport.tabularRows.count == 1, "AIRR row not parsed")
    require(airrReport.hits[0].title.contains("IGHV1-69*01"), "AIRR V call not exposed as hit title")
    require(airrReport.hits[0].accession == "Query_1", "AIRR sequence id not exposed")

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

    let pdbURL = directory.appendingPathComponent("antibody.pdb")
    try """
    HEADER    TEST STRUCTURE
    SEQRES   1 A    4  ASP ILE VAL VAL
    SEQRES   1 B    4  GLN VAL GLN LEU
    """.write(to: pdbURL, atomically: true, encoding: .utf8)
    let pdbChains = try ProteinStructureSequenceExtractor.extract(fromFile: pdbURL.path)
    require(pdbChains.count == 2, "PDB SEQRES chains not parsed")
    require(pdbChains.first { $0.chainID == "A" }?.sequence == "DIVV", "PDB chain A sequence wrong")
    require(pdbChains.first { $0.chainID == "B" }?.sequence == "QVQL", "PDB chain B sequence wrong")

    let cifURL = directory.appendingPathComponent("model.cif")
    try """
    data_model
    loop_
    _atom_site.group_PDB
    _atom_site.id
    _atom_site.label_atom_id
    _atom_site.label_comp_id
    _atom_site.auth_asym_id
    _atom_site.auth_seq_id
    ATOM 1 CA MET A 1
    ATOM 2 CA GLY A 2
    ATOM 3 CA SER B 1
    """.write(to: cifURL, atomically: true, encoding: .utf8)
    let cifChains = try ProteinStructureSequenceExtractor.extract(fromFile: cifURL.path)
    require(cifChains.first { $0.chainID == "A" }?.sequence == "MG", "mmCIF chain A sequence wrong")
    require(cifChains.first { $0.chainID == "B" }?.sequence == "S", "mmCIF chain B sequence wrong")
    try FileManager.default.removeItem(at: pdbURL)
    try FileManager.default.removeItem(at: cifURL)

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
