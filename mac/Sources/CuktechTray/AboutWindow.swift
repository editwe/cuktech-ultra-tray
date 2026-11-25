#if os(macOS)
import AppKit
import SwiftUI
import CuktechCore

// MARK: - 更新检查

/// 从 GitHub Releases 里找**最新一个带 mac 资产的版本**。
///
/// 为什么不看 `tag_name`：这个仓库的 tag 跟的是 Windows 版的号（v0.4.6），
/// 而 mac 版自己编号（0.1.0），两者并行发布 —— 直接比 tag 会把每次启动都判成「有新版本」。
/// 真正的 mac 版本号只出现在资产名里：`CuktechTray-0.1.0-mac.zip`。
enum UpdateChecker {
    struct Release {
        var version: String      // 从资产名里抠出来的 mac 版本号
        var pageURL: URL?        // release 页面
        var assetURL: URL?       // 直接下 zip 的地址
        var publishedAt: String?
    }

    private static let releasesAPI = URL(string: "https://api.github.com/repos/Blank2007/cuktech-ultra-tray/releases?per_page=20")!

    /// 用自定义枚举而不是 `Result<_, String>`：Result 的失败类型必须实现 Error。
    enum Outcome {
        case found(Release)
        case failed(String)
    }

    static func latestMacRelease() async -> Outcome {
        var req = URLRequest(url: releasesAPI)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("CuktechTray-mac/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            return .failed("连不上 GitHub（\(error.localizedDescription)）")
        }
        guard let http = resp as? HTTPURLResponse else { return .failed("GitHub 返回了看不懂的东西") }
        if http.statusCode == 403 {
            // 未登录的 API 每小时 60 次，按 IP 算；把恢复时间直接告诉用户，别让人干等
            if let raw = http.value(forHTTPHeaderField: "x-ratelimit-reset"),
               let epoch = Double(raw), epoch > 0 {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                let at = f.string(from: Date(timeIntervalSince1970: epoch))
                return .failed("GitHub 限流了（未登录每小时 60 次），\(at) 之后能再查")
            }
            return .failed("GitHub 限流了（每小时 60 次），过一会儿再试")
        }
        guard http.statusCode == 200 else { return .failed("GitHub 返回 \(http.statusCode)") }
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return .failed("解析 release 列表失败")
        }

        for rel in list {
            if (rel["draft"] as? Bool) == true { continue }
            guard let assets = rel["assets"] as? [[String: Any]] else { continue }
            for a in assets {
                guard let name = a["name"] as? String,
                      let ver = macVersion(inAssetName: name) else { continue }
                return .found(Release(
                    version: ver,
                    pageURL: (rel["html_url"] as? String).flatMap(URL.init(string:)),
                    assetURL: (a["browser_download_url"] as? String).flatMap(URL.init(string:)),
                    publishedAt: rel["published_at"] as? String
                ))
            }
        }
        return .failed("还没有发过 mac 版")
    }

    /// `CuktechTray-0.1.0-mac.zip` → `0.1.0`
    static func macVersion(inAssetName name: String) -> String? {
        guard name.hasSuffix("-mac.zip") else { return nil }
        let prefix = "CuktechTray-"
        guard let r = name.range(of: prefix), r.lowerBound == name.startIndex else { return nil }
        let rest = name[name.index(name.startIndex, offsetBy: prefix.count)...]
        let ver = rest.replacingOccurrences(of: "-mac.zip", with: "")
        return ver.first?.isNumber == true ? ver : nil
    }

    /// `remote` 是否比 `local` 新。
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let a = parts(remote), b = parts(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

// MARK: - 数据源

final class AboutModel: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate(String)
        case newer(UpdateChecker.Release)
        case failed(String)
    }

    @Published var state: State = .idle

    /// 打开窗口时自动查一次；点按钮也会走这里。
    func check() {
        if case .checking = state { return }
        state = .checking
        Task {
            let result = await UpdateChecker.latestMacRelease()
            await MainActor.run {
                switch result {
                case .found(let rel):
                    if UpdateChecker.isNewer(rel.version, than: BuildInfo.version) {
                        self.state = .newer(rel)
                    } else {
                        // 相等 → 已是最新；本地更大 → 自己编的开发版
                        self.state = .upToDate(rel.version)
                    }
                case .failed(let msg):
                    self.state = .failed(msg)
                }
            }
        }
    }
}

// MARK: - 界面

struct AboutView: View {
    @ObservedObject var model: AboutModel
    var onClose: () -> Void

    private var version: String { BuildInfo.version }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("酷态科功率表")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.fg)
                    Text("mac 版 \(version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.dim)
                    Text("菜单栏里看四路功率，不用开米家")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dim)
                }
                Spacer(minLength: 0)
            }

            Divider().opacity(0.25).padding(.vertical, 12)

            Text("数据全程走蓝牙，只有扫码配对时连一次小米云。不是小米或酷态科官方出的。")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.25).padding(.vertical, 12)

            statusRow

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                pill("GitHub 仓库", prominent: false) {
                    if let u = URL(string: "https://github.com/Blank2007/cuktech-ultra-tray") {
                        NSWorkspace.shared.open(u)
                    }
                }
                pill(checkingTitle, prominent: false) { model.check() }
                    .disabled(isChecking)
                Spacer()
                pill("好", prominent: true) { onClose() }
            }
        }
        .padding(18)
        .frame(width: 380, height: 286)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var isChecking: Bool {
        if case .checking = model.state { return true }
        return false
    }

    private var checkingTitle: String {
        isChecking ? "检查中…" : "检查更新"
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.state {
        case .idle:
            Text("版本 \(version)")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.dim)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在问 GitHub…")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.dim)
            }
        case .upToDate(let remote):
            if remote == version {
                label("已是最新（\(remote)）", color: Theme.ok)
            } else {
                label("线上最新 mac 版是 \(remote)，你这份 \(version) 是开发版", color: Theme.ok)
            }
        case .newer(let rel):
            HStack(spacing: 8) {
                label("有新版本 \(rel.version)", color: Theme.ok)
                pill("下载", prominent: true) {
                    if let u = rel.assetURL ?? rel.pageURL { NSWorkspace.shared.open(u) }
                }
                if rel.assetURL != nil, let page = rel.pageURL {
                    pill("看说明", prominent: false) { NSWorkspace.shared.open(page) }
                }
                Spacer()
            }
        case .failed(let msg):
            label(msg, color: Theme.bad)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundColor(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, prominent: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .foregroundColor(prominent ? Theme.fg : Theme.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(prominent ? Theme.cardOn : Theme.card)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 窗口

final class AboutController: NSObject, NSWindowDelegate {
    static let shared = AboutController()

    private var window: NSWindow?
    private let model = AboutModel()

    func show() {
        let win = window ?? makeWindow()
        window = win
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.check()
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 286),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered,
                           defer: false)
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.collectionBehavior = [.moveToActiveSpace]
        win.delegate = self
        win.contentView = NSHostingView(rootView: AboutView(model: model) { [weak win] in
            win?.orderOut(nil)
        })
        return win
    }
}
#endif
