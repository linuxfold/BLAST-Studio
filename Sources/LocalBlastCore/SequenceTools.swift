import Foundation

// MARK: - Genetic codes

/// An NCBI translation table. `aminoAcids` is indexed by the codon index
/// `base1*16 + base2*4 + base3` with T/U=0, C=1, A=2, G=3 (NCBI ncbieaa order).
public struct GeneticCodeTable: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    let aminoAcids: [Character]
    let startCodons: Set<String>

    public var displayName: String { "\(id). \(name)" }

    /// NCBI standard code amino-acid string (table 1).
    static let standardString = Array("FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG")

    static func index(for codon: String) -> Int? {
        let bases = Array(codon.uppercased())
        guard bases.count == 3 else { return nil }
        func value(_ c: Character) -> Int? {
            switch c {
            case "T", "U": return 0
            case "C": return 1
            case "A": return 2
            case "G": return 3
            default: return nil
            }
        }
        guard let b1 = value(bases[0]), let b2 = value(bases[1]), let b3 = value(bases[2]) else { return nil }
        return b1 * 16 + b2 * 4 + b3
    }

    /// Build a table from the standard string plus per-codon overrides.
    static func make(id: Int, name: String, overrides: [String: Character], starts: Set<String> = ["ATG"]) -> GeneticCodeTable {
        var aas = standardString
        for (codon, aa) in overrides {
            if let idx = index(for: codon) { aas[idx] = aa }
        }
        return GeneticCodeTable(id: id, name: name, aminoAcids: aas, startCodons: starts)
    }

    /// Translate a single codon; returns `X` for codons that contain non-ACGTU characters.
    public func translate(codon: String) -> Character {
        guard let idx = GeneticCodeTable.index(for: codon) else { return "X" }
        return aminoAcids[idx]
    }

    public static let standard = make(id: 1, name: "Standard", overrides: [:])

    public static let all: [GeneticCodeTable] = [
        standard,
        make(id: 2, name: "Vertebrate Mitochondrial", overrides: ["AGA": "*", "AGG": "*", "ATA": "M", "TGA": "W"]),
        make(id: 3, name: "Yeast Mitochondrial", overrides: ["ATA": "M", "CTT": "T", "CTC": "T", "CTA": "T", "CTG": "T", "TGA": "W"]),
        make(id: 4, name: "Mold / Protozoan / Coelenterate Mitochondrial", overrides: ["TGA": "W"]),
        make(id: 5, name: "Invertebrate Mitochondrial", overrides: ["AGA": "S", "AGG": "S", "ATA": "M", "TGA": "W"]),
        make(id: 6, name: "Ciliate / Dasycladacean / Hexamita Nuclear", overrides: ["TAA": "Q", "TAG": "Q"]),
        make(id: 9, name: "Echinoderm / Flatworm Mitochondrial", overrides: ["AAA": "N", "AGA": "S", "AGG": "S", "TGA": "W"]),
        make(id: 10, name: "Euplotid Nuclear", overrides: ["TGA": "C"]),
        make(id: 11, name: "Bacterial / Archaeal / Plant Plastid", overrides: [:]),
        make(id: 12, name: "Alternative Yeast Nuclear", overrides: ["CTG": "S"]),
        make(id: 13, name: "Ascidian Mitochondrial", overrides: ["AGA": "G", "AGG": "G", "ATA": "M", "TGA": "W"]),
        make(id: 14, name: "Alternative Flatworm Mitochondrial", overrides: ["AAA": "N", "AGA": "S", "AGG": "S", "TAA": "Y", "TGA": "W"]),
        make(id: 21, name: "Trematode Mitochondrial", overrides: ["TGA": "W", "ATA": "M", "AGA": "S", "AGG": "S", "AAA": "N"]),
        make(id: 25, name: "Candidate Division SR1 / Gracilibacteria", overrides: ["TGA": "G"]),
    ]

    public static func table(id: Int) -> GeneticCodeTable {
        all.first { $0.id == id } ?? standard
    }
}

/// Codon usage tables for back-translation (most-frequent codon per residue).
public struct CodonUsageTable: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    let codons: [Character: String]

    public func codon(for aminoAcid: Character) -> String? { codons[aminoAcid] }

    public static let human = CodonUsageTable(id: "human", name: "Human (high frequency)", codons: [
        "F": "TTC", "L": "CTG", "I": "ATC", "M": "ATG", "V": "GTG", "S": "AGC", "P": "CCC",
        "T": "ACC", "A": "GCC", "Y": "TAC", "H": "CAC", "Q": "CAG", "N": "AAC", "K": "AAG",
        "D": "GAC", "E": "GAG", "C": "TGC", "W": "TGG", "R": "CGG", "G": "GGC", "*": "TGA",
    ])

    public static let ecoli = CodonUsageTable(id: "ecoli", name: "E. coli (high frequency)", codons: [
        "F": "TTT", "L": "CTG", "I": "ATT", "M": "ATG", "V": "GTG", "S": "AGC", "P": "CCG",
        "T": "ACC", "A": "GCG", "Y": "TAT", "H": "CAT", "Q": "CAG", "N": "AAC", "K": "AAA",
        "D": "GAT", "E": "GAA", "C": "TGC", "W": "TGG", "R": "CGC", "G": "GGC", "*": "TAA",
    ])

    public static let all: [CodonUsageTable] = [human, ecoli]
}

// MARK: - Sequence transforms

public enum SequenceTools {
    private static let complementMap: [Character: Character] = [
        "A": "T", "T": "A", "U": "A", "G": "C", "C": "G",
        "R": "Y", "Y": "R", "S": "S", "W": "W", "K": "M", "M": "K",
        "B": "V", "V": "B", "D": "H", "H": "D", "N": "N", "-": "-",
    ]

    /// Uppercase and keep only nucleotide/IUPAC characters (drops FASTA headers, digits, whitespace).
    public static func cleanNucleotides(_ raw: String) -> String {
        let allowed = Set("ACGTURYSWKMBDHVN-")
        var out = String.UnicodeScalarView()
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == ">" { continue }
            for ch in line.uppercased() where allowed.contains(ch) {
                out.append(contentsOf: String(ch).unicodeScalars)
            }
        }
        return String(out)
    }

    /// Uppercase and keep only amino-acid letters (drops FASTA headers, digits, whitespace, stops).
    public static func cleanProtein(_ raw: String) -> String {
        let allowed = Set("ACDEFGHIKLMNPQRSTVWYBXZUO")
        var out = ""
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == ">" { continue }
            for ch in line.uppercased() where allowed.contains(ch) {
                out.append(ch)
            }
        }
        return out
    }

    public static func complement(_ raw: String) -> String {
        String(cleanNucleotides(raw).map { complementMap[$0] ?? "N" })
    }

    public static func reverse(_ raw: String) -> String {
        String(cleanNucleotides(raw).reversed())
    }

    public static func reverseComplement(_ raw: String) -> String {
        String(cleanNucleotides(raw).reversed().map { complementMap[$0] ?? "N" })
    }

    /// Translate a nucleotide sequence. `frame` in 1...3 reads the forward strand from
    /// offset frame-1; frame in -1...-3 reads the reverse-complement strand.
    public static func translate(_ raw: String, frame: Int, code: GeneticCodeTable = .standard) -> String {
        let clean = frame < 0 ? reverseComplement(raw) : cleanNucleotides(raw)
        let offset = abs(frame) - 1
        guard offset >= 0, offset < clean.count else { return "" }
        let chars = Array(clean)
        var protein = ""
        protein.reserveCapacity((chars.count - offset) / 3)
        var i = offset
        while i + 3 <= chars.count {
            protein.append(code.translate(codon: String(chars[i..<i + 3])))
            i += 3
        }
        return protein
    }

    public struct FrameTranslation: Identifiable, Hashable, Sendable {
        public let frame: Int
        public let label: String
        public let protein: String
        public var id: Int { frame }
    }

    /// Six-frame translation in ExPASy order: 5'3' frames 1-3 then 3'5' frames 1-3.
    public static func sixFrameTranslation(_ raw: String, code: GeneticCodeTable = .standard) -> [FrameTranslation] {
        [1, 2, 3, -1, -2, -3].map { frame in
            FrameTranslation(
                frame: frame,
                label: frame > 0 ? "5'3' Frame \(frame)" : "3'5' Frame \(abs(frame))",
                protein: translate(raw, frame: frame, code: code)
            )
        }
    }

    public struct OpenReadingFrame: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let frame: Int
        public let startNucleotide: Int   // 1-based position on the input (forward coordinates)
        public let endNucleotide: Int
        public let peptide: String        // includes leading M, excludes the stop
        public var length: Int { peptide.count }
    }

    /// Find Met-to-Stop open reading frames across all six frames, longest first.
    public static func findORFs(_ raw: String, code: GeneticCodeTable = .standard, minLength: Int = 20) -> [OpenReadingFrame] {
        let forward = cleanNucleotides(raw)
        let total = forward.count
        var orfs: [OpenReadingFrame] = []

        for frame in [1, 2, 3, -1, -2, -3] {
            let strand = frame < 0 ? String(Array(forward).reversed().map { complementMap[$0] ?? "N" }) : forward
            let chars = Array(strand)
            let offset = abs(frame) - 1
            var codonStart = offset
            var peptide = ""
            var pepStartCodon = -1
            while codonStart + 3 <= chars.count {
                let aa = code.translate(codon: String(chars[codonStart..<codonStart + 3]))
                if peptide.isEmpty {
                    if aa == "M" { pepStartCodon = codonStart; peptide = "M" }
                } else if aa == "*" {
                    if peptide.count >= minLength {
                        orfs.append(makeORF(frame: frame, strandStart: pepStartCodon, strandEnd: codonStart + 2, peptide: peptide, total: total))
                    }
                    peptide = ""
                    pepStartCodon = -1
                } else {
                    peptide.append(aa)
                }
                codonStart += 3
            }
            if peptide.count >= minLength {
                orfs.append(makeORF(frame: frame, strandStart: pepStartCodon, strandEnd: chars.count - 1, peptide: peptide, total: total))
            }
        }
        return orfs.sorted { $0.length > $1.length }
    }

    private static func makeORF(frame: Int, strandStart: Int, strandEnd: Int, peptide: String, total: Int) -> OpenReadingFrame {
        // Convert strand-local indices back to forward (1-based) coordinates.
        if frame > 0 {
            return OpenReadingFrame(frame: frame, startNucleotide: strandStart + 1, endNucleotide: strandEnd + 1, peptide: peptide)
        } else {
            return OpenReadingFrame(frame: frame, startNucleotide: total - strandStart, endNucleotide: total - strandEnd, peptide: peptide)
        }
    }

    /// Reverse-translate a protein into a nucleotide sequence using an organism's most-frequent codons.
    public static func backTranslate(_ raw: String, usage: CodonUsageTable = .human) -> String {
        var out = ""
        for aa in cleanProtein(raw) {
            out += usage.codon(for: aa) ?? "NNN"
        }
        return out
    }
}
