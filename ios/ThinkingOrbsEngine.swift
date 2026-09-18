import Foundation

func thinkingOrbsPhase(period: Double, speed: Double, reverse: Bool, startAt: Double, seconds: Double) -> Double {
    let p = period / orbMax(0.0001, speed)
    var u = orbMod(seconds, p) / p
    if u < 0 { u += 1 }
    if reverse { u = 1 - u }
    u = orbMod(u + startAt, 1)
    return u < 0 ? u + 1 : u
}

func thinkingOrbsFit(size: Double) -> Double {
    OrbFitCache.shared.fit(10, size, .identity)
}

func thinkingOrbsDotScale(size: Double) -> Double {
    if size <= 46 { return 0.4 }
    if size <= 190 { return 0.4 + ((size - 46) / 144) * 0.6 }
    if size <= 340 { return 1 + ((size - 190) / 150) * 0.55 }
    return 1.55
}

private struct OrbVec {
    let a: [Double]
    init(_ a: [Double]) { self.a = a }
    subscript(_ i: Double) -> Double {
        guard i >= 0, i < Double(a.count) else { return Double.nan }
        return a[Int(i)]
    }
}

private struct OrbKnobs {
    var n: Double = 1
    var sp: Double = 1
    var pv: Double = 1
    var dz: Double = 1
    var df: Double = 1
    var yw: Double = 0
    var pc: Double = 0
    var sn: Double = 0
    var op: Double = 1
    static let identity = OrbKnobs()
    var fitKey: String { "\(n)/\(sp)/\(pv)/\(dz)/\(df)/\(yw)/\(pc)/\(sn)/\(op)" }
}

private final class OrbSink {
    let ds: Double
    let n: Double
    let sp: Double
    let pv: Double
    let dz: Double
    let df: Double
    let yw: Double
    let pc: Double
    let sn: Double
    var t: Double
    private let sink: (Double, Double, Double, Double, Double) -> Void
    init(ds: Double, knobs Q: OrbKnobs, t: Double, _ sink: @escaping (Double, Double, Double, Double, Double) -> Void) {
        self.ds = ds
        self.n = Q.n
        self.sp = Q.sp
        self.pv = Q.pv
        self.dz = Q.dz
        self.df = Q.df
        self.yw = Q.yw
        self.pc = Q.pc
        self.sn = Q.sn
        self.t = t
        self.sink = sink
    }
    func d(_ x: Double, _ y: Double, _ r: Double, _ a: Double, _ col: Double) {
        sink(x, y, r, a, col)
    }
}

private func orbSin(_ x: Double) -> Double { sin(x) }
private func orbCos(_ x: Double) -> Double { cos(x) }
private func orbPow(_ x: Double, _ y: Double) -> Double { pow(x, y) }
private func orbAcos(_ x: Double) -> Double { acos(x) }
private func orbAtan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
private func orbSqrt(_ x: Double) -> Double { x.squareRoot() }
private func orbAbs(_ x: Double) -> Double { abs(x) }

private func orbRound(_ x: Double) -> Double {
    if x.isNaN || x.isInfinite || x == 0 { return x }
    if x > 0 && x < 0.5 { return 0 }
    if x < 0 && x >= -0.5 { return -0.0 }
    let f = floor(x)
    return x - f >= 0.5 ? f + 1 : f
}

private func orbMax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return .nan }
    return a > b ? a : b
}

private func orbMax(_ a: Double, _ b: Double, _ c: Double) -> Double { orbMax(orbMax(a, b), c) }

private func orbMin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return .nan }
    return a < b ? a : b
}

private func orbMod(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

private func orbTruthy(_ x: Double) -> Bool { x != 0 && !x.isNaN }

private func orbOr(_ a: Double, _ b: Double) -> Double { orbTruthy(a) ? a : b }

private func orbSortByIndex(_ arr: [OrbVec], _ key: Double) -> [OrbVec] {
    return arr.enumerated()
        .sorted { l, r in
            let a = l.element[key]
            let b = r.element[key]
            if a < b { return true }
            if b < a { return false }
            return l.offset < r.offset
        }
        .map { $0.element }
}

private enum OrbSpecs13 {
    static let TAU: Double = Double.pi * 2

    static func NC(_ c: Double, _ n: Double) -> Double {
        let v: Double = orbRound(c * n)
        return v < 1 ? 1 : v
    }

    static func VIEW(_ p: OrbVec, _ K: OrbSink) -> OrbVec {
        let ay: Double = K.yw + (((Double.pi * 2) * K.sn) * K.t)
        let ca: Double = orbCos(ay)
        let sa: Double = orbSin(ay)
        let X: Double = (p[0] * ca) - (p[2] * sa)
        var Z: Double = (p[0] * sa) + (p[2] * ca)
        let cb: Double = orbCos(K.pc)
        let sb: Double = orbSin(K.pc)
        let Y: Double = (p[1] * cb) - (Z * sb)
        Z = (p[1] * sb) + (Z * cb)
        return OrbVec([X, Y, Z, p[3], p[4], p[5]])
    }

    static func cl(_ u: Double) -> Double {
        return u < 0 ? 0 : (u > 1 ? 1 : u)
    }

    static func rot(_ p: OrbVec, _ ay: Double, _ ax: Double) -> OrbVec {
        let ca: Double = orbCos(ay)
        let sa: Double = orbSin(ay)
        let X: Double = (p[0] * ca) - (p[2] * sa)
        var Z: Double = (p[0] * sa) + (p[2] * ca)
        let cb: Double = orbCos(ax)
        let sb: Double = orbSin(ax)
        let Y: Double = (p[1] * cb) - (Z * sb)
        Z = (p[1] * sb) + (Z * cb)
        return OrbVec([X, Y, Z, p[3], p[4], p[5]])
    }

    static func P3(_ pts: [OrbVec], _ S2: Double, _ K: OrbSink, _ RF: Double) {
        let cx: Double = S2 / 2
        let cy: Double = S2 / 2
        let R: Double = (S2 * (orbOr(RF, 0.3))) * K.sp
        let f: Double = 3.5 * K.pv
        var out: [OrbVec] = []
        for p0 in pts {
            let p: OrbVec = VIEW(p0, K)
            let z: Double = p[2]
            let per: Double = f / (f - z)
            let d: Double = cl((z + 1.1) / 2.2)
            out.append(OrbVec([cx + ((p[0] * R) * per), cy + ((p[1] * R) * per), ((K.ds * (0.4 + ((1.6 * K.dz) * d))) * per) * (p[3].isNaN ? 1 : p[3]), (0.07 + (0.93 * orbPow(d, 1.55 * K.df))) * (p[4].isNaN ? 1 : p[4]), orbOr(p[5], 1), z]))
        }
        out = orbSortByIndex(out, 5)
        for o in out {
            K.d(o[0], o[1], o[2], o[3], o[4])
        }
    }

    static func fib(_ i: Double, _ N: Double) -> OrbVec {
        let y: Double = 1 - ((i / (N - 1)) * 2)
        let r: Double = orbSqrt(orbMax(0, 1 - (y * y)))
        let th: Double = i * 2.399963
        return OrbVec([orbCos(th) * r, y, orbSin(th) * r])
    }

    static func sph(_ p: OrbVec) -> OrbVec {
        return OrbVec([orbAcos(orbMax(-1, orbMin(1, p[1]))), orbAtan2(p[2], p[0])])
    }

    static func draw12(_ t: Double, _ S2: Double, _ K: OrbSink) {
        var pts: [OrbVec] = []
        var i: Double = 0
        let count = NC(160, K.n)
        while i < count {
            defer { i += 1 }
            let p: OrbVec = fib(i, count)
            let s: OrbVec = sph(p)
            let a: Double = orbSin(((4 * s[1]) + (6 * s[0])) - ((TAU * 2) * t))
            let b: Double = orbSin(((4 * s[1]) - (6 * s[0])) + ((TAU * 2) * t))
            let w: Double = cl(((a * b) + 1) / 2)
            pts.append(rot(OrbVec([p[0], p[1], p[2], 0.5 + (1.3 * w), 0.2 + (0.8 * w), w > 0.9 ? 2 : 1]), TAU * t, 0.36))
        }
        P3(pts, S2, K, 0.3)
    }
}

private final class OrbFitCache: @unchecked Sendable {
    static let shared = OrbFitCache()
    private var map: [String: Double] = [:]
    private let lock = NSLock()

    func fit(_ style: Int, _ size: Double, _ Q: OrbKnobs) -> Double {
        let key = "\(style)@\(size)@\(Q.fitKey)"
        lock.lock()
        if let hit = map[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let f = orbFit(size, Q)
        lock.lock()
        map[key] = f
        lock.unlock()
        return f
    }
}

private func orbFit(_ S: Double, _ Q: OrbKnobs) -> Double {
    let h = S / 2
    var ext: Double = 0
    let probe = OrbSink(ds: 1, knobs: Q, t: 0) { x, y, r, a, _ in
        if a <= 0.05 || r <= 0.15 { return }
        ext = orbMax(ext, orbAbs(x - h) + r * 0.5, orbAbs(y - h) + r * 0.5)
    }
    for k in 0 ..< 20 {
        probe.t = Double(k) / 20
        OrbSpecs13.draw12(Double(k) / 20, S, probe)
    }
    return ext > 1 ? orbMax(0.55, orbMin(1.7, (S * 0.415) / ext)) : 1
}
