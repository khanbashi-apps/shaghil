import Foundation
import UIKit
import Network

// MARK: - Icon rendering

enum IconRenderer {
    static func customIconURL(_ id: String) -> URL {
        ProjectStore.shared.dir(id).appendingPathComponent("icon.png")
    }

    static func customIcon(_ id: String) -> UIImage? {
        guard let d = try? Data(contentsOf: customIconURL(id)) else { return nil }
        return UIImage(data: d)
    }

    static func render(_ p: Project, size: CGFloat) -> UIImage {
        render(emoji: p.iconEmoji, hex: p.iconColorHex, image: customIcon(p.id), size: size)
    }

    static func render(emoji: String, hex: String, image: UIImage?, size: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            if let img = image {
                let s = max(size / img.size.width, size / img.size.height)
                let w = img.size.width * s, h = img.size.height * s
                img.draw(in: CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
                return
            }
            let base = UIColor(hexString: hex)
            let top = base.adjusted(by: 0.18)
            let cs = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: cs, colors: [top.cgColor, base.cgColor] as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size * 0.3, y: size), options: [])
            } else {
                base.setFill(); ctx.fill(rect)
            }
            let font = UIFont.systemFont(ofSize: size * 0.56)
            let str = NSAttributedString(string: emoji, attributes: [.font: font])
            let b = str.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil)
            str.draw(at: CGPoint(x: (size - b.width) / 2, y: (size - b.height) / 2))
        }
    }
}

extension UIColor {
    convenience init(hexString: String) {
        var s = hexString.replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(rgb: UInt32(truncatingIfNeeded: v))
    }

    func adjusted(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(r + amount, 1), green: min(g + amount, 1), blue: min(b + amount, 1), alpha: a)
    }
}

// MARK: - Home-screen Web Clip profile

enum WebClipBuilder {
    static func profile(for p: Project, label: String) -> Data? {
        let icon = IconRenderer.render(p, size: 180).pngData() ?? Data()
        let clip: [String: Any] = [
            "FullScreen": true,
            "Icon": icon,
            "IsRemovable": true,
            "Label": label,
            "Precomposed": true,
            "URL": SharedStore.runURL(p.id).absoluteString,
            "PayloadDescription": "أيقونة لتشغيل مشروع «\(label)» من تطبيق شغّل",
            "PayloadDisplayName": label,
            "PayloadIdentifier": "om.khanbashi.shaghil.webclip.\(p.id)",
            "PayloadType": "com.apple.webClip.managed",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1
        ]
        let root: [String: Any] = [
            "PayloadContent": [clip],
            "PayloadDescription": "يضيف أيقونة «\(label)» إلى الشاشة الرئيسية. تفتح المشروع بملء الشاشة داخل تطبيق شغّل، بدون إنترنت.",
            "PayloadDisplayName": "\(label) — شغّل",
            "PayloadIdentifier": "om.khanbashi.shaghil.profile.\(p.id)",
            "PayloadOrganization": "شغّل",
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1
        ]
        return try? PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    static func profileFile(for p: Project, label: String) -> URL? {
        guard let data = profile(for: p, label: label) else { return nil }
        let safe = label.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).mobileconfig")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

/// Tiny local HTTP server so Safari can download the profile (Safari is the app that installs profiles).
final class ProfileServer {
    static let shared = ProfileServer()
    private var listener: NWListener?
    private var payload = Data()
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var stopWork: DispatchWorkItem?

    func serve(_ data: Data, completion: @escaping (URL?) -> Void) {
        stop()
        payload = data
        guard let l = try? NWListener(using: .tcp, on: .any) else { completion(nil); return }
        var done = false
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.stateUpdateHandler = { state in
            guard !done else { return }
            switch state {
            case .ready:
                done = true
                if let port = l.port?.rawValue {
                    completion(URL(string: "http://127.0.0.1:\(port)/install.mobileconfig"))
                } else { completion(nil) }
            case .failed, .cancelled:
                done = true
                completion(nil)
            default: break
            }
        }
        l.start(queue: .main)
        listener = l
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "profile-server") { [weak self] in self?.stop() }
        let w = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: w)
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: .main)
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, _, _ in
            guard let self else { c.cancel(); return }
            var head = "HTTP/1.1 200 OK\r\n"
            head += "Content-Type: application/x-apple-aspen-config\r\n"
            head += "Content-Disposition: attachment; filename=\"install.mobileconfig\"\r\n"
            head += "Content-Length: \(self.payload.count)\r\n"
            head += "Connection: close\r\n\r\n"
            var out = Data(head.utf8)
            out.append(self.payload)
            c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    func stop() {
        stopWork?.cancel()
        listener?.cancel()
        listener = nil
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}

// MARK: - Offline PWA packager

enum PWAPackager {
    static func package(_ p: Project) -> URL? {
        let store = ProjectStore.shared
        var files: [String: Data] = [:]
        for f in p.files {
            files[f] = store.read(f, in: p.id).data(using: .utf8)
        }
        var index: String
        if let html = p.files.contains("index.html") ? store.read("index.html", in: p.id) : nil {
            index = html
        } else {
            index = Runner.wrapper(for: p)
        }
        index = inject(into: index, name: p.name)
        files["index.html"] = index.data(using: .utf8)

        for (n, s) in [("icon-192.png", 192), ("icon-512.png", 512), ("apple-touch-icon.png", 180)] {
            files[n] = IconRenderer.render(p, size: CGFloat(s)).pngData()
        }

        let manifest: [String: Any] = [
            "name": p.name,
            "short_name": String(p.name.prefix(12)),
            "start_url": "./index.html",
            "scope": "./",
            "display": "standalone",
            "background_color": "#ffffff",
            "theme_color": p.iconColorHex,
            "dir": "auto",
            "icons": [
                ["src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable"],
                ["src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"]
            ]
        ]
        files["manifest.json"] = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])

        let assets = (["./"] + files.keys.sorted() + ["sw.js"]).map { "\"\($0 == "./" ? $0 : "./" + $0)\"" }.joined(separator: ",\n  ")
        let version = Int(Date().timeIntervalSince1970)
        let sw = """
        // Generated by شغّل \(AppInfo.version) — offline cache-first service worker
        const CACHE = 'shaghil-\(p.id.prefix(8))-\(version)';
        const ASSETS = [
          \(assets)
        ];
        self.addEventListener('install', e => {
          e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
        });
        self.addEventListener('activate', e => {
          e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
        });
        self.addEventListener('fetch', e => {
          if (e.request.method !== 'GET') return;
          e.respondWith(caches.match(e.request, { ignoreSearch: true }).then(r => r || fetch(e.request).then(res => {
            const copy = res.clone();
            caches.open(CACHE).then(c => c.put(e.request, copy));
            return res;
          }).catch(() => caches.match('./index.html'))));
        });
        """
        files["sw.js"] = sw.data(using: .utf8)
        files["README.txt"] = """
        \(p.name) — حزمة تطبيق ويب تعمل بدون إنترنت (PWA)
        أُنشئت بتطبيق شغّل \(AppInfo.version)

        للنشر على GitHub Pages: ارفع محتويات هذا المجلد إلى مستودع، ثم فعّل Pages من الإعدادات.
        بعد فتح الرابط في Safari: مشاركة ← إضافة إلى الشاشة الرئيسية.
        """.data(using: .utf8)

        let safe = p.name.replacingOccurrences(of: #"[\\/:*?"<>| ]"#, with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)-PWA.zip")
        let zip = ZipWriter()
        let folder = safe + "/"
        for k in files.keys.sorted() {
            if let d = files[k] { zip.add(path: folder + k, data: d) }
        }
        do {
            try zip.finish().write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    private static func inject(into html: String, name: String) -> String {
        var s = html
        let head = """
        <link rel="manifest" href="manifest.json">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-title" content="\(name)">
        <meta name="apple-mobile-web-app-status-bar-style" content="default">
        <link rel="apple-touch-icon" href="apple-touch-icon.png">
        """
        let reg = """
        <script>if('serviceWorker' in navigator){window.addEventListener('load',function(){navigator.serviceWorker.register('sw.js').catch(function(e){console.warn('SW',e)})})}</script>
        """
        // widget bridge stub so code that calls shaghil.widget() does not break outside the app
        let stub = "<script>window.shaghil=window.shaghil||{state:null,widget:function(){}};</script>"
        if let r = s.range(of: "</head>", options: .caseInsensitive) {
            s.insert(contentsOf: head + "\n" + stub + "\n", at: r.lowerBound)
        } else {
            s = head + stub + s
        }
        if let r = s.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            s.insert(contentsOf: reg + "\n", at: r.lowerBound)
        } else {
            s += reg
        }
        return s
    }
}

// MARK: - Minimal ZIP writer (stored, no compression)

final class ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private func le16(_ v: UInt16, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    private func le32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

    private var dosTime: (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let t = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let d = UInt16(((c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (t, d)
    }

    func add(path: String, data file: Data) {
        let name = Data(path.utf8)
        let crc = Self.crc32(file)
        let size = UInt32(file.count)
        let offset = UInt32(data.count)
        let (t, d) = dosTime
        // local header
        le32(0x04034b50, &data); le16(20, &data); le16(0x0800, &data); le16(0, &data)
        le16(t, &data); le16(d, &data); le32(crc, &data); le32(size, &data); le32(size, &data)
        le16(UInt16(name.count), &data); le16(0, &data)
        data.append(name); data.append(file)
        // central directory
        le32(0x02014b50, &central); le16(20, &central); le16(20, &central); le16(0x0800, &central); le16(0, &central)
        le16(t, &central); le16(d, &central); le32(crc, &central); le32(size, &central); le32(size, &central)
        le16(UInt16(name.count), &central); le16(0, &central); le16(0, &central); le16(0, &central); le16(0, &central)
        le32(0, &central); le32(offset, &central)
        central.append(name)
        count += 1
    }

    func finish() -> Data {
        var out = data
        let cdOffset = UInt32(out.count)
        out.append(central)
        le32(0x06054b50, &out); le16(0, &out); le16(0, &out); le16(count, &out); le16(count, &out)
        le32(UInt32(central.count), &out); le32(cdOffset, &out); le16(0, &out)
        return out
    }
}
