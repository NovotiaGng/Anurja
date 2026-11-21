import Foundation

/// One-hidden-layer ReLU network with a sigmoid per output: "form_ok" plus
/// one probability per form checkpoint. Training only: CoreMLExport.swift
/// writes it out as an updatable Core ML model for the app.
struct FormNetwork: Codable {
    /// "form_ok" followed by FormCheck ids.
    var outputs: [String]
    /// Outputs that beat the plain 2D rule on validation; the rest use the rule.
    var useModel: [String]
    var mean: [Double]
    var scale: [Double]
    /// [hidden][input]
    var w1: [[Double]]
    var b1: [Double]
    /// [output][hidden]
    var w2: [[Double]]
    var b2: [Double]

    init(outputs: [String], mean: [Double], scale: [Double], hidden: Int, seed: inout UInt64) {
        func uniform(_ limit: Double) -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) / Double(1 << 53) * 2 - 1) * limit
        }
        let inputs = mean.count
        self.outputs = outputs
        useModel = outputs
        self.mean = mean
        self.scale = scale
        let l1 = (6.0 / Double(inputs + hidden)).squareRoot(), l2 = (6.0 / Double(hidden + outputs.count)).squareRoot()
        w1 = (0..<hidden).map { _ in (0..<inputs).map { _ in uniform(l1) } }
        b1 = Array(repeating: 0, count: hidden)
        w2 = outputs.map { _ in (0..<hidden).map { _ in uniform(l2) } }
        b2 = Array(repeating: 0, count: outputs.count)
    }

    func hidden(_ x: [Double]) -> [Double] {
        w1.indices.map { j in
            var z = b1[j]
            let row = w1[j]
            for i in row.indices { z += row[i] * (x[i] - mean[i]) / scale[i] }
            return max(0, z)
        }
    }

    private func head(_ h: [Double]) -> [Double] {
        w2.indices.map { k in
            var z = b2[k]
            for j in h.indices { z += w2[k][j] * h[j] }
            return 1 / (1 + exp(-z))
        }
    }

    func predict(_ x: [Double]) -> [Double] { head(hidden(x)) }

    func scores(_ x: [Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: zip(outputs, predict(x)))
    }

    /// Mini-batch SGD with momentum on binary cross-entropy. `lastLayerOnly`
    /// keeps the learned pose features and only re-weighs them, which is what
    /// on-device personalisation does with a few hundred of the user's frames.
    mutating func fit(_ x: [[Double]], _ y: [[Double]], epochs: Int, rate: Double, lastLayerOnly: Bool = false,
                      batch: Int = 64, decay: Double = 1e-4, seed: UInt64 = 1) {
        let hiddenCount = b1.count, outCount = b2.count, inCount = mean.count
        var v1 = w1.map { $0.map { _ in 0.0 } }, vb1 = b1.map { _ in 0.0 }
        var v2 = w2.map { $0.map { _ in 0.0 } }, vb2 = b2.map { _ in 0.0 }
        var order = Array(x.indices)
        var rng = seed
        let z = x.map { row in row.indices.map { (row[$0] - mean[$0]) / scale[$0] } }
        // Fixed features: hidden layer can be computed once.
        let frozen = lastLayerOnly ? x.map(hidden) : []
        for _ in 0..<epochs {
            for i in stride(from: order.count - 1, to: 0, by: -1) {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                order.swapAt(i, Int((rng >> 33) % UInt64(i + 1)))
            }
            for start in stride(from: 0, to: order.count, by: batch) {
                let idx = order[start..<min(start + batch, order.count)]
                var g1 = lastLayerOnly ? [] : w1.map { $0.map { _ in 0.0 } }, gb1 = b1.map { _ in 0.0 }
                var g2 = w2.map { $0.map { _ in 0.0 } }, gb2 = b2.map { _ in 0.0 }
                for n in idx {
                    let h = lastLayerOnly ? frozen[n] : hidden(x[n])
                    let p = head(h)
                    var dh = Array(repeating: 0.0, count: hiddenCount)
                    for k in 0..<outCount {
                        let d = p[k] - y[n][k]
                        gb2[k] += d
                        for j in 0..<hiddenCount {
                            g2[k][j] += d * h[j]
                            dh[j] += d * w2[k][j]
                        }
                    }
                    guard !lastLayerOnly else { continue }
                    for j in 0..<hiddenCount where h[j] > 0 {
                        gb1[j] += dh[j]
                        for i in 0..<inCount { g1[j][i] += dh[j] * z[n][i] }
                    }
                }
                let s = rate / Double(idx.count)
                for k in 0..<outCount {
                    vb2[k] = 0.9 * vb2[k] - s * gb2[k]
                    b2[k] += vb2[k]
                    for j in 0..<hiddenCount {
                        v2[k][j] = 0.9 * v2[k][j] - s * g2[k][j] - rate * decay * w2[k][j]
                        w2[k][j] += v2[k][j]
                    }
                }
                guard !lastLayerOnly else { continue }
                for j in 0..<hiddenCount {
                    vb1[j] = 0.9 * vb1[j] - s * gb1[j]
                    b1[j] += vb1[j]
                    for i in 0..<inCount {
                        v1[j][i] = 0.9 * v1[j][i] - s * g1[j][i] - rate * decay * w1[j][i]
                        w1[j][i] += v1[j][i]
                    }
                }
            }
        }
    }
}
