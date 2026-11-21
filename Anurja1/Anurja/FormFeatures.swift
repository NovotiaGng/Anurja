import Foundation
import simd

// Shared by the app and tools/formcoach/TrainFormModel.swift, so training and
// the phone compute exactly the same numbers. Foundation + simd only.

/// 36 numbers describing one camera frame of a body pose.
enum FormFeatures {
    static let count = 36

    /// Points in the order lS rS lE rE lW rW lH rH lK rK lA rA, image
    /// coordinates with x and y in the same units and y pointing down.
    static func vector(_ p: [SIMD2<Double>]) -> [Double] {
        precondition(p.count == 12)
        let hip = (p[6] + p[7]) / 2
        let shoulders = (p[0] + p[1]) / 2
        let scale = max(simd_length(shoulders - hip), 1e-6)
        let q = p.map { ($0 - hip) / scale }

        func angle(_ a: Int, _ b: Int, _ c: Int) -> Double {
            let u = q[a] - q[b], v = q[c] - q[b]
            return abs(atan2(u.x * v.y - u.y * v.x, simd_dot(u, v))) * 180 / .pi
        }
        /// Degrees the top-to-bottom segment leans away from vertical.
        func lean(_ top: SIMD2<Double>, _ bottom: SIMD2<Double>) -> Double {
            atan2(abs(top.x - bottom.x), bottom.y - top.y) * 180 / .pi
        }

        var f = q.flatMap { [$0.x, $0.y] }
        // knee L/R, hip L/R, elbow L/R, shoulder (hip-shoulder-elbow) L/R
        f += [angle(6, 8, 10), angle(7, 9, 11), angle(0, 6, 8), angle(1, 7, 9),
              angle(0, 2, 4), angle(1, 3, 5), angle(6, 0, 2), angle(7, 1, 3)].map { $0 / 180 }
        // torso, left shin, right shin
        f += [lean((q[0] + q[1]) / 2, (q[6] + q[7]) / 2), lean(q[8], q[10]), lean(q[9], q[11])].map { $0 / 90 }
        // knee gap / ankle gap: low while bent = knees caving in
        let ankleGap = max(abs(q[10].x - q[11].x), 0.1)
        f.append(min(abs(q[8].x - q[9].x) / ankleGap, 3) / 3)
        return f
    }
}
