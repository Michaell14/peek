import Foundation

/// Lays out overlapping calendar events side by side, the way a day view does.
public enum EventLayout {
    public struct Slot: Hashable, Sendable {
        /// Which column the event sits in, counting from the left.
        public var column: Int
        /// How many columns its group of overlapping events needs.
        public var columnCount: Int
    }

    /// Returns one slot per input interval, in input order.
    public static func arrange(_ intervals: [(start: Double, end: Double)]) -> [Slot] {
        var slots = [Slot](repeating: Slot(column: 0, columnCount: 1), count: intervals.count)
        let order = intervals.indices.sorted {
            (intervals[$0].start, intervals[$0].end) < (intervals[$1].start, intervals[$1].end)
        }

        var cluster: [Int] = []
        var clusterEnd = -Double.infinity
        var columnEnds: [Double] = []

        func closeCluster() {
            for index in cluster {
                slots[index].columnCount = max(columnEnds.count, 1)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for index in order {
            let interval = intervals[index]
            if !cluster.isEmpty, interval.start >= clusterEnd {
                closeCluster()
                clusterEnd = -Double.infinity
            }
            let column = columnEnds.firstIndex { $0 <= interval.start } ?? columnEnds.count
            if column == columnEnds.count {
                columnEnds.append(interval.end)
            } else {
                columnEnds[column] = interval.end
            }
            slots[index].column = column
            cluster.append(index)
            clusterEnd = max(clusterEnd, interval.end)
        }
        closeCluster()
        return slots
    }
}
