import PhotosUI
import SwiftData
import SwiftUI

struct ChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]

    @State private var input = ""
    @State private var photo: Data?
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty { emptyHint }
                        ForEach(messages) { MessageRow(message: $0) }
                        if sending {
                            HStack { ProgressView(); Text("豆包识别中…").foregroundStyle(.secondary); Spacer() }
                                .id("sending")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: sending) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                ChatInputBar(input: $input, photo: $photo, focused: $focused, sending: sending, onSend: send)
            }
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("直接说、按住说或拍，不用填表").font(.headline)
            Group {
                Text("· 中午吃了一碗牛肉面加一个卤蛋")
                Text("· 晚上 7 点跑步 40 分钟，5 公里")
                Text("· 📷 拍一张餐盘照片直接发送")
                Text("· 刚才那碗面改成 500 千卡")
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func send(_ text: String) {
        let image = photo
        photo = nil
        sending = true
        Task {
            await RecordAssistant(context: context, settings: settings).handle(text: text, photo: image)
            sending = false
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage
    @Query private var records: [BehaviorRecord]

    init(message: ChatMessage) {
        self.message = message
        let ids = message.recordIDs
        _records = Query(filter: #Predicate<BehaviorRecord> { ids.contains($0.id) }, sort: \.timestamp)
    }

    var body: some View {
        let isUser = message.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let data = message.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxWidth: 200).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isUser ? Theme.oliveSoft : Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if !isUser { RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1) }
                    }
                    .foregroundStyle(message.isError ? Theme.warning : Theme.ink)
                    .textSelection(.enabled)
            }
            ForEach(records) { RecordCard(record: $0) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

/// 一条记录的卡片，长按可删除
struct RecordCard: View {
    @Environment(\.modelContext) private var context
    let record: BehaviorRecord
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let data = record.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: record.kind.symbol).font(.title2)
                    .foregroundStyle(Theme.oliveText)
                    .frame(width: 48, height: 48)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(record.kind.title) · \(record.category)").font(.subheadline.bold())
                    Spacer()
                    Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if let m = record.durationMinutes { Text("\(m) 分钟") }
                    if let c = record.calories { Text(record.kind == .meal ? "\(c) 千卡" : "约消耗 \(c) 千卡") }
                }
                .font(.subheadline).monospacedDigit()
                if !record.detail.isEmpty {
                    Text(record.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        .contextMenu {
            Button("删除记录", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { context.delete(record) }
        }
    }
}

struct RecordListView: View {
    @Query(sort: \BehaviorRecord.timestamp, order: .reverse) private var records: [BehaviorRecord]

    var body: some View {
        let groups = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.timestamp) }
        List {
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                let items = groups[day]!
                let intake = items.filter { $0.kind == .meal }.reduce(0) { $0 + ($1.calories ?? 0) }
                Section {
                    ForEach(items) { RecordCard(record: $0) }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } header: {
                    HStack {
                        Text(day.formatted(date: .complete, time: .omitted))
                        Spacer()
                        Text("摄入 \(intake) 千卡")
                    }
                }
            }
        }
        .listStyle(.plain)
        .themedList()
        .navigationTitle("全部记录")
        .overlay { if records.isEmpty { ContentUnavailableView("还没有记录", systemImage: "tray") } }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage, let data = img.jpegData(compressionQuality: 0.9) {
                parent.onPick(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
