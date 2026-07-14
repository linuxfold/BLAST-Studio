import Foundation

/// A full physicochemical analysis of a protein, mirroring ExPASy ProtParam.
public struct ProtParamResult: Sendable {
    public struct CompositionEntry: Sendable, Identifiable {
        public let code: Character
        public let name: String
        public let count: Int
        public let percent: Double
        public var id: Character { code }
    }

    public let cleanedSequence: String
    public let residueCount: Int
    public let molecularWeight: Double
    public let theoreticalPI: Double
    public let composition: [CompositionEntry]
    public let negativeResidueCount: Int   // Asp + Glu
    public let positiveResidueCount: Int   // Arg + Lys
    public let atomCounts: (carbon: Int, hydrogen: Int, nitrogen: Int, oxygen: Int, sulfur: Int)
    public let totalAtoms: Int
    public let formula: String
    public let extinctionCystine: Int      // assuming all Cys form cystines
    public let extinctionReduced: Int      // assuming all Cys reduced
    public let abs01Cystine: Double        // Abs 0.1% (=1 g/l), cystines
    public let abs01Reduced: Double
    public let cysteineCount: Int
    public let tyrosineCount: Int
    public let tryptophanCount: Int
    public let halfLifeMammalian: String
    public let halfLifeYeast: String
    public let halfLifeEcoli: String
    public let instabilityIndex: Double
    public let isStable: Bool
    public let aliphaticIndex: Double
    public let gravy: Double
    public let nTerminal: Character
    public let cTerminal: Character
}

public enum ProtParam {
    static let standardResidues = Array("ACDEFGHIKLMNPQRSTVWY")

    public static let aaNames: [Character: String] = [
        "A": "Ala", "R": "Arg", "N": "Asn", "D": "Asp", "C": "Cys", "E": "Glu", "Q": "Gln",
        "G": "Gly", "H": "His", "I": "Ile", "L": "Leu", "K": "Lys", "M": "Met", "F": "Phe",
        "P": "Pro", "S": "Ser", "T": "Thr", "W": "Trp", "Y": "Tyr", "V": "Val",
    ]

    // Average residue masses (Da); protein MW = sum + one water.
    static let residueMass: [Character: Double] = [
        "A": 71.0788, "R": 156.1875, "N": 114.1038, "D": 115.0886, "C": 103.1388,
        "E": 129.1155, "Q": 128.1307, "G": 57.0519, "H": 137.1411, "I": 113.1594,
        "L": 113.1594, "K": 128.1741, "M": 131.1926, "F": 147.1766, "P": 97.1167,
        "S": 87.0782, "T": 101.1051, "W": 186.2132, "Y": 163.1760, "V": 99.1326,
    ]
    static let waterMass = 18.01524

    // Atomic composition per residue (C, H, N, O, S); whole protein adds one water (H2, O1).
    static let residueAtoms: [Character: (Int, Int, Int, Int, Int)] = [
        "G": (2, 3, 1, 1, 0), "A": (3, 5, 1, 1, 0), "S": (3, 5, 1, 2, 0), "P": (5, 7, 1, 1, 0),
        "V": (5, 9, 1, 1, 0), "T": (4, 7, 1, 2, 0), "C": (3, 5, 1, 1, 1), "L": (6, 11, 1, 1, 0),
        "I": (6, 11, 1, 1, 0), "N": (4, 6, 2, 2, 0), "D": (4, 5, 1, 3, 0), "Q": (5, 8, 2, 2, 0),
        "K": (6, 12, 2, 1, 0), "E": (5, 7, 1, 3, 0), "M": (5, 9, 1, 1, 1), "H": (6, 7, 3, 1, 0),
        "F": (9, 9, 1, 1, 0), "R": (6, 12, 4, 1, 0), "Y": (9, 9, 1, 2, 0), "W": (11, 10, 2, 1, 0),
    ]

    // pKa values used by ExPASy compute_pi (Bjellqvist).
    static let sidePositivePK: [Character: Double] = ["K": 10.0, "R": 12.0, "H": 5.98]
    static let sideNegativePK: [Character: Double] = ["D": 4.05, "E": 4.45, "C": 9.0, "Y": 10.0]
    static let nTermDefault = 7.5
    static let nTermPK: [Character: Double] = ["A": 7.59, "M": 7.0, "S": 6.93, "P": 8.36, "T": 6.82, "V": 7.44, "E": 7.7]
    static let cTermDefault = 3.55
    static let cTermPK: [Character: Double] = ["D": 4.55, "E": 4.75]

    // N-end rule estimated half-lives.
    static let halfLife: [Character: (String, String, String)] = [
        "A": ("4.4 hours", ">20 hours", ">10 hours"),
        "R": ("1 hour", "2 min", "2 min"),
        "N": ("1.4 hours", "3 min", ">10 hours"),
        "D": ("1.1 hours", "3 min", ">10 hours"),
        "C": ("1.2 hours", ">20 hours", ">10 hours"),
        "Q": ("0.8 hours", "10 min", ">10 hours"),
        "E": ("1 hour", "30 min", ">10 hours"),
        "G": ("30 hours", ">20 hours", ">10 hours"),
        "H": ("3.5 hours", "10 min", ">10 hours"),
        "I": ("20 hours", "30 min", ">10 hours"),
        "L": ("5.5 hours", "3 min", "2 min"),
        "K": ("1.3 hours", "3 min", "2 min"),
        "M": ("30 hours", ">20 hours", ">10 hours"),
        "F": ("1.1 hours", "3 min", "2 min"),
        "P": (">20 hours", ">20 hours", "?"),
        "S": ("1.9 hours", ">20 hours", ">10 hours"),
        "T": ("7.2 hours", ">20 hours", ">10 hours"),
        "W": ("2.8 hours", "3 min", "2 min"),
        "Y": ("2.8 hours", "10 min", "2 min"),
        "V": ("100 hours", ">20 hours", ">10 hours"),
    ]

    /// Compute ProtParam properties. Returns nil if no standard residues are present.
    public static func analyze(_ raw: String) -> ProtParamResult? {
        let cleaned = SequenceTools.cleanProtein(raw)
        // Restrict computations to the 20 standard residues.
        let residues = cleaned.filter { standardResidues.contains($0) }
        guard !residues.isEmpty else { return nil }
        let chars = Array(residues)
        let n = chars.count

        var counts: [Character: Int] = [:]
        for c in chars { counts[c, default: 0] += 1 }

        // Molecular weight
        let mw = chars.reduce(0.0) { $0 + (residueMass[$1] ?? 0) } + waterMass

        // Composition
        let composition = standardResidues.map { aa in
            let count = counts[aa] ?? 0
            return ProtParamResult.CompositionEntry(
                code: aa, name: aaNames[aa] ?? String(aa), count: count,
                percent: n > 0 ? Double(count) / Double(n) * 100 : 0
            )
        }

        let negative = (counts["D"] ?? 0) + (counts["E"] ?? 0)
        let positive = (counts["R"] ?? 0) + (counts["K"] ?? 0)

        // Atomic composition (+ one water for the whole chain)
        var c = 0, h = 0, nAt = 0, o = 0, s = 0
        for ch in chars {
            if let a = residueAtoms[ch] { c += a.0; h += a.1; nAt += a.2; o += a.3; s += a.4 }
        }
        h += 2; o += 1
        let total = c + h + nAt + o + s
        let formula = molecularFormula(c: c, h: h, n: nAt, o: o, s: s)

        // Extinction coefficient (Gill & von Hippel / Edelhoch)
        let nTyr = counts["Y"] ?? 0, nTrp = counts["W"] ?? 0, nCys = counts["C"] ?? 0
        let cystines = nCys / 2
        let extReduced = nTyr * 1490 + nTrp * 5500
        let extCystine = extReduced + cystines * 125
        let abs01Reduced = mw > 0 ? Double(extReduced) / mw : 0
        let abs01Cystine = mw > 0 ? Double(extCystine) / mw : 0

        // pI
        let pI = isoelectricPoint(chars: chars, counts: counts)

        // Instability index
        var diSum = 0.0
        for i in 0..<(chars.count - 1) {
            diSum += SequenceConstants.instabilityDipeptide[chars[i]]?[chars[i + 1]] ?? 0
        }
        let instability = n > 1 ? (10.0 / Double(n)) * diSum : 0

        // Aliphatic index: X_Ala + 2.9 X_Val + 3.9 (X_Ile + X_Leu), X = mole percent
        func molePercent(_ aa: Character) -> Double { Double(counts[aa] ?? 0) / Double(n) * 100 }
        let aliphatic = molePercent("A") + 2.9 * molePercent("V") + 3.9 * (molePercent("I") + molePercent("L"))

        // GRAVY (Kyte-Doolittle)
        let gravy = chars.reduce(0.0) { $0 + (SequenceConstants.kyteDoolittle[$1] ?? 0) } / Double(n)

        let hl = halfLife[chars.first!] ?? ("N/A", "N/A", "N/A")

        return ProtParamResult(
            cleanedSequence: residues,
            residueCount: n,
            molecularWeight: mw,
            theoreticalPI: pI,
            composition: composition,
            negativeResidueCount: negative,
            positiveResidueCount: positive,
            atomCounts: (c, h, nAt, o, s),
            totalAtoms: total,
            formula: formula,
            extinctionCystine: extCystine,
            extinctionReduced: extReduced,
            abs01Cystine: abs01Cystine,
            abs01Reduced: abs01Reduced,
            cysteineCount: nCys,
            tyrosineCount: nTyr,
            tryptophanCount: nTrp,
            halfLifeMammalian: hl.0,
            halfLifeYeast: hl.1,
            halfLifeEcoli: hl.2,
            instabilityIndex: instability,
            isStable: instability <= 40,
            aliphaticIndex: aliphatic,
            gravy: gravy,
            nTerminal: chars.first!,
            cTerminal: chars.last!
        )
    }

    private static func molecularFormula(c: Int, h: Int, n: Int, o: Int, s: Int) -> String {
        var parts: [String] = []
        if c > 0 { parts.append("C\(c)") }
        if h > 0 { parts.append("H\(h)") }
        if n > 0 { parts.append("N\(n)") }
        if o > 0 { parts.append("O\(o)") }
        if s > 0 { parts.append("S\(s)") }
        return parts.joined()
    }

    /// Net charge of the protein at a given pH.
    static func netCharge(pH: Double, chars: [Character], counts: [Character: Int]) -> Double {
        var charge = 0.0
        // N-terminus (positive)
        let nPK = nTermPK[chars.first!] ?? nTermDefault
        charge += 1.0 / (1.0 + pow(10.0, pH - nPK))
        // C-terminus (negative)
        let cPK = cTermPK[chars.last!] ?? cTermDefault
        charge -= 1.0 / (1.0 + pow(10.0, cPK - pH))
        // Positive side chains
        for (aa, pk) in sidePositivePK {
            let count = Double(counts[aa] ?? 0)
            if count > 0 { charge += count / (1.0 + pow(10.0, pH - pk)) }
        }
        // Negative side chains
        for (aa, pk) in sideNegativePK {
            let count = Double(counts[aa] ?? 0)
            if count > 0 { charge -= count / (1.0 + pow(10.0, pk - pH)) }
        }
        return charge
    }

    static func isoelectricPoint(chars: [Character], counts: [Character: Int]) -> Double {
        var low = 0.0, high = 14.0
        // Bisection to the pH where net charge crosses zero.
        for _ in 0..<100 {
            let mid = (low + high) / 2
            let charge = netCharge(pH: mid, chars: chars, counts: counts)
            if charge > 0 { low = mid } else { high = mid }
            if high - low < 0.0001 { break }
        }
        return (low + high) / 2
    }
}
