
extension Array where Element == PointPermission {
    mutating func mergeUnique(_ other: [PointPermission]) {
        for perm in other where !contains(where: { $0.technology == perm.technology &&
            $0.operatorName == perm.operatorName }) {
            append(perm)
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
