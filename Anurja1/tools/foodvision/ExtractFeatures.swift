// Vision image feature prints for every prepared photo, the same request
// FoodRecognizer makes in the app (revision 2, 768 floats).
//
//   swiftc -O -o /tmp/food-features tools/foodvision/ExtractFeatures.swift
//   /tmp/food-features [data dir]        # default tools/foodvision/data
//
// Writes <data>/<split>.f32 (row-major float32) and <data>/<split>.labels.

import Foundation
import Vision

let data = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "data").path)
let fm = FileManager.default

var seen: [String: String] = [:]  // file name -> split: a photo in two splits would leak into the test score
for split in ["train", "val", "test"] {
    var floats = Data()
    var labels: [String] = []
    let folder = data.appending(path: split)
    for label in try fm.contentsOfDirectory(atPath: folder.path).sorted() where !label.hasPrefix(".") {
        for file in try fm.contentsOfDirectory(atPath: folder.appending(path: label).path).sorted() where file.hasSuffix(".jpg") {
            if let other = seen.updateValue(split, forKey: file), other != split {
                fatalError("\(file) is in both \(other) and \(split); rebuild data/{train,val,test}")
            }
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            try VNImageRequestHandler(url: folder.appending(path: "\(label)/\(file)")).perform([request])
            guard let print = request.results?.first, print.elementType == .float, print.elementCount == 768 else {
                fatalError("unexpected feature print for \(label)/\(file)")
            }
            floats.append(print.data)
            labels.append(label)
        }
    }
    try floats.write(to: data.appending(path: "\(split).f32"))
    try labels.joined(separator: "\n").write(to: data.appending(path: "\(split).labels"), atomically: true, encoding: .utf8)
    print(split, labels.count)
}
