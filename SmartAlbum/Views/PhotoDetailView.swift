import SwiftUI

// MARK: - 照片详情页

struct PhotoDetailView: View {
    let photoAsset: PhotoAsset
    let photoService: PhotoLibraryService
    let aiService: AIService
    let photoStore: PhotoStore

    @State private var fullImage: UIImage?
    @State private var isAnalyzing = false
    @State private var showEditTags = false
    @State private var editingTags: [String] = []
    @State private var currentRecord: PhotoRecord?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                imageSection

                if let record = currentRecord, record.isAnalyzed {
                    analysisResultCard(record)
                } else {
                    analysisPlaceholder
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("照片详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadContent() }
        .sheet(isPresented: $showEditTags) {
            EditTagsView(tags: $editingTags) { saveTags() }
        }
    }

    private var imageSection: some View {
        Group {
            if let image = fullImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(height: 300)
                    .overlay(ProgressView())
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
        }
    }

    private func analysisResultCard(_ record: PhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let category = record.category {
                    Label(category.rawValue, systemImage: category.icon)
                        .font(.headline)
                        .foregroundColor(category.color)
                }
                Spacer()
                if let c = record.confidence {
                    Text("置信度 \(Int(c * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if let desc = record.imageDescription, !desc.isEmpty {
                Text(desc).font(.body)
            }
            if !record.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(record.tags, id: \.self) { tag in
                            Text(tag).font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                }
            }
            Button {
                editingTags = record.tags
                showEditTags = true
            } label: {
                Label("编辑标签", systemImage: "pencil").font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var analysisPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.largeTitle).foregroundColor(.accentColor)
            Text("尚未分析该照片").font(.headline)
            Text("使用 AI 获取智能分类和标签")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            if let error = errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }
            Button {
                analyzePhoto()
            } label: {
                HStack(spacing: 6) {
                    if isAnalyzing { ProgressView().scaleEffect(0.8) }
                    Text(isAnalyzing ? "分析中..." : "开始分析")
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(Color.accentColor).foregroundColor(.white).cornerRadius(20)
            }
            .disabled(isAnalyzing)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func loadContent() async {
        fullImage = await photoService.requestThumbnail(
            for: photoAsset.asset, targetSize: CGSize(width: 800, height: 800))
        currentRecord = photoStore.fetch(by: photoAsset.id)
    }

    private func analyzePhoto() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        errorMessage = nil

        let settings = SettingsViewModel()
        let engine = AnalysisEngine(
            photoService: photoService,
            aiService: aiService,
            photoStore: photoStore
        )

        Task {
            defer { isAnalyzing = false }
            do {
                try await engine.analyzeSingle(
                    photoAsset.asset,
                    apiKey: settings.apiKey,
                    endpoint: settings.endpoint,
                    model: settings.model
                )
                await loadContent()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveTags() {
        guard var record = currentRecord else { return }
        record.tags = editingTags
        photoStore.upsert(record)
        currentRecord = record
    }
}

// MARK: - 编辑标签 Sheet

private struct EditTagsView: View {
    @Binding var tags: [String]
    let onSave: () -> Void
    @State private var newTag = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("当前标签") {
                    if tags.isEmpty { Text("暂无标签").foregroundColor(.secondary) }
                    ForEach(tags.indices, id: \.self) { i in Text(tags[i]) }
                    .onDelete { tags.remove(atOffsets: $0) }
                }
                Section("添加标签") {
                    HStack {
                        TextField("输入新标签", text: $newTag).submitLabel(.done).onSubmit { addTag() }
                        Button("添加") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { onSave(); dismiss() } }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(t) else { return }
        tags.append(t)
        newTag = ""
    }
}
