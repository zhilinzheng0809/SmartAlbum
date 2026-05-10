import SwiftUI
import Photos

// MARK: - 搜索页

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    let photoService: PhotoLibraryService

    init(photoStore: PhotoStore, photoService: PhotoLibraryService) {
        self.photoService = photoService
        _viewModel = StateObject(wrappedValue: SearchViewModel(photoStore: photoStore))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar.padding()
                contentArea
            }
            .navigationTitle("搜索")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("搜索标签、描述、分类...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .onSubmit { Task { await viewModel.search() } }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isSearching {
            Spacer(); ProgressView(); Spacer()
        } else if viewModel.searchText.isEmpty {
            Spacer()
            ContentUnavailableView("搜索照片", systemImage: "magnifyingglass",
                description: Text("输入关键词搜索已分析的照片"))
            Spacer()
        } else if viewModel.searchResults.isEmpty {
            Spacer()
            ContentUnavailableView("无结果", systemImage: "magnifyingglass",
                description: Text("未找到匹配「\(viewModel.searchText)」的照片"))
            Spacer()
        } else {
            List {
                ForEach(viewModel.searchResults) { record in
                    SearchResultRow(record: record, photoService: photoService)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - 搜索结果行

private struct SearchResultRow: View {
    let record: PhotoRecord
    let photoService: PhotoLibraryService
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60).cornerRadius(8)
                } else {
                    Rectangle().fill(Color(.systemGray5))
                        .frame(width: 60, height: 60).cornerRadius(8)
                        .overlay(ProgressView().scaleEffect(0.6))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let category = record.category {
                    Label(category.rawValue, systemImage: category.icon)
                        .font(.caption).foregroundColor(category.color)
                }
                if let desc = record.imageDescription, !desc.isEmpty {
                    Text(desc).font(.subheadline).lineLimit(2)
                }
                if !record.tags.isEmpty {
                    Text(record.tags.prefix(4).joined(separator: " · "))
                        .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            guard let asset = fetchAsset() else { return }
            thumbnail = await photoService.requestThumbnail(
                for: asset, targetSize: CGSize(width: 120, height: 120))
        }
    }

    private func fetchAsset() -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [record.assetIdentifier], options: nil).firstObject
    }
}
