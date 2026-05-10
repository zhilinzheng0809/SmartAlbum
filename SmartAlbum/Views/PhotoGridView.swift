import SwiftUI

// MARK: - 照片网格主页

struct PhotoGridView: View {
    @StateObject private var viewModel: PhotoGridViewModel
    @State private var showAnalysisProgress = false
    @State private var searchText = ""

    let photoService: PhotoLibraryService
    let aiService: AIService
    let photoStore: PhotoStore

    init(photoService: PhotoLibraryService, aiService: AIService, photoStore: PhotoStore) {
        self.photoService = photoService
        self.aiService = aiService
        self.photoStore = photoStore
        _viewModel = StateObject(wrappedValue: PhotoGridViewModel(
            photoService: photoService,
            photoStore: photoStore
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                categoryFilterBar
                contentArea
            }
            .navigationTitle("智能相册")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAnalysisProgress = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                }
            }
            .sheet(isPresented: $showAnalysisProgress) {
                AnalysisProgressView(
                    photoService: photoService,
                    aiService: aiService,
                    photoStore: photoStore
                )
            }
            .task {
                await viewModel.loadPhotos()
            }
            .onChange(of: viewModel.selectedCategory) {
                Task { await viewModel.loadPhotos(searchText: searchText) }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索标签、描述...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await viewModel.loadPhotos(searchText: searchText) }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await viewModel.loadPhotos() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "全部", icon: "square.grid.2x2",
                    isSelected: viewModel.selectedCategory == nil
                ) { viewModel.selectedCategory = nil }

                ForEach(PhotoCategory.allCases, id: \.self) { category in
                    CategoryChip(title: category.rawValue, icon: category.icon,
                        isSelected: viewModel.selectedCategory == category
                    ) { viewModel.selectedCategory = category }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView("加载中...")
            Spacer()
        } else if viewModel.assets.isEmpty {
            Spacer()
            ContentUnavailableView(
                "没有照片",
                systemImage: "photo.on.rectangle.angled",
                description: Text(searchText.isEmpty ? "请授权访问相册" : "未找到匹配的照片")
            )
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                    ForEach(viewModel.assets) { photoAsset in
                        NavigationLink {
                            PhotoDetailView(
                                photoAsset: photoAsset,
                                photoService: photoService,
                                aiService: aiService,
                                photoStore: photoStore
                            )
                        } label: {
                            PhotoCell(photoAsset: photoAsset)
                        }
                    }
                }
                .padding(2)
            }
            .refreshable {
                await viewModel.loadPhotos(searchText: searchText)
            }
        }
    }
}

// MARK: - 子组件

private struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

private struct PhotoCell: View {
    let photoAsset: PhotoAsset

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = photoAsset.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: size, height: size)
                        .overlay(ProgressView())
                }
                if let category = photoAsset.record?.category {
                    Image(systemName: category.icon)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(category.color.opacity(0.85))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
