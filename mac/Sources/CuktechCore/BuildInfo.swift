import Foundation

/// 版本信息。**macOS 版从 0.1.0 起自己编号**，不再跟 Windows 版的 0.4.x 绑在一起：
/// 两个平台的改动节奏不一样（Windows 大改 UI 时 mac 可能只跟着修 bug），
/// 硬绑同一个号会让 changelog 变成两边互不相干的内容混在一条。
/// 产物文件名用 -win / -mac 区分平台，所以重号也不会混。
public enum BuildInfo {
    public static let version = "0.1.1"
    public static let channel = "mac"
}
