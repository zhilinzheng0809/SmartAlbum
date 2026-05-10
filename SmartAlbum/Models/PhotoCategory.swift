import Foundation
import SwiftUI

/// 照片分类枚举，定义AI可识别的图片类别
enum PhotoCategory: String, CaseIterable, Codable {
    case people      = "人物"
    case landscape   = "风景"
    case food        = "食物"
    case animal      = "动物"
    case document    = "文档截图"
    case art         = "艺术设计"
    case architecture = "建筑"
    case plant       = "植物"
    case vehicle     = "交通工具"
    case other       = "其他"

    /// SF Symbol 图标名
    var icon: String {
        switch self {
        case .people:       return "person.2.fill"
        case .landscape:    return "mountain.2.fill"
        case .food:         return "fork.knife"
        case .animal:       return "pawprint.fill"
        case .document:     return "doc.text.fill"
        case .art:          return "paintpalette.fill"
        case .architecture: return "building.2.fill"
        case .plant:        return "leaf.fill"
        case .vehicle:      return "car.fill"
        case .other:        return "square.grid.2x2.fill"
        }
    }

    /// 分类主题色
    var color: Color {
        switch self {
        case .people:       return .blue
        case .landscape:    return .green
        case .food:         return .orange
        case .animal:       return .brown
        case .document:     return .gray
        case .art:          return .purple
        case .architecture: return .indigo
        case .plant:        return .mint
        case .vehicle:      return .red
        case .other:        return .secondary
        }
    }
}
