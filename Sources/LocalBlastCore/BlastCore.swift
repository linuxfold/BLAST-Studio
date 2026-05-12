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
    case igblastn
    case igblastp

    public var id: String { rawValue }
    public var executableName: String { rawValue }

    public static let blastPlusPrograms: Set<BlastProgram> = [
        .blastn, .blastp, .blastx, .tblastn, .tblastx,
        .psiblast, .rpsblast, .rpstblastn, .deltablast
    ]

    public static let igBlastPrograms: Set<BlastProgram> = [.igblastn, .igblastp]

    public var isIgBlast: Bool {
        Self.igBlastPrograms.contains(self)
    }

    public var supportsPairwiseAlignment: Bool {
        !isIgBlast
    }

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
        case .igblastn: "IgBLASTN"
        case .igblastp: "IgBLASTP"
        }
    }

    public var queryKind: SequenceKind {
        switch self {
        case .blastn, .blastx, .tblastx, .rpstblastn, .igblastn:
            .nucleotide
        case .blastp, .tblastn, .psiblast, .rpsblast, .deltablast, .igblastp:
            .protein
        }
    }

    public var databaseKind: SequenceKind {
        switch self {
        case .blastn, .tblastn, .tblastx, .igblastn:
            .nucleotide
        case .blastp, .blastx, .psiblast, .deltablast, .igblastp:
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
        case .igblastn:
            "Nucleotide immunoglobulin or T cell receptor query against germline V(D)J databases."
        case .igblastp:
            "Protein immunoglobulin or T cell receptor query against a germline V database."
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
        supportedPrograms: Set<BlastProgram> = BlastProgram.blastPlusPrograms,
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
            defaultValue: "4",
            help: "Number of local CPU threads to use. Ignored by remote searches."
        ),
        BlastOption(
            id: "igOutfmt",
            flag: "-outfmt",
            title: "Alignment format",
            group: "IgBLAST",
            control: .picker,
            defaultValue: "3",
            choices: [
                .init("3", "Flat query-anchored with identities"),
                .init("4", "Flat query-anchored without identities"),
                .init("7", "Tabular with comments"),
                .init("19", "AIRR rearrangement tabular")
            ],
            help: "IgBLAST-specific output format. Format 19 writes AIRR rearrangement TSV.",
            supportedPrograms: [.igblastn]
        ),
        BlastOption(
            id: "igOutfmt",
            flag: "-outfmt",
            title: "Alignment format",
            group: "IgBLAST",
            control: .picker,
            defaultValue: "3",
            choices: [
                .init("3", "Flat query-anchored with identities"),
                .init("4", "Flat query-anchored without identities"),
                .init("7", "Tabular with comments")
            ],
            help: "IgBLASTP output format. AIRR rearrangement TSV is supported by IgBLASTN only.",
            supportedPrograms: [.igblastp]
        ),
        BlastOption(
            id: "igDomainSystem",
            flag: "-domain_system",
            title: "V domain system",
            group: "IgBLAST",
            control: .picker,
            defaultValue: "imgt",
            choices: [
                .init("imgt", "IMGT"),
                .init("kabat", "Kabat")
            ],
            help: "Numbering system used to delineate framework and CDR regions.",
            supportedPrograms: BlastProgram.igBlastPrograms
        ),
        BlastOption(
            id: "showTranslation",
            flag: "-show_translation",
            title: "Show translation",
            group: "IgBLAST",
            control: .checkbox,
            defaultValue: "false",
            help: "Show amino-acid translation for nucleotide IgBLAST reports.",
            supportedPrograms: [.igblastn],
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "extendAlign5End",
            flag: "-extend_align5end",
            title: "Extend 5' alignment",
            group: "IgBLAST",
            control: .checkbox,
            defaultValue: "false",
            help: "Show simple gapless extension into the 5' end of the V gene when local alignment misses bases.",
            supportedPrograms: BlastProgram.igBlastPrograms,
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "extendAlign3End",
            flag: "-extend_align3end",
            title: "Extend 3' alignment",
            group: "IgBLAST",
            control: .checkbox,
            defaultValue: "false",
            help: "Show simple gapless extension into the 3' end of the J gene when local alignment misses bases.",
            supportedPrograms: [.igblastn],
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "allowVDJOverlap",
            flag: "-allow_vdj_overlap",
            title: "Allow V(D)J overlap",
            group: "IgBLAST",
            control: .checkbox,
            defaultValue: "false",
            help: "Allow V, D, and J assignments to share overlapping bases at rearrangement junctions.",
            supportedPrograms: [.igblastn],
            argumentKind: .flagWhenTrue
        ),
        BlastOption(
            id: "igEvalue",
            flag: "-evalue",
            title: "Additional DB expect",
            group: "IgBLAST",
            control: .decimal,
            defaultValue: "10",
            help: "Expect threshold for the optional additional non-germline database search.",
            supportedPrograms: BlastProgram.igBlastPrograms
        ),
        BlastOption(
            id: "numAlignments",
            flag: "-num_alignments",
            title: "Additional alignments",
            group: "IgBLAST",
            control: .integer,
            defaultValue: "50",
            help: "Number of alignments to show for the optional additional database search.",
            supportedPrograms: BlastProgram.igBlastPrograms
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
            let order = ["General", "IgBLAST", "Scoring", "Filters", "Algorithm", "Results", "Output", "PSI-BLAST"]
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

public struct ProteinChainSequence: Identifiable, Codable, Hashable, Sendable {
    public var chainID: String
    public var sequence: String
    public var sourceName: String

    public var id: String { chainID }

    public init(chainID: String, sequence: String, sourceName: String = "") {
        self.chainID = chainID
        self.sequence = sequence
        self.sourceName = sourceName
    }

    public func fastaRecord(label: String? = nil) -> String {
        let safeSource = sourceName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        let safeChain = chainID.isEmpty ? "unknown" : chainID
        let identifier = label.map { "\(safeSource)_chain_\(safeChain)_\($0)" } ?? "\(safeSource)_chain_\(safeChain)"
        return ">\(identifier)\n\(Self.wrapped(sequence))\n"
    }

    private static func wrapped(_ sequence: String, width: Int = 80) -> String {
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
}

public enum ProteinStructureParseError: Error, LocalizedError, Equatable {
    case unsupportedFile(String)
    case unreadableFile(String)
    case noProteinChains(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let path):
            "Unsupported structure file type: \(URL(fileURLWithPath: path).lastPathComponent)"
        case .unreadableFile(let path):
            "Could not read structure file: \(URL(fileURLWithPath: path).lastPathComponent)"
        case .noProteinChains(let path):
            "No protein chains could be extracted from \(URL(fileURLWithPath: path).lastPathComponent)."
        }
    }
}

public enum ProteinStructureSequenceExtractor {
    public static func extract(fromFile path: String) throws -> [ProteinChainSequence] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ProteinStructureParseError.unreadableFile(path)
        }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let sourceName = url.deletingPathExtension().lastPathComponent
        let chains: [ProteinChainSequence]
        switch ext {
        case "pdb", "ent":
            chains = extractPDB(text, sourceName: sourceName)
        case "cif", "mmcif":
            chains = extractMMCIF(text, sourceName: sourceName)
        default:
            throw ProteinStructureParseError.unsupportedFile(path)
        }

        let proteinChains = chains
            .map { chain in
                ProteinChainSequence(
                    chainID: chain.chainID,
                    sequence: chain.sequence.filter { $0.isLetter || $0 == "*" },
                    sourceName: sourceName
                )
            }
            .filter { !$0.sequence.isEmpty }
            .sorted { lhs, rhs in
                lhs.chainID.localizedStandardCompare(rhs.chainID) == .orderedAscending
            }
        guard !proteinChains.isEmpty else {
            throw ProteinStructureParseError.noProteinChains(path)
        }
        return proteinChains
    }

    private static func extractPDB(_ text: String, sourceName: String) -> [ProteinChainSequence] {
        let seqres = extractPDBSEQRES(text, sourceName: sourceName)
        if !seqres.isEmpty {
            return seqres
        }
        return extractPDBAtomCA(text, sourceName: sourceName)
    }

    private static func extractPDBSEQRES(_ text: String, sourceName: String) -> [ProteinChainSequence] {
        var residuesByChain: [String: [String]] = [:]
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("SEQRES") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 5 else { continue }
            let chainID = parts[2].isEmpty ? "_" : parts[2]
            let residues = parts.dropFirst(4).compactMap { aminoAcidCode(for: $0) }
            residuesByChain[chainID, default: []].append(contentsOf: residues)
        }
        return residuesByChain.map { chainID, residues in
            ProteinChainSequence(chainID: chainID, sequence: residues.joined(), sourceName: sourceName)
        }
    }

    private static func extractPDBAtomCA(_ text: String, sourceName: String) -> [ProteinChainSequence] {
        var residuesByChain: [String: [String]] = [:]
        var seenResidues = Set<String>()
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("ATOM") || line.hasPrefix("HETATM") {
            let atomName = fixedWidthField(line, start: 12, end: 16).trimmingCharacters(in: .whitespaces)
            guard atomName == "CA" else { continue }
            let residueName = fixedWidthField(line, start: 17, end: 20).trimmingCharacters(in: .whitespaces)
            guard let code = aminoAcidCode(for: residueName) else { continue }
            let chainID = fixedWidthField(line, start: 21, end: 22).trimmingCharacters(in: .whitespaces)
            let normalizedChainID = chainID.isEmpty ? "_" : chainID
            let residueID = fixedWidthField(line, start: 22, end: 27).trimmingCharacters(in: .whitespaces)
            let key = "\(normalizedChainID)|\(residueID)"
            guard !seenResidues.contains(key) else { continue }
            seenResidues.insert(key)
            residuesByChain[normalizedChainID, default: []].append(code)
        }
        return residuesByChain.map { chainID, residues in
            ProteinChainSequence(chainID: chainID, sequence: residues.joined(), sourceName: sourceName)
        }
    }

    private static func extractMMCIF(_ text: String, sourceName: String) -> [ProteinChainSequence] {
        let tokens = mmcifTokens(text)
        var index = 0
        var residuesByChain: [String: [String]] = [:]
        var seenResidues = Set<String>()

        while index < tokens.count {
            guard tokens[index] == "loop_" else {
                index += 1
                continue
            }
            index += 1
            var headers: [String] = []
            while index < tokens.count, tokens[index].hasPrefix("_") {
                headers.append(tokens[index])
                index += 1
            }

            guard headers.contains(where: { $0.hasPrefix("_atom_site.") }) else {
                while index < tokens.count, tokens[index] != "loop_", !tokens[index].hasPrefix("_") {
                    index += 1
                }
                continue
            }

            let groupIndex = indexOf(headers, "_atom_site.group_PDB")
            let atomIndex = indexOf(headers, "_atom_site.label_atom_id") ?? indexOf(headers, "_atom_site.auth_atom_id")
            let compIndex = indexOf(headers, "_atom_site.label_comp_id") ?? indexOf(headers, "_atom_site.auth_comp_id")
            let chainIndex = indexOf(headers, "_atom_site.auth_asym_id") ?? indexOf(headers, "_atom_site.label_asym_id")
            let seqIndex = indexOf(headers, "_atom_site.auth_seq_id") ?? indexOf(headers, "_atom_site.label_seq_id")
            let insIndex = indexOf(headers, "_atom_site.pdbx_PDB_ins_code")

            while index + headers.count <= tokens.count {
                if tokens[index] == "loop_" || tokens[index].hasPrefix("_") || tokens[index].hasPrefix("data_") {
                    break
                }
                let row = Array(tokens[index..<index + headers.count])
                index += headers.count

                if let groupIndex, row.indices.contains(groupIndex), row[groupIndex] != "ATOM" {
                    continue
                }
                guard let atomIndex, row.indices.contains(atomIndex), row[atomIndex] == "CA" else { continue }
                guard let compIndex, row.indices.contains(compIndex),
                      let code = aminoAcidCode(for: row[compIndex]) else { continue }

                let chainID = chainIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "_"
                let seqID = seqIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "\(index)"
                let insID = insIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
                let normalizedChainID = normalizeMissingCIFValue(chainID, fallback: "_")
                let key = "\(normalizedChainID)|\(seqID)|\(insID)"
                guard !seenResidues.contains(key) else { continue }
                seenResidues.insert(key)
                residuesByChain[normalizedChainID, default: []].append(code)
            }
        }

        return residuesByChain.map { chainID, residues in
            ProteinChainSequence(chainID: chainID, sequence: residues.joined(), sourceName: sourceName)
        }
    }

    private static func fixedWidthField(_ line: String, start: Int, end: Int) -> String {
        let characters = Array(line)
        guard start < characters.count else { return "" }
        let upper = min(end, characters.count)
        guard start < upper else { return "" }
        return String(characters[start..<upper])
    }

    private static func indexOf(_ headers: [String], _ name: String) -> Int? {
        headers.firstIndex(of: name)
    }

    private static func normalizeMissingCIFValue(_ value: String, fallback: String) -> String {
        value == "." || value == "?" || value.isEmpty ? fallback : value
    }

    private static func mmcifTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var atLineStart = true
        var iterator = text.makeIterator()

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        while let character = iterator.next() {
            if let quoteCharacter = quote {
                if character == quoteCharacter {
                    quote = nil
                } else {
                    current.append(character)
                }
                atLineStart = character == "\n"
                continue
            }

            if atLineStart, character == ";" {
                flush()
                var block = ""
                var previousWasNewline = false
                while let blockCharacter = iterator.next() {
                    if previousWasNewline, blockCharacter == ";" {
                        break
                    }
                    block.append(blockCharacter)
                    previousWasNewline = blockCharacter == "\n"
                }
                tokens.append(block.trimmingCharacters(in: .whitespacesAndNewlines))
                atLineStart = true
                continue
            }

            if character == "#" {
                flush()
                while let skipped = iterator.next(), skipped != "\n" { }
                atLineStart = true
                continue
            }

            if character == "'" || character == "\"" {
                flush()
                quote = character
                atLineStart = false
                continue
            }

            if character.isWhitespace {
                flush()
                atLineStart = character == "\n"
            } else {
                current.append(character)
                atLineStart = false
            }
        }
        flush()
        return tokens
    }

    private static func aminoAcidCode(for rawName: String) -> String? {
        switch rawName.uppercased() {
        case "ALA": "A"
        case "ARG": "R"
        case "ASN": "N"
        case "ASP": "D"
        case "CYS": "C"
        case "GLN": "Q"
        case "GLU": "E"
        case "GLY": "G"
        case "HIS": "H"
        case "ILE": "I"
        case "LEU": "L"
        case "LYS": "K"
        case "MET", "MSE": "M"
        case "PHE": "F"
        case "PRO": "P"
        case "SER": "S"
        case "THR": "T"
        case "TRP": "W"
        case "TYR": "Y"
        case "VAL": "V"
        case "ASX": "B"
        case "GLX": "Z"
        case "SEC": "U"
        case "PYL": "O"
        case "UNK": "X"
        default: nil
        }
    }
}

public struct IgBlastConfiguration: Codable, Equatable, Sendable {
    public var organism: String
    public var sequenceType: String
    public var igDataDirectory: String
    public var germlineVDatabase: String
    public var germlineDDatabase: String
    public var germlineJDatabase: String
    public var cRegionDatabase: String
    public var auxiliaryDataPath: String
    public var additionalDatabaseName: String
    public var additionalDatabaseDirectory: String

    public init(
        organism: String = "human",
        sequenceType: String = "Ig",
        igDataDirectory: String = "",
        germlineVDatabase: String = "",
        germlineDDatabase: String = "",
        germlineJDatabase: String = "",
        cRegionDatabase: String = "",
        auxiliaryDataPath: String = "",
        additionalDatabaseName: String = "",
        additionalDatabaseDirectory: String = ""
    ) {
        self.organism = organism
        self.sequenceType = sequenceType
        self.igDataDirectory = igDataDirectory
        self.germlineVDatabase = germlineVDatabase
        self.germlineDDatabase = germlineDDatabase
        self.germlineJDatabase = germlineJDatabase
        self.cRegionDatabase = cRegionDatabase
        self.auxiliaryDataPath = auxiliaryDataPath
        self.additionalDatabaseName = additionalDatabaseName
        self.additionalDatabaseDirectory = additionalDatabaseDirectory
    }

    public var searchTargetDescription: String {
        searchTargetDescription(for: .igblastn)
    }

    public func searchTargetDescription(for program: BlastProgram) -> String {
        let germlineParts = [
            labeled("V", germlineVDatabase),
            program == .igblastn ? labeled("D", germlineDDatabase) : nil,
            program == .igblastn ? labeled("J", germlineJDatabase) : nil,
            program == .igblastn ? labeled("C", cRegionDatabase) : nil
        ].compactMap { $0 }
        let germline = germlineParts.isEmpty ? "germline databases" : germlineParts.joined(separator: ", ")
        let additional = additionalDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !additional.isEmpty else { return germline }
        return "\(germline) + \(additional)"
    }

    private func labeled(_ label: String, _ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\(label): \(trimmed)"
    }
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
    public var igBlast: IgBlastConfiguration

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
        rawArguments: String = "",
        igBlast: IgBlastConfiguration = IgBlastConfiguration()
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
        self.igBlast = igBlast
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
    case missingGermlineVDatabase
    case unsupportedPairwiseProgram(String)
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
        case .missingGermlineVDatabase:
            "Choose an IgBLAST germline V database."
        case .unsupportedPairwiseProgram(let program):
            "\(program) does not support Align two sequences mode."
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

        if configuration.program.isIgBlast {
            return try buildIgBlast(configuration: configuration, queryPath: query)
        }

        var arguments = ["-query", query]
        if !configuration.querySubrange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-query_loc", configuration.querySubrange])
        }

        if configuration.alignTwoSequences {
            guard configuration.program.supportsPairwiseAlignment else {
                throw BlastCommandBuildError.unsupportedPairwiseProgram(configuration.program.displayName)
            }
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

    private static func buildIgBlast(
        configuration: BlastSearchConfiguration,
        queryPath: String
    ) throws -> BlastCommand {
        guard !configuration.alignTwoSequences else {
            throw BlastCommandBuildError.unsupportedPairwiseProgram(configuration.program.displayName)
        }

        let igBlast = configuration.igBlast
        let germlineV = igBlast.germlineVDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !germlineV.isEmpty else { throw BlastCommandBuildError.missingGermlineVDatabase }

        var arguments = ["-query", queryPath]
        if !configuration.querySubrange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-query_loc", configuration.querySubrange])
        }

        arguments.append(contentsOf: ["-germline_db_V", germlineV])
        if configuration.program == .igblastn {
            appendValueOption("-germline_db_D", value: igBlast.germlineDDatabase, to: &arguments)
            appendValueOption("-germline_db_J", value: igBlast.germlineJDatabase, to: &arguments)
            appendValueOption("-c_region_db", value: igBlast.cRegionDatabase, to: &arguments)
        }
        appendValueOption("-organism", value: igBlast.organism, to: &arguments)
        appendValueOption("-ig_seqtype", value: igBlast.sequenceType, to: &arguments)
        if configuration.program == .igblastn {
            appendValueOption("-auxiliary_data", value: igBlast.auxiliaryDataPath, to: &arguments)
        }
        appendValueOption("-db", value: igBlast.additionalDatabaseName, to: &arguments)
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
            environment: igBlastEnvironment(for: configuration)
        )
    }

    private static func appendValueOption(_ flag: String, value: String, to arguments: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        arguments.append(contentsOf: [flag, trimmed])
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

    private static func igBlastEnvironment(for configuration: BlastSearchConfiguration) -> [String: String] {
        var environment: [String: String] = [:]
        let igDataDirectory = configuration.igBlast.igDataDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !igDataDirectory.isEmpty {
            environment["IGDATA"] = igDataDirectory
        }

        let additionalDirectory = configuration.igBlast.additionalDatabaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let additionalDatabaseName = configuration.igBlast.additionalDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !additionalDirectory.isEmpty, !additionalDatabaseName.isEmpty, !isPathLikeDatabaseName(additionalDatabaseName) {
            environment["BLASTDB"] = additionalDirectory
        }
        return environment
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

public enum BlastResultFormat: String, Codable, Sendable {
    case pairwise
    case tabular
    case text
}

public struct BlastResultHit: Identifiable, Codable, Equatable, Sendable {
    public var title: String
    public var accession: String
    public var scoreBits: String
    public var eValue: String
    public var identity: String
    public var queryCover: String

    public var id: String {
        [accession, title, scoreBits, eValue].joined(separator: "|")
    }

    public init(
        title: String,
        accession: String = "",
        scoreBits: String = "",
        eValue: String = "",
        identity: String = "",
        queryCover: String = ""
    ) {
        self.title = title
        self.accession = accession
        self.scoreBits = scoreBits
        self.eValue = eValue
        self.identity = identity
        self.queryCover = queryCover
    }
}

public struct BlastAlignmentSection: Identifiable, Codable, Equatable, Sendable {
    public var title: String
    public var accession: String
    public var scoreBits: String
    public var eValue: String
    public var identities: String
    public var gaps: String
    public var strand: String
    public var text: String

    public var id: String {
        [accession, title, scoreBits, eValue].joined(separator: "|")
    }

    public init(
        title: String,
        accession: String = "",
        scoreBits: String = "",
        eValue: String = "",
        identities: String = "",
        gaps: String = "",
        strand: String = "",
        text: String = ""
    ) {
        self.title = title
        self.accession = accession
        self.scoreBits = scoreBits
        self.eValue = eValue
        self.identities = identities
        self.gaps = gaps
        self.strand = strand
        self.text = text
    }
}

public struct IgBlastDomainRegion: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var qualifier: String
    public var from: String
    public var to: String
    public var length: String
    public var matches: String
    public var mismatches: String
    public var gaps: String
    public var percentIdentity: String

    public var id: String {
        [name, qualifier, from, to].joined(separator: "|")
    }

    public var displayName: String {
        qualifier.isEmpty ? name : "\(name) \(qualifier)"
    }

    public var rangeLabel: String {
        from.isEmpty || to.isEmpty ? "" : "\(from)-\(to)"
    }

    public init(
        name: String,
        qualifier: String = "",
        from: String = "",
        to: String = "",
        length: String = "",
        matches: String = "",
        mismatches: String = "",
        gaps: String = "",
        percentIdentity: String = ""
    ) {
        self.name = name
        self.qualifier = qualifier
        self.from = from
        self.to = to
        self.length = length
        self.matches = matches
        self.mismatches = mismatches
        self.gaps = gaps
        self.percentIdentity = percentIdentity
    }
}

public struct BlastResultReport: Codable, Equatable, Sendable {
    public var format: BlastResultFormat
    public var rawText: String
    public var program: String
    public var query: String
    public var queryLength: Int?
    public var database: String
    public var databaseSummary: String
    public var noHits: Bool
    public var hits: [BlastResultHit]
    public var alignments: [BlastAlignmentSection]
    public var tabularHeaders: [String]
    public var tabularRows: [[String]]
    public var igBlastDomainRegions: [IgBlastDomainRegion]

    public var hitCount: Int {
        if !hits.isEmpty {
            return hits.count
        }
        if !tabularRows.isEmpty {
            return tabularRows.count
        }
        return alignments.count
    }

    public var hasVisibleResults: Bool {
        noHits || hitCount > 0 || !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        format: BlastResultFormat,
        rawText: String,
        program: String = "",
        query: String = "",
        queryLength: Int? = nil,
        database: String = "",
        databaseSummary: String = "",
        noHits: Bool = false,
        hits: [BlastResultHit] = [],
        alignments: [BlastAlignmentSection] = [],
        tabularHeaders: [String] = [],
        tabularRows: [[String]] = [],
        igBlastDomainRegions: [IgBlastDomainRegion] = []
    ) {
        self.format = format
        self.rawText = rawText
        self.program = program
        self.query = query
        self.queryLength = queryLength
        self.database = database
        self.databaseSummary = databaseSummary
        self.noHits = noHits
        self.hits = hits
        self.alignments = alignments
        self.tabularHeaders = tabularHeaders
        self.tabularRows = tabularRows
        self.igBlastDomainRegions = igBlastDomainRegions
    }
}

public enum BlastResultParser {
    public static func parse(_ text: String) -> BlastResultReport {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedText.components(separatedBy: .newlines)
        let tabular = parseTabular(lines)
        let alignments = parseAlignmentSections(lines)
        let pairwiseHits = parsePairwiseHits(lines)
        let igBlastDomainRegions = parseIgBlastDomainRegions(lines)
        let hits = pairwiseHits.isEmpty ? tabularHits(rows: tabular.rows, headers: tabular.headers) : pairwiseHits
        let noHits = normalizedText.range(of: "No hits found", options: .caseInsensitive) != nil
        let format: BlastResultFormat
        if !tabular.rows.isEmpty, pairwiseHits.isEmpty, alignments.isEmpty {
            format = .tabular
        } else if !pairwiseHits.isEmpty || !alignments.isEmpty || noHits {
            format = .pairwise
        } else {
            format = .text
        }

        return BlastResultReport(
            format: format,
            rawText: normalizedText,
            program: parseProgram(lines),
            query: parseQuery(lines),
            queryLength: parseQueryLength(lines),
            database: parseDatabase(lines).name,
            databaseSummary: parseDatabase(lines).summary,
            noHits: noHits,
            hits: hits,
            alignments: alignments,
            tabularHeaders: tabular.headers,
            tabularRows: tabular.rows,
            igBlastDomainRegions: igBlastDomainRegions
        )
    }

    private static func parseProgram(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("BLAST") || $0.hasPrefix("IGBLAST") || $0.hasPrefix("IgBLAST") } ?? ""
    }

    private static func parseQuery(_ lines: [String]) -> String {
        guard let queryIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Query=")
        }) else {
            return ""
        }

        let firstLine = lines[queryIndex]
        var parts = [
            String(firstLine[firstLine.range(of: "Query=")!.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }

        for line in lines.dropFirst(queryIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if parts.isEmpty {
                    continue
                }
                break
            }
            if trimmed.hasPrefix("Length=") || trimmed.hasPrefix("Database:") {
                break
            }
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }

    private static func parseQueryLength(_ lines: [String]) -> Int? {
        guard let queryIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Query=")
        }) else {
            return nil
        }
        for line in lines.dropFirst(queryIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Query=")
                || trimmed.hasPrefix(">")
                || trimmed.hasPrefix("Sequences producing significant alignments")
                || trimmed.hasPrefix("Lambda") {
                break
            }
            guard trimmed.hasPrefix("Length=") else { continue }
            return Int(trimmed.dropFirst("Length=".count).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func parseDatabase(_ lines: [String]) -> (name: String, summary: String) {
        guard let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Database:")
        }) else {
            return ("", "")
        }

        let line = lines[index]
        let name = String(line[line.range(of: "Database:")!.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = lines.dropFirst(index + 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix(">") } ?? ""
        return (name, summary)
    }

    private static func parsePairwiseHits(_ lines: [String]) -> [BlastResultHit] {
        guard let startIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("Sequences producing significant alignments")
        }) else {
            return []
        }

        var hits: [BlastResultHit] = []
        var hasStartedRows = false
        for line in lines.dropFirst(startIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if hasStartedRows {
                    break
                }
                continue
            }
            if trimmed.hasPrefix(">") || trimmed.hasPrefix("Database:") {
                break
            }
            let lowercased = trimmed.lowercased()
            if lowercased.contains("score") || lowercased.contains("bits") || lowercased.contains("e value") {
                continue
            }
            guard let parsed = parseHitTableLine(line) else {
                if hasStartedRows {
                    break
                }
                continue
            }
            hasStartedRows = true
            hits.append(parsed)
        }
        return hits
    }

    private static func parseHitTableLine(_ line: String) -> BlastResultHit? {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 3 else { return nil }
        let eValue = String(tokens[tokens.count - 1])
        let score = String(tokens[tokens.count - 2])
        guard looksNumeric(score), looksNumeric(eValue) else { return nil }

        var prefix = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let eValueRange = prefix.range(of: eValue, options: .backwards) {
            prefix.removeSubrange(eValueRange.lowerBound..<prefix.endIndex)
        }
        prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scoreRange = prefix.range(of: score, options: .backwards) {
            prefix.removeSubrange(scoreRange.lowerBound..<prefix.endIndex)
        }
        let title = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return BlastResultHit(
            title: title,
            accession: title.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "",
            scoreBits: score,
            eValue: eValue
        )
    }

    private static func parseAlignmentSections(_ lines: [String]) -> [BlastAlignmentSection] {
        var sections: [BlastAlignmentSection] = []
        var index = lines.startIndex
        while index < lines.endIndex {
            guard lines[index].hasPrefix(">") else {
                index += 1
                continue
            }

            var block = [lines[index]]
            index += 1
            while index < lines.endIndex {
                let line = lines[index]
                if line.hasPrefix(">") || line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Lambda") {
                    break
                }
                block.append(line)
                index += 1
            }
            sections.append(parseAlignmentBlock(block))
        }
        return sections
    }

    private static func parseAlignmentBlock(_ block: [String]) -> BlastAlignmentSection {
        guard let first = block.first else {
            return BlastAlignmentSection(title: "")
        }

        var titleParts = [
            String(first.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
        for line in block.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Length=") || trimmed.hasPrefix("Score =") {
                break
            }
            if !trimmed.isEmpty {
                titleParts.append(trimmed)
            }
        }

        let title = titleParts.joined(separator: " ")
        let scoreLine = block.first { $0.contains("Score =") } ?? ""
        let identityLine = block.first { $0.contains("Identities =") } ?? ""
        let strandLine = block.first { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Strand=") } ?? ""
        return BlastAlignmentSection(
            title: title,
            accession: title.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "",
            scoreBits: extractMetric(from: scoreLine, label: "Score"),
            eValue: extractMetric(from: scoreLine, label: "Expect"),
            identities: extractMetric(from: identityLine, label: "Identities"),
            gaps: extractMetric(from: identityLine, label: "Gaps"),
            strand: strandLine.replacingOccurrences(of: "Strand=", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            text: block.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseTabular(_ lines: [String]) -> (headers: [String], rows: [[String]]) {
        var fields: [String] = []
        var rows: [[String]] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# Fields:") {
                let fieldText = String(trimmed.dropFirst("# Fields:".count))
                fields = fieldText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                continue
            }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let columns = line.components(separatedBy: "\t")
            guard columns.count > 1 else { continue }
            if fields.isEmpty, rows.isEmpty, looksLikeTabularHeader(columns) {
                fields = columns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                continue
            }
            rows.append(columns)
        }

        let headers: [String]
        if let firstRow = rows.first, fields.count == firstRow.count {
            headers = fields
        } else if let firstRow = rows.first {
            headers = (1...firstRow.count).map { "Column \($0)" }
        } else {
            headers = []
        }
        return (headers, rows)
    }

    private static func parseIgBlastDomainRegions(_ lines: [String]) -> [IgBlastDomainRegion] {
        guard let startIndex = lines.firstIndex(where: {
            $0.range(
                of: "Alignment summary between query and top germline V gene hit",
                options: .caseInsensitive
            ) != nil
        }) else {
            return []
        }

        var regions: [IgBlastDomainRegion] = []
        var hasStartedRows = false
        for line in lines.dropFirst(startIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if hasStartedRows { break }
                continue
            }
            if trimmed.lowercased().hasPrefix("alignments") {
                break
            }

            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty else { continue }
            guard tokens[0].range(of: #"^(FR|CDR)\d?-|^CDR3-"#, options: .regularExpression) != nil else {
                continue
            }
            hasStartedRows = true

            let name = tokens[0]
            var offset = 1
            var qualifier = ""
            if tokens.indices.contains(offset), tokens[offset].hasPrefix("(") {
                qualifier = tokens[offset]
                offset += 1
            }
            guard tokens.count >= offset + 7 else { continue }

            regions.append(
                IgBlastDomainRegion(
                    name: name,
                    qualifier: qualifier,
                    from: tokens[offset],
                    to: tokens[offset + 1],
                    length: tokens[offset + 2],
                    matches: tokens[offset + 3],
                    mismatches: tokens[offset + 4],
                    gaps: tokens[offset + 5],
                    percentIdentity: tokens[offset + 6]
                )
            )
        }
        return regions
    }

    private static func tabularHits(rows: [[String]], headers: [String]) -> [BlastResultHit] {
        guard !rows.isEmpty else { return [] }
        let normalizedHeaders = headers.map { normalizeFieldName($0) }

        func value(in row: [String], names: [String], fallbackIndex: Int? = nil) -> String {
            for name in names {
                if let index = normalizedHeaders.firstIndex(of: normalizeFieldName(name)), row.indices.contains(index) {
                    return row[index]
                }
            }
            if let fallbackIndex, row.indices.contains(fallbackIndex) {
                return row[fallbackIndex]
            }
            return ""
        }

        return rows.prefix(200).map { row in
            let hasAirrHeaders = normalizedHeaders.contains("sequenceid") || normalizedHeaders.contains("vcall")
            let subjectFallbackIndex = hasAirrHeaders ? nil : 1
            let subject = value(in: row, names: ["sseqid", "subject id", "subject acc.", "subject acc"], fallbackIndex: subjectFallbackIndex)
            let vCall = value(in: row, names: ["v_call", "v call"])
            let dCall = value(in: row, names: ["d_call", "d call"])
            let jCall = value(in: row, names: ["j_call", "j call"])
            let rearrangementTitle = [vCall, dCall, jCall].filter { !$0.isEmpty }.joined(separator: " / ")
            let title = value(in: row, names: ["stitle", "subject title"], fallbackIndex: subjectFallbackIndex)
            let identity = value(in: row, names: ["pident", "% identity"], fallbackIndex: 2)
            let eValue = value(in: row, names: ["evalue", "e-value"], fallbackIndex: row.count >= 12 ? 10 : nil)
            let score = value(in: row, names: ["bitscore", "bit score"], fallbackIndex: row.count >= 12 ? 11 : nil)
            let query = value(in: row, names: ["sequence_id", "sequence id", "qseqid", "query id"], fallbackIndex: 0)
            return BlastResultHit(
                title: !rearrangementTitle.isEmpty ? rearrangementTitle : (title.isEmpty ? subject : title),
                accession: subject.isEmpty ? query : subject,
                scoreBits: score,
                eValue: eValue,
                identity: identity.isEmpty ? "" : "\(identity)%",
                queryCover: value(in: row, names: ["qcovhsp", "query cover"])
            )
        }
    }

    private static func looksLikeTabularHeader(_ columns: [String]) -> Bool {
        let normalized = columns.map { normalizeFieldName($0) }
        let headerNames: Set<String> = [
            "sequenceid", "revcomp", "productive", "vjincdr3", "vcall", "dcall", "jcall",
            "sequencealignment", "germlinealignment", "junction", "junctionaa",
            "qseqid", "sseqid", "pident", "evalue", "bitscore"
        ]
        return normalized.contains { headerNames.contains($0) }
    }

    private static func extractMetric(from line: String, label: String) -> String {
        guard let labelRange = line.range(of: label),
              let equalsRange = line[labelRange.upperBound...].range(of: "=") else {
            return ""
        }
        var value = String(line[equalsRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let commaIndex = value.firstIndex(of: ",") {
            value = String(value[..<commaIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func normalizeFieldName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func looksNumeric(_ value: String) -> Bool {
        value.range(
            of: #"^([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$|^[eE][+-]?[0-9]+$"#,
            options: .regularExpression
        ) != nil
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
