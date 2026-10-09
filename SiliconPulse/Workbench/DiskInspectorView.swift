import SwiftUI
import Charts
import AppKit

struct DiskInspectorView: View {
    @Environment(DiskScanModel.self) private var scan
    private let palette: [Color] = [.blue, .teal, .purple, .orange, .pink, .green, .indigo]
    var body: some View {
        @Bindable var settings = scan
        VStack(spacing: 0) {
            HStack {
                Button("Choose folder…") { scan.chooseFolder() }.disabled(scan.isScanning)
                if let root = scan.root { Text(root.path).font(.caption).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                Spacer()
                Menu("History") { ForEach(scan.history) { entry in Button("\(URL(fileURLWithPath: entry.root).lastPathComponent) · \(entry.date.formatted())") { scan.restore(entry) } } }.fixedSize()
                if scan.isScanning { ProgressView().controlSize(.small); Button("Cancel") { scan.cancel() } }
                else { Button("Scan") { if let root = scan.root { scan.start(root) } else { scan.chooseFolder() } }.buttonStyle(.borderedProminent) }
            }.padding(14)
            Divider()
            if scan.root == nil { ContentUnavailableView("Choose a folder to analyze", systemImage: "chart.pie", description: Text("The scan stays on your Mac and never follows symbolic links.")) }
            else {
                HSplitView {
                    VStack(spacing: 12) {
                        HStack {
                            Button { scan.up() } label: { Image(systemName: "arrow.up") }.disabled(scan.focus == 0 || scan.isScanning)
                            Picker("Group", selection: $settings.group) { Text("File size").tag("File size"); Text("File type").tag("File type") }.labelsHidden().frame(width: 140)
                            Picker("View", selection: $settings.layout) { Text("Treemap").tag("Treemap"); Text("Balls").tag("Balls") }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                            Spacer()
                        }
                        GeometryReader { geometry in
                            let nodes = chartNodes
                            if nodes.isEmpty { ContentUnavailableView(scan.isScanning ? "Scanning…" : "No readable files", systemImage: "folder") }
                            else if scan.layout == "Balls" {
                                Canvas { context, size in
                                    for (index, node) in nodes.prefix(64).enumerated() {
                                        let columns = 8, cell = size.width / Double(columns)
                                        let maxBytes = Double(nodes.first?.bytes ?? 1)
                                        let radius = max(3, min(cell, size.height / 8) * 0.46 * sqrt(Double(node.bytes) / max(1, maxBytes)))
                                        let center = CGPoint(x: (Double(index % columns) + 0.5) * cell, y: (Double(index / columns) + 0.5) * size.height / 8)
                                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                                        context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [palette[index % palette.count].opacity(0.55), palette[index % palette.count]]), center: CGPoint(x: center.x - radius / 3, y: center.y - radius / 3), startRadius: 0, endRadius: radius * 1.7))
                                    }
                                }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
                                    let column = min(7, max(0, Int(event.location.x / (geometry.size.width / 8))))
                                    let row = min(7, max(0, Int(event.location.y / (geometry.size.height / 8))))
                                    let index = row * 8 + column
                                    if nodes.indices.contains(index), scan.group == "File size" { scan.selected = nodes[index].id }
                                })
                                .accessibilityLabel("File sizes shown as circles")
                            } else {
                                ZStack(alignment: .topLeading) {
                                    ForEach(tiles(nodes, in: CGRect(origin: .zero, size: geometry.size))) { tile in
                                        RoundedRectangle(cornerRadius: 4).fill(palette[tile.index % palette.count].opacity(scan.selected == tile.node.id ? 1 : 0.72))
                                            .overlay(alignment: .topLeading) {
                                                if tile.rect.width > 60 && tile.rect.height > 30 {
                                                    VStack(alignment: .leading, spacing: 3) { Text(tile.node.name).font(.caption.weight(.semibold)).lineLimit(1); Text(DisplayValue.bytes(tile.node.bytes)).font(.caption2) }.foregroundStyle(.white).padding(7)
                                                }
                                            }.frame(width: max(0, tile.rect.width - 2), height: max(0, tile.rect.height - 2)).clipped()
                                            .position(x: tile.rect.midX, y: tile.rect.midY)
                                            .onTapGesture(count: 2) { if scan.group == "File size" { scan.drill(tile.node) } }
                                            .onTapGesture { if scan.group == "File size" { scan.selected = tile.node.id } }
                                            .help("\(tile.node.name): \(DisplayValue.bytes(tile.node.bytes))")
                                    }
                                }
                            }
                        }.frame(minHeight: 220)
                        Text("Double-click a folder to explore it. Sizes show allocated storage.").font(.caption).foregroundStyle(.secondary)
                        TextField("Search files", text: $settings.query).textFieldStyle(.roundedBorder).onChange(of: scan.query) { _, _ in scan.search() }
                        Table(scan.query.isEmpty ? scan.largest : scan.nodes, selection: $settings.selected) {
                            TableColumn("Largest files", value: \.name)
                            TableColumn("Size") { Text(DisplayValue.bytes($0.bytes)).monospacedDigit() }.width(100)
                            TableColumn("Modified") { Text($0.modified?.formatted(date: .abbreviated, time: .omitted) ?? "n/a") }.width(110)
                        }.frame(height: 180)
                    }.padding(16).frame(minWidth: 420)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(scan.root?.lastPathComponent ?? "Disk Space").font(.headline)
                            if let total = scan.volumeTotal, let free = scan.volumeFree, total > 0 { ProgressView(value: Double(total - min(total, free)), total: Double(total)); InspectorValues(entries: [("Total", DisplayValue.bytes(total)), ("Available", DisplayValue.bytes(free)), ("Scanned", DisplayValue.bytes(scan.scannedBytes))]) }
                            Divider()
                            Text("File Type").font(.headline)
                            ForEach(scan.fileTypes.keys.sorted(), id: \.self) { key in HStack { Text(LocalizedStringKey(key)); Spacer(); Text(DisplayValue.bytes(scan.fileTypes[key])).monospacedDigit() }.font(.caption) }
                            Divider(); Text("Largest Folders").font(.headline)
                            ForEach(scan.nodes.filter(\.directory).prefix(10)) { node in Button { scan.drill(node) } label: { HStack { Text(node.name).lineLimit(1); Spacer(); Text(DisplayValue.bytes(node.bytes)).monospacedDigit() } }.buttonStyle(.plain).font(.caption) }
                            if let node = scan.selectedNode() {
                                Divider(); Text(node.name).font(.headline)
                                InspectorValues(entries: [("Allocated", DisplayValue.bytes(node.bytes)), ("Logical size", DisplayValue.bytes(node.logical)), ("Files", String(node.files))])
                                if let url = scan.path(node.id) { Text(url.path).font(.caption).textSelection(.enabled); Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                            }
                        }.padding(16)
                    }.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                }
            }
            HStack { Text(scan.message).font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(scan.files)") + Text(" ") + Text("Files"); if scan.skipped > 0 { Text("\(scan.skipped)") + Text(" ") + Text("Skipped") } }.font(.caption).padding(12)
        }
    }
    private var chartNodes: [ScannedNode] {
        if scan.group == "File type" { return scan.fileTypes.enumerated().map { i, entry in ScannedNode(id: UInt32.max - UInt32(i), parent: 0, name: entry.key, bytes: entry.value, logical: entry.value, directory: false, files: 0, modified: nil) }.sorted { $0.bytes > $1.bytes } }
        let nodes = scan.nodes.filter { $0.bytes > 0 }, limit = scan.layout == "Balls" ? 63 : 99
        var visible = Array(nodes.prefix(limit))
        if nodes.count > limit { let remaining = nodes.dropFirst(limit); visible.append(ScannedNode(id: UInt32.max, parent: 0, name: "Other", bytes: remaining.reduce(0) { $0 + $1.bytes }, logical: remaining.reduce(0) { $0 + $1.logical }, directory: false, files: remaining.reduce(0) { $0 + $1.files }, modified: nil)) }
        return visible
    }
    private struct Tile: Identifiable { let node: ScannedNode, index: Int, rect: CGRect; var id: UInt32 { node.id } }
    private func tiles(_ nodes: [ScannedNode], in rect: CGRect) -> [Tile] {
        var result: [Tile] = []
        func partition(_ start: Int, _ end: Int, _ area: CGRect) {
            guard start < end else { return }
            if end - start == 1 { result.append(Tile(node: nodes[start], index: start, rect: area)); return }
            let total = nodes[start..<end].reduce(0.0) { $0 + Double($1.bytes) }
            var sum = 0.0, middle = start + 1
            for i in start..<(end - 1) { sum += Double(nodes[i].bytes); middle = i + 1; if sum >= total / 2 { break } }
            let ratio = total > 0 ? sum / total : Double(middle - start) / Double(end - start)
            if area.width >= area.height {
                let width = area.width * ratio
                partition(start, middle, CGRect(x: area.minX, y: area.minY, width: width, height: area.height))
                partition(middle, end, CGRect(x: area.minX + width, y: area.minY, width: area.width - width, height: area.height))
            } else {
                let height = area.height * ratio
                partition(start, middle, CGRect(x: area.minX, y: area.minY, width: area.width, height: height))
                partition(middle, end, CGRect(x: area.minX, y: area.minY + height, width: area.width, height: area.height - height))
            }
        }
        partition(0, nodes.count, rect)
        return result
    }
}
