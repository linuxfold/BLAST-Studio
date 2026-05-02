import Foundation

public enum SequenceKind: String, CaseIterable, Codable, Sendable {
    case nucleotide = "Nucleotide"
    case protein = "Protein"
    case conservedDomain = "Conserved Domain"
    case mixed = "Mixed"
}

public enum BlastProgram: String, CaseIterable, Codable, Identifiable, Sendable {
    case blastn
    case blastp
    case blastx
    case tblastn
    case tblastx
    case psiblast
    case rpsblast
    case rpstblastn
    case deltablast

    public var id: String { rawValue }
    public var executableName: String { rawValue }

    public var displayName: String {
        switch self {
        case .blastn: "BLASTN"
        case .blastp: "BLASTP"
        case .blastx: "BLASTX"
        case .tblastn: "TBLASTN"
        case .tblastx: "TBLASTX"
        case .psiblast: "PSI-BLAST"
        case .rpsblast: "RPS-BLAST"
        case .rpstblastn: "RPSTBLASTN"
        case .deltablast: "DELTA-BLAST"
        }
    }

    public var queryKind: SequenceKind {
        switch self {
        case .blastn, .blastx, .tblastx, .rpstblastn:
            .nucleotide
        case .blastp, .tblastn, .psiblast, .rpsblast, .deltablast:
            .protein
        }
    }

    public var databaseKind: SequenceKind {
        switch self {
        case .blastn, .tblastn, .tblastx:
            .nucleotide
        case .blastp, .blastx, .psiblast, .deltablast:
            .protein
        case .rpsblast, .rpstblastn:
            .conservedDomain
        }
    }

    public var summary: String {
        switch self {
        case .blastn:
            "Nucleotide query against a nucleotide database."
        case .blastp:
            "Protein query against a protein database."
        case .blastx:
            "Translated nucleotide query against a protein database."
        case .tblastn:
            "Protein query against a translated nucleotide database."
        case .tblastx:
            "Translated nucleotide query against a translated nucleotide database."
        case .psiblast:
            "Iterative protein search that builds a position-specific scoring model."
        case .rpsblast:
            "Protein query against conserved domain profile databases."
        case .rpstblastn:
            "Translated nucleotide query against conserved domain profile databases."
        case .deltablast:
            "Protein search seeded from conserved domain matches."
        }
    }

    public var recommendedDatabaseName: String? {
        switch self {
        case .blastn:
            RecommendedBlastDatabases.blastn
        case .blastp:
            RecommendedBlastDatabases.blastp
        default:
            nil
        }
    }
}

public enum RecommendedBlastDatabases {
    public static let blastn = "core_nt"
    public static let blastp = "nr_cluster_seq"
    public static let starterNames = [blastn, blastp]

    public static let entries: [BlastDatabaseEntry] = [
        .init(
            name: blastn,
            title: "Core nucleotide BLAST database - recommended starter for BLASTN",
            kind: .nucleotide
        ),
        .init(
            name: blastp,
            title: "Clustered NR protein sequences - recommended starter for BLASTP",
            kind: .protein,
            source: "NCBI ClusteredNR"
        )
    ]

    public static func rank(for name: String) -> Int {
        starterNames.firstIndex(of: name) ?? Int.max
    }

    public static func label(for name: String) -> String? {
        switch name {
        case blastn:
            "Recommended for BLASTN"
        case blastp:
            "Recommended for BLASTP"
        default:
            nil
        }
    }
}

public enum BlastOptionControl: String, Codable, Sendable {
    case text
    case integer
    case decimal
    case checkbox
    case picker
    case multiline
}

public enum BlastArgumentKind: String, Codable, Sendable {
    case value
    case flagWhenTrue
    case yesNoValue
}

public struct BlastOptionChoice: Codable, Hashable, Sendable {
    public var value: String
    public var label: String

    public init(_ value: String, _ label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

public struct BlastOption: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var flag: String
    public var title: String
    public var group: String
    public var control: BlastOptionControl
    public var defaultValue: String
    public var choices: [BlastOptionChoice]
    public var help: String
    public var supportedPrograms: Set<BlastProgram>
    public var argumentKind: BlastArgumentKind
    public var includeWhenDefault: Bool

    public init(
        id: String,
        flag: String,
        title: String,
        group: String,
        control: BlastOptionControl,
        defaultValue: String = "",
        choices: [BlastOptionChoice] = [],
        help: String,
        supportedPrograms: Set<BlastProgram> = Set(BlastProgram.allCases),
        argumentKind: BlastArgumentKind = .value,
        includeWhenDefault: Bool = false
    ) {
        self.id = id
        self.flag = flag
        self.title = title
        self.group = group
        self.control = control
        self.defaultValue = defaultValue
        self.choices = choices
        self.help = help
        self.supportedPrograms = supportedPrograms
        self.argumentKind = argumentKind
        self.includeWhenDefault = includeWhenDefault
    }

    public func supports(_ program: BlastProgram) -> Bool {
        supportedPrograms.contains(program)
    }

    public func arguments(for rawValue: String) -> [String] {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard includeWhenDefault || value != defaultValue else { return [] }

        switch argumentKind {
        case .value:
            guard !value.isEmpty else { return [] }
            return [flag, value]
        case .flagWhenTrue:
            return value.booleanValue == true ? [flag] : []
        case .yesNoValue:
            guard let bool = value.booleanValue else { return [] }
            return [flag, bool ? "yes" : "no"]
        }
    }
}

public enum BlastParameterCatalog {
    public static let nucleotidePrograms: Set<BlastProgram> = [.blastn]
    public static let proteinPrograms: Set<BlastProgram> = [.blastp, .blastx, .tblastn, .psiblast, .rpsblast, .deltablast]
    public static let translatedPrograms: Set<BlastProgram> = [.blastx, .tblastn, .tblastx, .rpstblastn]
    public static let proteinScoringPrograms: Set<BlastProgram> = [.blastp, .blastx, .tblastn, .psiblast, .rpsblast, .deltablast]

    public static let options: [BlastOption] = [
        BlastOption(
            id: "task",
            flag: "-task",
            title: "Algorithm task",
            group: "General",
            control: .picker,
            choices: [
                .init("megablast", "Highly similar sequences"),
                .init("dc-megablast", "Discontiguous megablast"),
                .init("blastn", "Somewhat similar sequences"),
                .init("blastn-short", "Short nucleotide sequences"),
                .init("blastp", "Standard protein BLAST"),
                .init("blastp-fast", "Fast protein BLAST"),
                .init("blastp-short", "Short protein sequences")
            ],
            help: "Selects the BLAST task/preset for programs that expose one.",
            supportedPrograms: [.blastn, .blastp]
        ),
        BlastOption(
            id: "entrezQuery",
            flag: "-entrez_query",
            title: "Entrez query",
            group: "General",
            control: .text,
            help: "Limits matching database sequences by an Entrez expression when the database supports it."
        ),
        BlastOption(
            id: "maxTargetSeqs",
            flag: "-max_target_seqs",
            title: "Max target sequences",
            group: "General",
            control: .integer,
            defaultValue: "100",
            help: "Maximum number of aligned sequences to keep."
        ),
        BlastOption(
            id: "evalue",
            flag: "-evalue",
            title: "Expect threshold",
            group: "General",
            control: .decimal,
            defaultValue: "10",
            help: "Expected number of chance matches in a database of this size."
        ),
        BlastOption(
            id: "wordSize",
            flag: "-word_size",
            title: "Word size",
            group: "Algorithm",
            control: .integer,
            help: "Initial word size for seed matches."
        ),
        BlastOption(
            id: "numThreads",
            flag: "-num_threads",
            title: "CPU threads",
            group: "General",
            control: .integer,
            defaultValue: "1",
            help: "Number of local CPU threads to use. Ignored by remote searches."
        ),
        BlastOption(
            id: "strand",
            flag: "-strand",
            title: "Query strand",
            group: "General",
            control: .picker,
            defaultValue: "both",
            choices: [.init("both"), .init("plus"), .init("minus")],
            help: "Nucleotide strand to search.",
            supportedPrograms: [.blastn, .blastx, .tblastx]
        ),
        BlastOption(
            id: "queryGeneticCode",
            flag: "-query_gencode",
            title: "Query genetic code",
            group: "General",
            control: .picker,
            defaultValue: "1",
            choices: geneticCodeChoices,
            help: "Genetic code used to translate the query.",
            supportedPrograms: [.blastx, .tblastx]
        ),
        BlastOption(
            id: "dbGeneticCode",
            flag: "-db_gencode",
            title: "Database genetic code",
            group: "General",
            control: .picker,
            defaultValue: "1",
            choices: geneticCodeChoices,
            help: "Genetic code used to translate database sequences.",
            supportedPrograms: [.tblastn, .tblastx]
        ),
        BlastOption(
            id: "matrix",
            flag: "-matrix",
            title: "Matrix",
            group: "Scoring",
            control: .picker,
            defaultValue: "BLOSUM62",
            choices: [
                .init("BLOSUM45"), .init("BLOSUM50"), .init("BLOSUM62"), .init("BLOSUM80"), .init("BLOSUM90"),
                .init("PAM30"), .init("PAM70"), .init("PAM250")
            ],
            help: "Protein substitution matrix.",
            supportedPrograms: proteinScoringPrograms
        ),
        BlastOption(
            id: "reward",
            flag: "-reward",
            title: "Match reward",
            group: "Scoring",
            control: .integer,
            help: "Reward for a nucleotide match.",
            supportedPrograms: nucleotidePrograms
        ),
        BlastOption(
            id: "penalty",
            flag: "-penalty",
            title: "Mismatch penalty",
            group: "Scoring",
            control: .integer,
            help: "Penalty for a nucleotide mismatch.",
            supportedPrograms: nucleotidePrograms
        ),
        BlastOption(
            id: "gapOpen",
            flag: "-gapopen",
            title: "Gap open cost",
            group: "Scoring",
            control: .integer,
            help: "Penalty to open a gap."
        ),
        BlastOption(
            id: "gapExtend",
            flag: "-gapextend",
            title: "Gap extension cost",
            group: "Scoring",
            control: .integer,
            help: "Penalty to extend a gap."
        ),
        BlastOption(
            id: "threshold",
            flag: "-threshold",
            title: "Neighboring score threshold",
            group: "Algorithm",
            control: .integer,
            help: "Minimum neighboring word score for protein searches.",
            supportedPrograms: proteinScoringPrograms
        ),
        BlastOption(
            id: "compBasedStats",
            flag: "-comp_based_stats",
            title: "Compositional adjustments",
            group: "Algorithm",
            control: .picker,
            defaultValue: "2",
            choices: [
                .init("0", "Off"),
                .init("1", "Composition-based statistics"),
                .init("2", "Conditional compositional score matrix adjustment"),
                .init("3", "Universal compositional score matrix adjustment")
            ],
            help: "Protein composition-based statistics mode.",
            supportedPrograms: proteinScoringPrograms
        ),
        BlastOption(
            id: "dust",
            flag: "-dust",
            title: "DUST low-complexity filter",
            group: "Filters",
            control: .checkbox,
            defaultValue: "true",
            help: "Masks low-complexity nucleotide sequence.",
            supportedPrograms: [.blastn],
            argumentKind: .yesNoValue
        ),
        BlastOption(
            id: "seg",
            flag: "-seg",
            title: "SEG low-complexity filter",
            group: "Filters",
            control: .checkbox,
            defaultValue: "true",
            help: "Masks low-complexity protein sequence.",
            supportedPrograms: proteinScoringPrograms,
            argumentKind: .yesNoValue
        ),
        BlastOption(
            id: "softMasking",
            flag: "-soft_masking",
            title: "Soft masking",
            group: "Filters",
            control: .checkbox,
            defaultValue: "true",
            help: "Use masked regions for finding seeds but not for extension.",
            argumentKind: .yesNoValue
        ),
        BlastOption(
            id: "lowercaseMasking",
            flag: "-lcase_masking",
            title: "Lowercase masking",
            group: "Filters",
            control: .checkbox,
            defaultValue: "false",
            help: "Treat lowercase letters in FASTA input as masked sequence.",
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "lookupMaskingOnly",
            flag: "-lookup_table_masking_only",
            title: "Mask lookup table only",
            group: "Filters",
            control: .checkbox,
            defaultValue: "false",
            help: "Apply masking only while building the lookup table.",
            supportedPrograms: [.blastn, .blastp, .blastx, .tblastn, .tblastx],
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "ungapped",
            flag: "-ungapped",
            title: "Ungapped alignment only",
            group: "Algorithm",
            control: .checkbox,
            defaultValue: "false",
            help: "Run ungapped alignment only.",
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "windowSize",
            flag: "-window_size",
            title: "Multiple-hit window size",
            group: "Algorithm",
            control: .integer,
            help: "Window size for multiple-hit algorithm."
        ),
        BlastOption(
            id: "xdropUngap",
            flag: "-xdrop_ungap",
            title: "X dropoff ungapped",
            group: "Algorithm",
            control: .decimal,
            help: "X dropoff value for ungapped extension."
        ),
        BlastOption(
            id: "xdropGap",
            flag: "-xdrop_gap",
            title: "X dropoff gapped",
            group: "Algorithm",
            control: .decimal,
            help: "X dropoff value for preliminary gapped extension."
        ),
        BlastOption(
            id: "xdropGapFinal",
            flag: "-xdrop_gap_final",
            title: "X dropoff final",
            group: "Algorithm",
            control: .decimal,
            help: "X dropoff value for final gapped alignment."
        ),
        BlastOption(
            id: "bestHitOverhang",
            flag: "-best_hit_overhang",
            title: "Best hit overhang",
            group: "Results",
            control: .decimal,
            help: "Best-hit filtering overhang value."
        ),
        BlastOption(
            id: "bestHitScoreEdge",
            flag: "-best_hit_score_edge",
            title: "Best hit score edge",
            group: "Results",
            control: .decimal,
            help: "Best-hit filtering score edge value."
        ),
        BlastOption(
            id: "cullingLimit",
            flag: "-culling_limit",
            title: "Culling limit",
            group: "Results",
            control: .integer,
            help: "Remove hits enveloped by this many higher-scoring hits."
        ),
        BlastOption(
            id: "maxHSPs",
            flag: "-max_hsps",
            title: "Max HSPs per subject",
            group: "Results",
            control: .integer,
            help: "Maximum high-scoring segment pairs to keep per subject."
        ),
        BlastOption(
            id: "percentIdentity",
            flag: "-perc_identity",
            title: "Percent identity cutoff",
            group: "Results",
            control: .decimal,
            help: "Minimum percent identity.",
            supportedPrograms: [.blastn]
        ),
        BlastOption(
            id: "queryCoverage",
            flag: "-qcov_hsp_perc",
            title: "Query cover cutoff",
            group: "Results",
            control: .decimal,
            help: "Minimum query coverage per HSP."
        ),
        BlastOption(
            id: "outfmt",
            flag: "-outfmt",
            title: "Output format",
            group: "Output",
            control: .picker,
            defaultValue: "0",
            choices: [
                .init("0", "Pairwise"),
                .init("1", "Query-anchored with identities"),
                .init("2", "Query-anchored without identities"),
                .init("3", "Flat query-anchored with identities"),
                .init("4", "Flat query-anchored without identities"),
                .init("5", "XML"),
                .init("6", "Tabular"),
                .init("7", "Tabular with comments"),
                .init("8", "Seqalign text ASN.1"),
                .init("9", "Seqalign binary ASN.1"),
                .init("10", "CSV"),
                .init("11", "BLAST archive ASN.1"),
                .init("12", "Seqalign JSON"),
                .init("13", "Multiple-file JSON"),
                .init("14", "Multiple-file XML2"),
                .init("15", "Single-file JSON"),
                .init("16", "Single-file XML2"),
                .init("17", "SAM"),
                .init("18", "Organism report")
            ],
            help: "Result serialization format."
        ),
        BlastOption(
            id: "html",
            flag: "-html",
            title: "HTML report",
            group: "Output",
            control: .checkbox,
            defaultValue: "false",
            help: "Render pairwise reports as HTML.",
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "inclusionEvalue",
            flag: "-inclusion_ethresh",
            title: "PSI inclusion threshold",
            group: "PSI-BLAST",
            control: .decimal,
            defaultValue: "0.005",
            help: "E-value threshold for including matches in PSI-BLAST model updates.",
            supportedPrograms: [.psiblast]
        ),
        BlastOption(
            id: "numIterations",
            flag: "-num_iterations",
            title: "PSI iterations",
            group: "PSI-BLAST",
            control: .integer,
            defaultValue: "1",
            help: "Number of PSI-BLAST iterations.",
            supportedPrograms: [.psiblast]
        )
    ]

    public static var groups: [String] {
        Array(Set(options.map(\.group))).sorted { lhs, rhs in
            let order = ["General", "Scoring", "Filters", "Algorithm", "Results", "Output", "PSI-BLAST"]
            return (order.firstIndex(of: lhs) ?? Int.max, lhs) < (order.firstIndex(of: rhs) ?? Int.max, rhs)
        }
    }

    public static func options(for program: BlastProgram) -> [BlastOption] {
        options.filter { $0.supports(program) }
    }

    public static func option(id: String) -> BlastOption? {
        options.first { $0.id == id }
    }

    public static func defaultValues(for program: BlastProgram) -> [String: String] {
        var values: [String: String] = [:]
        for option in options(for: program) {
            if option.id == "task" {
                values[option.id] = program == .blastn ? "megablast" : "blastp"
            } else {
                values[option.id] = option.defaultValue
            }
        }
        return values
    }

    public static let geneticCodeChoices: [BlastOptionChoice] = [
        .init("1", "Standard"),
        .init("2", "Vertebrate mitochondrial"),
        .init("3", "Yeast mitochondrial"),
        .init("4", "Mold/protozoan/coelenterate mitochondrial"),
        .init("5", "Invertebrate mitochondrial"),
        .init("6", "Ciliate/dasycladacean/hexamita nuclear"),
        .init("9", "Echinoderm/flatworm mitochondrial"),
        .init("10", "Euplotid nuclear"),
        .init("11", "Bacterial, archaeal and plant plastid"),
        .init("12", "Alternative yeast nuclear"),
        .init("13", "Ascidian mitochondrial"),
        .init("14", "Alternative flatworm mitochondrial"),
        .init("16", "Chlorophycean mitochondrial"),
        .init("21", "Trematode mitochondrial"),
        .init("22", "Scenedesmus obliquus mitochondrial"),
        .init("23", "Thraustochytrium mitochondrial"),
        .init("24", "Pterobranchia mitochondrial"),
        .init("25", "Candidate division SR1 and gracilibacteria"),
        .init("26", "Pachysolen tannophilus nuclear"),
        .init("27", "Karyorelict nuclear"),
        .init("28", "Condylostoma nuclear"),
        .init("29", "Mesodinium nuclear"),
        .init("30", "Peritrich nuclear"),
        .init("31", "Blastocrithidia nuclear"),
        .init("33", "Cephalodiscidae mitochondrial")
    ]
}

public struct BlastDatabaseEntry: Identifiable, Codable, Hashable, Sendable {
    public var name: String
    public var title: String
    public var kind: SequenceKind
    public var isInstalled: Bool
    public var source: String

    public var id: String { name }

    public init(name: String, title: String, kind: SequenceKind, isInstalled: Bool = false, source: String = "NCBI") {
        self.name = name
        self.title = title
        self.kind = kind
        self.isInstalled = isInstalled
        self.source = source
    }
}

public enum FallbackDatabaseCatalog {
    public static let entries: [BlastDatabaseEntry] = [
        .init(name: "core_nt", title: "Core nucleotide BLAST database - recommended starter for BLASTN", kind: .nucleotide),
        .init(name: "nr_cluster_seq", title: "Clustered NR protein sequences - recommended starter for BLASTP", kind: .protein, source: "NCBI ClusteredNR"),
        .init(name: "nt", title: "Nucleotide collection (nr/nt)", kind: .nucleotide),
        .init(name: "nr", title: "Non-redundant protein sequences", kind: .protein),
        .init(name: "refseq_rna", title: "RefSeq RNA", kind: .nucleotide),
        .init(name: "refseq_protein", title: "RefSeq protein", kind: .protein),
        .init(name: "refseq_genomic", title: "RefSeq genomic", kind: .nucleotide),
        .init(name: "swissprot", title: "UniProtKB/Swiss-Prot", kind: .protein),
        .init(name: "pdbaa", title: "PDB protein sequences", kind: .protein),
        .init(name: "pdbnt", title: "PDB nucleotide sequences", kind: .nucleotide),
        .init(name: "patnt", title: "Patent nucleotide sequences", kind: .nucleotide),
        .init(name: "patprot", title: "Patent protein sequences", kind: .protein),
        .init(name: "tsa_nt", title: "Transcriptome shotgun assembly nucleotide", kind: .nucleotide),
        .init(name: "tsa_nr", title: "Transcriptome shotgun assembly protein", kind: .protein),
        .init(name: "env_nt", title: "Environmental nucleotide sequences", kind: .nucleotide),
        .init(name: "env_nr", title: "Environmental protein sequences", kind: .protein),
        .init(name: "est", title: "Expressed sequence tags", kind: .nucleotide),
        .init(name: "est_human", title: "Human EST", kind: .nucleotide),
        .init(name: "est_mouse", title: "Mouse EST", kind: .nucleotide),
        .init(name: "est_others", title: "Other EST", kind: .nucleotide),
        .init(name: "gss", title: "Genome survey sequences", kind: .nucleotide),
        .init(name: "htgs", title: "High-throughput genomic sequences", kind: .nucleotide),
        .init(name: "wgs", title: "Whole genome shotgun sequences", kind: .nucleotide),
        .init(name: "landmark", title: "Model organism genomic sequences", kind: .nucleotide),
        .init(name: "16S_ribosomal_RNA", title: "16S ribosomal RNA", kind: .nucleotide),
        .init(name: "cdd_delta", title: "CDD DELTA-BLAST database", kind: .protein),
        .init(name: "cdd", title: "Conserved Domain Database", kind: .conservedDomain),
        .init(name: "taxdb", title: "BLAST taxonomy lookup database", kind: .mixed)
    ]
}

public struct BlastSearchConfiguration: Codable, Equatable, Sendable {
    public var program: BlastProgram
    public var queryText: String
    public var queryFilePath: String
    public var querySubrange: String
    public var alignTwoSequences: Bool
    public var subjectText: String
    public var subjectFilePath: String
    public var subjectSubrange: String
    public var databaseName: String
    public var databaseDirectory: String
    public var outputPath: String
    public var optionValues: [String: String]
    public var rawArguments: String

    public init(
        program: BlastProgram = .blastn,
        queryText: String = "",
        queryFilePath: String = "",
        querySubrange: String = "",
        alignTwoSequences: Bool = false,
        subjectText: String = "",
        subjectFilePath: String = "",
        subjectSubrange: String = "",
        databaseName: String = RecommendedBlastDatabases.blastn,
        databaseDirectory: String = "",
        outputPath: String = "",
        optionValues: [String: String] = BlastParameterCatalog.defaultValues(for: .blastn),
        rawArguments: String = ""
    ) {
        self.program = program
        self.queryText = queryText
        self.queryFilePath = queryFilePath
        self.querySubrange = querySubrange
        self.alignTwoSequences = alignTwoSequences
        self.subjectText = subjectText
        self.subjectFilePath = subjectFilePath
        self.subjectSubrange = subjectSubrange
        self.databaseName = databaseName
        self.databaseDirectory = databaseDirectory
        self.outputPath = outputPath
        self.optionValues = optionValues
        self.rawArguments = rawArguments
    }

    public mutating func resetOptionsForProgram() {
        optionValues = BlastParameterCatalog.defaultValues(for: program)
    }
}

public struct BlastCommand: Equatable, Sendable {
    public var executableName: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(executableName: String, arguments: [String], environment: [String: String] = [:]) {
        self.executableName = executableName
        self.arguments = arguments
        self.environment = environment
    }

    public var preview: String {
        let assignments = environment.keys.sorted().map { key in
            "\(key)=\(environment[key, default: ""].shellEscaped)"
        }
        let command = [executableName.shellEscaped] + arguments.map(\.shellEscaped)
        return (assignments + command).joined(separator: " ")
    }
}

public enum BlastCommandBuildError: Error, LocalizedError, Equatable {
    case missingQuery
    case missingSubject
    case missingDatabase
    case missingOutputPath
    case malformedRawArguments(String)

    public var errorDescription: String? {
        switch self {
        case .missingQuery:
            "Choose a query file or paste a FASTA query."
        case .missingSubject:
            "Choose a subject file or paste a subject FASTA sequence."
        case .missingDatabase:
            "Choose a BLAST database."
        case .missingOutputPath:
            "Choose an output file."
        case .malformedRawArguments(let value):
            "Could not parse advanced arguments near: \(value)"
        }
    }
}

public enum BlastCommandBuilder {
    public static func build(
        configuration: BlastSearchConfiguration,
        queryPath: String,
        subjectPath: String = ""
    ) throws -> BlastCommand {
        let query = queryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw BlastCommandBuildError.missingQuery }
        guard !configuration.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BlastCommandBuildError.missingOutputPath
        }

        var arguments = ["-query", query]
        if !configuration.querySubrange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-query_loc", configuration.querySubrange])
        }

        if configuration.alignTwoSequences {
            let subject = subjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else { throw BlastCommandBuildError.missingSubject }
            arguments.append(contentsOf: ["-subject", subject])
            if !configuration.subjectSubrange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                arguments.append(contentsOf: ["-subject_loc", configuration.subjectSubrange])
            }
        } else {
            guard !configuration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BlastCommandBuildError.missingDatabase
            }
            arguments.append(contentsOf: ["-db", databaseArgument(for: configuration)])
        }
        arguments.append(contentsOf: ["-out", configuration.outputPath])

        let options = BlastParameterCatalog.options(for: configuration.program)
        for option in options {
            guard let value = configuration.optionValues[option.id] else { continue }
            arguments.append(contentsOf: option.arguments(for: value))
        }

        do {
            arguments.append(contentsOf: try splitShellArguments(configuration.rawArguments))
        } catch {
            throw BlastCommandBuildError.malformedRawArguments(configuration.rawArguments)
        }

        return BlastCommand(
            executableName: configuration.program.executableName,
            arguments: arguments,
            environment: environment(for: configuration)
        )
    }

    private static func databaseArgument(for configuration: BlastSearchConfiguration) -> String {
        let databaseName = configuration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return databaseName
    }

    private static func environment(for configuration: BlastSearchConfiguration) -> [String: String] {
        guard !configuration.alignTwoSequences else { return [:] }
        let directory = configuration.databaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let databaseName = configuration.databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty, !isPathLikeDatabaseName(databaseName) else { return [:] }
        return ["BLASTDB": directory]
    }

    private static func isPathLikeDatabaseName(_ databaseName: String) -> Bool {
        databaseName.hasPrefix("/")
            || databaseName.hasPrefix("~")
            || databaseName.hasPrefix(".")
            || databaseName.contains("/")
    }

    public static func splitShellArguments(_ input: String) throws -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in input {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                escaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if escaped {
            current.append("\\")
        }
        if quote != nil {
            throw BlastCommandBuildError.malformedRawArguments(input)
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}

public extension String {
    var booleanValue: Bool? {
        switch trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "on":
            true
        case "false", "no", "0", "off":
            false
        default:
            nil
        }
    }

    var shellEscaped: String {
        guard !isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=.,/:@%")
        if unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return self
        }
        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum BlastDatabaseParser {
    public static func parseShowAll(_ output: String) -> [BlastDatabaseEntry] {
        var entries: [BlastDatabaseEntry] = []
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        for line in lines {
            let name = line.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? line
            guard isLikelyDatabaseName(name), !entries.contains(where: { $0.name == name }) else { continue }
            entries.append(
                BlastDatabaseEntry(
                    name: name,
                    title: fallbackTitle(for: name),
                    kind: inferKind(from: name),
                    source: "update_blastdb.pl --showall"
                )
            )
        }
        return includingRecommended(entries)
    }

    public static func includingRecommended(_ entries: [BlastDatabaseEntry]) -> [BlastDatabaseEntry] {
        var merged = entries
        for recommendedEntry in RecommendedBlastDatabases.entries where !merged.contains(where: { $0.name == recommendedEntry.name }) {
            merged.append(recommendedEntry)
        }
        return merged.sorted(by: recommendedSort)
    }

    public static func markInstalled(_ entries: [BlastDatabaseEntry], installedNames: Set<String>) -> [BlastDatabaseEntry] {
        entries.map { entry in
            var copy = entry
            copy.isInstalled = installedNames.contains(entry.name)
            return copy
        }
    }

    public static func recommendedSort(_ lhs: BlastDatabaseEntry, _ rhs: BlastDatabaseEntry) -> Bool {
        let lhsRank = RecommendedBlastDatabases.rank(for: lhs.name)
        let rhsRank = RecommendedBlastDatabases.rank(for: rhs.name)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    public static func inferKind(from name: String) -> SequenceKind {
        let lower = name.lowercased()
        if lower.contains("cdd") || lower.contains("rps") {
            return .conservedDomain
        }
        if lower.contains("prot") || lower.contains("nr") || lower.contains("aa") || lower.contains("swiss") {
            return .protein
        }
        if lower.contains("taxdb") {
            return .mixed
        }
        return .nucleotide
    }

    private static func isLikelyDatabaseName(_ value: String) -> Bool {
        guard value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return false }
        let rejected = [
            "usage", "options", "database", "blastdb", "available", "error",
            "connected", "connecting", "retrieving", "downloading", "warning", "http", "https", "ftp"
        ]
        return !rejected.contains(value.lowercased())
    }

    private static func fallbackTitle(for name: String) -> String {
        FallbackDatabaseCatalog.entries.first { $0.name == name }?.title ?? name.replacingOccurrences(of: "_", with: " ")
    }
}

public struct InstalledDatabaseSummary: Equatable, Sendable {
    public var names: Set<String>
    public var fileCount: Int
    public var byteSize: Int64

    public init(names: Set<String> = [], fileCount: Int = 0, byteSize: Int64 = 0) {
        self.names = names
        self.fileCount = fileCount
        self.byteSize = byteSize
    }
}

public enum InstalledBlastDatabaseScanner {
    private static let knownExtensions: Set<String> = [
        "nhr", "nin", "nsq", "nog", "nsd", "nsi", "ndb", "not", "ntf", "nto",
        "nhd", "nhi", "nnd", "nni", "nos", "nxm", "nal",
        "phr", "pin", "psq", "pog", "psd", "psi", "pdb", "pot", "ptf", "pto",
        "phd", "phi", "ppd", "ppi", "pxm", "pjs", "pos",
        "pal", "nal", "bti", "btd"
    ]

    public static func scan(directory: URL) -> Set<String> {
        summary(directory: directory).names
    }

    public static func summary(directory: URL) -> InstalledDatabaseSummary {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return InstalledDatabaseSummary()
        }

        var names = Set<String>()
        var fileCount = 0
        var byteSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            fileCount += 1
            byteSize += Int64(values?.fileSize ?? 0)

            let ext = fileURL.pathExtension.lowercased()
            guard knownExtensions.contains(ext) else { continue }
            let base = stripBlastSuffixes(from: fileURL.deletingPathExtension().lastPathComponent)
            if !base.isEmpty {
                names.insert(base)
            }
        }
        return InstalledDatabaseSummary(names: names, fileCount: fileCount, byteSize: byteSize)
    }

    private static func stripBlastSuffixes(from name: String) -> String {
        var result = name
        if let range = result.range(of: #"\.\d+$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }
}
