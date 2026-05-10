import SwiftUI

// MARK: - 分析进度页

struct AnalysisProgressView: View {
    @StateObject private var engine: AnalysisEngine
    @State private var isRunning = false
    @State private var didComplete = false
    @Environment(\.dismiss) private var dismiss

    init(photoService: PhotoLibraryService, aiService: AIService, photoStore: PhotoStore) {
        _engine = StateObject(wrappedValue: AnalysisEngine(
            photoService: photoService, aiService: aiService, photoStore: photoStore))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if !isRunning && engine.analyzedCount == 0 { idleView }
                else { progressView }
                Spacer()
                bottomActions
            }
            .frame(maxWidth: .infinity)
            .padding()
            .navigationTitle("智能分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !engine.isAnalyzing {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                }
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60)).foregroundColor(.accentColor)
            Text("开始智能分析").font(.title2).fontWeight(.semibold)
            Text("使用 AI 对相册中的照片进行自动分类和标签识别\n分析结果会自动保存，无需重复分析")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 8).frame(width: 140, height: 140)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: engine.analyzedCount)
                VStack(spacing: 2) {
                    Text("\(engine.analyzedCount)").font(.title).fontWeight(.bold)
                    Text("/ \(engine.totalCount)").font(.caption).foregroundColor(.secondary)
                }
            }
            if engine.isAnalyzing {
                ProgressView().padding(.top, 4)
                Text("正在分析...").font(.subheadline).foregroundColor(.secondary)
            } else if didComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("分析完成").font(.headline).foregroundColor(.green)
                }
            }
            if let error = engine.currentError {
                Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            }
        }
    }

    private var progressFraction: CGFloat {
        guard engine.totalCount > 0 else { return 0 }
        return CGFloat(engine.analyzedCount) / CGFloat(engine.totalCount)
    }

    @ViewBuilder
    private var bottomActions: some View {
        if !isRunning {
            Button { startAnalysis() } label: {
                Text("开始分析").font(.headline).frame(maxWidth: .infinity)
                    .padding(.vertical, 14).background(Color.accentColor).foregroundColor(.white).cornerRadius(16)
            }
        } else if !engine.isAnalyzing && didComplete {
            Button { dismiss() } label: {
                Text("完成").font(.headline).frame(maxWidth: .infinity)
                    .padding(.vertical, 14).background(Color.accentColor).foregroundColor(.white).cornerRadius(16)
            }
        }
    }

    private func startAnalysis() {
        let settings = SettingsViewModel()
        guard settings.isConfigured else {
            engine.currentError = "请先在「设置」中配置 API Key"
            return
        }
        isRunning = true
        didComplete = false
        Task {
            await engine.analyzeNewPhotos(
                apiKey: settings.apiKey,
                endpoint: settings.endpoint,
                model: settings.model
            )
            didComplete = true
        }
    }
}
