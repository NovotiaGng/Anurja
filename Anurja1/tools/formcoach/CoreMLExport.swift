import CoreML
import Foundation

// Writes a FormNetwork as an updatable Core ML neural network (.mlmodel),
// encoding the Core ML protobuf spec directly so the pipeline stays Swift-only.
// Field numbers are from apple/coremltools mlmodel/format/{Model,FeatureTypes,
// NeuralNetwork,Parameters,DataStructures}.proto. Spec version 4 (Core ML 3,
// iOS 13+), the first with on-device updates.
//
// Model: features[36] -> dense1 (scaler folded in) -> ReLU -> dense2 -> sigmoid -> checks[K]
// The last layer is updatable: MSE loss on `checks` against `checks_true`,
// SGD, run on the phone by MLUpdateTask from the user's corrected reps.

/// Minimal protobuf writer: just the wire types the spec needs.
struct ProtoWriter {
    private(set) var data = Data()

    private mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, _ wire: UInt64) { varint(UInt64(field) << 3 | wire) }

    mutating func int(_ field: Int, _ value: Int64) {
        guard value != 0 else { return }
        tag(field, 0)
        varint(UInt64(bitPattern: value))
    }

    mutating func bool(_ field: Int, _ value: Bool) { int(field, value ? 1 : 0) }

    mutating func double(_ field: Int, _ value: Double) {
        tag(field, 1)
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }

    /// Always written, even when empty: an empty message still selects a oneof case.
    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        bytes(field, inner.data)
    }

    mutating func floats(_ field: Int, _ values: [Float]) {
        var packed = Data()
        for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { packed.append(contentsOf: $0) } }
        bytes(field, packed)
    }

    mutating func int64s(_ field: Int, _ values: [Int64]) {
        var inner = ProtoWriter()
        for v in values { inner.varint(UInt64(bitPattern: v)) }
        bytes(field, inner.data)
    }
}

enum CoreMLExport {
    static let doubleArray: Int64 = 65600  // ArrayFeatureType.DOUBLE

    private static func arrayFeature(_ w: inout ProtoWriter, _ field: Int, name: String, count: Int, about: String) {
        w.message(field) { d in                                    // FeatureDescription
            d.string(1, name)
            d.string(2, about)
            d.message(3) { t in                                    // FeatureType
                t.message(5) { a in                                // multiArrayType
                    a.int64s(1, [Int64(count)])                    // shape
                    a.int(2, doubleArray)                          // dataType
                }
            }
        }
    }

    private static func dense(_ w: inout ProtoWriter, name: String, input: String, output: String,
                              weights: [[Double]], bias: [Double], updatable: Bool) {
        w.message(1) { l in                                        // NeuralNetwork.layers
            l.string(1, name)
            l.string(2, input)
            l.string(3, output)
            l.bool(10, updatable)
            l.message(140) { p in                                  // innerProduct
                p.int(1, Int64(weights[0].count))                  // inputChannels
                p.int(2, Int64(weights.count))                     // outputChannels
                p.bool(10, true)                                   // hasBias
                p.message(20) { v in                               // weights [C_out, C_in]
                    v.floats(1, weights.flatMap { $0.map(Float.init) })
                    v.bool(50, updatable)
                }
                p.message(21) { v in                               // bias
                    v.floats(1, bias.map(Float.init))
                    v.bool(50, updatable)
                }
            }
        }
    }

    private static func activation(_ w: inout ProtoWriter, name: String, input: String, output: String, kind: Int) {
        w.message(1) { l in
            l.string(1, name)
            l.string(2, input)
            l.string(3, output)
            l.message(130) { a in a.message(kind) { _ in } }       // activation: ReLU = 10, sigmoid = 40
        }
    }

    static func spec(_ net: FormNetwork, exercise: String, metadata: [String: String]) -> Data {
        // Fold the input standardisation into the first layer.
        let w1 = net.w1.map { row in row.indices.map { row[$0] / net.scale[$0] } }
        let b1 = net.w1.indices.map { j in
            net.b1[j] - net.w1[j].indices.reduce(0) { $0 + net.w1[j][$1] * net.mean[$1] / net.scale[$1] }
        }
        let inputs = net.mean.count, outputs = net.outputs.count
        var model = ProtoWriter()
        model.int(1, 4)                                            // specificationVersion
        model.message(2) { d in                                    // ModelDescription
            arrayFeature(&d, 1, name: "features", count: inputs, about: "36 pose features from FormFeatures.swift")
            arrayFeature(&d, 10, name: "checks", count: outputs,
                         about: "Probability each is hit: " + net.outputs.joined(separator: ", "))
            arrayFeature(&d, 50, name: "features", count: inputs, about: "36 pose features from FormFeatures.swift")
            arrayFeature(&d, 50, name: "checks_true", count: outputs, about: "Corrected targets, 0 or 1")
            d.message(100) { m in                                  // Metadata
                m.string(1, "Form checkpoints for \(exercise), one camera frame at a time.")
                m.string(3, "Anurja. Trained on UI-PRMD (Vakanski et al. 2018).")
                m.string(4, "Training data: Open Data Commons PDDL (public domain).")
                for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                    m.message(100) { e in e.string(1, key); e.string(2, value) }
                }
            }
        }
        model.bool(10, true)                                       // isUpdatable
        model.message(500) { nn in                                 // neuralNetwork
            dense(&nn, name: "dense1", input: "features", output: "dense1_out", weights: w1, bias: b1, updatable: false)
            activation(&nn, name: "relu1", input: "dense1_out", output: "relu1_out", kind: 10)
            dense(&nn, name: "dense2", input: "relu1_out", output: "dense2_out", weights: net.w2, bias: net.b2, updatable: true)
            activation(&nn, name: "sigmoid", input: "dense2_out", output: "checks", kind: 40)
            nn.message(10) { u in                                  // updateParams
                u.message(1) { loss in                             // lossLayers
                    loss.string(1, "loss")
                    loss.message(11) { mse in mse.string(1, "checks"); mse.string(2, "checks_true") }
                }
                u.message(2) { o in                                // optimizer
                    o.message(10) { sgd in                         // sgdOptimizer
                        sgd.message(1) { p in p.double(1, 0.5); p.message(10) { r in r.double(1, 0); r.double(2, 5) } }
                        sgd.message(2) { p in p.int(1, 16); p.message(11) { s in s.int64s(1, [16]) } }
                        sgd.message(3) { p in p.double(1, 0.9); p.message(10) { r in r.double(1, 0); r.double(2, 1) } }
                    }
                }
                u.message(3) { p in p.int(1, 20); p.message(11) { s in s.int64s(1, [20]) } }   // epochs
                u.message(10) { p in p.bool(1, true) }             // shuffle
            }
        }
        return model.data
    }

    static func modelName(_ exercise: String) -> String { "Form" + exercise.prefix(1).uppercased() + exercise.dropFirst() }

    /// Writes Anurja/FormModels/Form<Exercise>.mlmodel and loads it back through Core ML.
    static func write(_ net: FormNetwork, exercise: String, metadata: [String: String], to folder: URL) async throws -> MLModel {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(modelName(exercise)).mlmodel")
        try spec(net, exercise: exercise, metadata: metadata).write(to: url)
        return try await load(url)
    }

    static func load(_ url: URL) async throws -> MLModel {
        let compiled = try await MLModel.compileModel(at: url)
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        return try MLModel(contentsOf: compiled, configuration: config)
    }

    static func predict(_ model: MLModel, _ x: [Double]) throws -> [Double] {
        let input = try MLMultiArray(shape: [NSNumber(value: x.count)], dataType: .double)
        for (i, v) in x.enumerated() { input[i] = NSNumber(value: v) }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["features": input]))
        let checks = out.featureValue(for: "checks")!.multiArrayValue!
        return (0..<checks.count).map { checks[$0].doubleValue }
    }
}
