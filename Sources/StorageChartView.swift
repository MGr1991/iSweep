import SwiftUI
import Charts

struct ChartItem: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let isOther: Bool
}

struct StorageChartView: View {
    let items: [StorageItem]
    
    var chartItems: [ChartItem] {
        let sorted = items.sorted { $0.size > $1.size }
        let totalSize = sorted.reduce(0) { $0 + $1.size }
        
        let top = Array(sorted.prefix(8))
        var result = top.map { ChartItem(name: $0.name, size: $0.size, isOther: false) }
        
        let topSize = top.reduce(0) { $0 + $1.size }
        let remainingSize = totalSize - topSize
        
        if remainingSize > 0 && sorted.count > 8 {
            result.append(ChartItem(name: "Andere", size: remainingSize, isOther: true))
        }
        
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speicherverteilung (Top Elemente)")
                .font(.headline)
                .padding(.horizontal)
            
            Chart(chartItems) { item in
                BarMark(
                    x: .value("Größe", item.size),
                    y: .value("Name", item.name)
                )
                .foregroundStyle(by: .value("Kategorie", item.isOther ? "Andere" : "Dateien/Ordner"))
                .annotation(position: .trailing) {
                    Text(formatBytes(item.size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .chartForegroundStyleScale([
                "Dateien/Ordner": .blue,
                "Andere": .gray
            ])
            .chartLegend(.hidden)
            .frame(height: max(200, CGFloat(chartItems.count * 35)))
            .padding()
        }
        .padding(.vertical)
    }
    
    private func formatBytes(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
