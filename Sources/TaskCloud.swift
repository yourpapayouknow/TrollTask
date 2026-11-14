// 描述归档账户，百度网盘和自定义账户共用WebDAV。
enum TaskCloudKind: String, CaseIterable, Codable {
    case google, one, baidu, dav

    var name: String {
        switch self {
        case .google: return "GoogleDrive"
        case .one: return "OneDrive"
        case .baidu: return "BaiduNetDisk"
        case .dav: return "自定义WebDav"
        }
    }

    var isDAV: Bool { self == .baidu || self == .dav }
}

// 用稳定的服务身份保留旧归档的下载能力。
struct TaskCloudAccount: Codable {
    var id = UUID().uuidString.lowercased()
    let kind: TaskCloudKind
    var name: String
    var endpoint = ""
    var user = ""
    var secret = ""
    var access = ""
    var expires: Double = 0
    var previousEndpoints: [String]? = nil

    // 验证端点的结构，避免把密码附带在URL中。
    func davURL() throws -> URL {
        guard var components = URLComponents(string: endpoint),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw TaskCloudHTTP.err("WebDAV地址无效")
        }
        if !components.percentEncodedPath.hasSuffix("/") { components.percentEncodedPath += "/" }
        guard let url = components.url else { throw TaskCloudHTTP.err("WebDAV地址无效") }
        return url
    }
}

// 一次钥匙串写入保留列表、默认账户和认证资料。
struct TaskCloudConfig: Codable {
    var accounts: [TaskCloudAccount] = []
    private(set) var selected: String?
    private var priority: [String]?

    // 兼容旧版默认账户，并预留百度和OneDrive的顺序。
    var archiveOrder: [String] {
        if let priority { return priority }
        let legacy = accounts.first { $0.id == selected }
        return [legacy?.id].compactMap { $0 } + [TaskCloudKind.baidu, .one]
            .filter { $0 != legacy?.kind }.map { kind in accounts.first { $0.kind == kind }?.id ?? kind.rawValue }
    }

    var archiveAccounts: [TaskCloudAccount] { archiveOrder.compactMap(account(for:)) }

    // 尚未连接的服务保留顺位，连接后参与归档。
    func account(for key: String) -> TaskCloudAccount? {
        accounts.first { $0.id == key || $0.kind.rawValue == key }
    }

    // 加载已有账户。
    static func load() throws -> Self {
        guard let data = try TaskKeychain.rd("archive") else { return Self() }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    // 保存已验证账户并保持历史引用。
    mutating func add(_ account: TaskCloudAccount, replacing prior: TaskCloudAccount? = nil) throws {
        var account = account
        let existing = accounts.firstIndex {
            $0.kind == account.kind && $0.user == account.user && $0.endpoint == account.endpoint
        }
        if let prior, account.kind == .baidu, prior.kind == account.kind, prior.user == account.user,
           account.endpoint != prior.endpoint, try prior.davURL().path == account.davURL().path {
            guard existing == nil,
                  let index = accounts.firstIndex(where: { $0.id == prior.id && $0.endpoint == prior.endpoint && $0.user == prior.user }) else {
                throw TaskCloudHTTP.err("百度连接已变更，请重新打开")
            }
            account.id = prior.id
            let endpoints = (accounts[index].previousEndpoints ?? []) + [prior.endpoint]
            account.previousEndpoints = endpoints.filter { $0 != account.endpoint }
            accounts[index] = account
        } else if let index = existing {
            account.id = accounts[index].id
            account.previousEndpoints = accounts[index].previousEndpoints
            if !account.kind.isDAV && account.secret.isEmpty { account.secret = accounts[index].secret }
            accounts[index] = account
        } else {
            guard account.kind.isDAV || !account.secret.isEmpty else { throw TaskCloudHTTP.err("授权未返回刷新令牌") }
            accounts.append(account)
        }
        try save()
    }

    // 保存用户选择的顺序，包括空列表。
    mutating func setOrder(_ order: [String]) throws {
        priority = order
        selected = archiveAccounts.first?.id
        try save()
    }

    // 原子持久化当前配置。
    func save() throws { try TaskKeychain.sv("archive", JSONEncoder().encode(self)) }
}

// 校验HTTP状态，禁止跨站发送认证头。
final class TaskCloudHTTP: NSObject, URLSessionTaskDelegate {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: TaskCloudHTTP(), delegateQueue: nil)
    }()

    // 保留同源DAV跳转，跨站下载只跟随HTTPS且清除认证头。
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let source = response.url, let target = request.url else { completionHandler(nil); return }
        let method = task.originalRequest?.httpMethod
        func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
        if source.scheme == target.scheme && source.host == target.host && port(source) == port(target) {
            if response.statusCode == 307 || response.statusCode == 308 || method == "GET" {
                completionHandler(request)
            } else { completionHandler(nil) }
            return
        }
        guard method == "GET", target.scheme == "https" else {
            completionHandler(nil)
            return
        }
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
    }

    // 发送请求，调用者决定可接受的服务状态。
    static func send(_ url: URL, _ method: String, auth: String? = nil,
                     type: String? = nil, body: Data? = nil, headers: [String: String] = [:],
                     extra: Set<Int> = []) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw err("服务器响应无效") }
        guard (200..<300).contains(http.statusCode) || extra.contains(http.statusCode) else {
            throw err("云端请求失败（\(http.statusCode)）", http.statusCode)
        }
        return (data, http)
    }

    // 为调用方提供可识别错误，避免显示含认证信息的服务响应。
    static func err(_ message: String, _ code: Int = 1) -> NSError {
        NSError(domain: "com.iwmei.taskforiwmei.archive", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // 构建服务查询，不用手拼用户输入。
    static func query(_ url: URL, _ fields: [String: String]) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }

    // 只接受服务预期的JSON对象。
    static func json(_ data: Data) throws -> TaskFields {
        guard let json = try JSONSerialization.jsonObject(with: data) as? TaskFields else { throw err("云端响应无效") }
        return json
    }

    // 生成文件完整性校验。
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// 原生OAuth授权码及PKCE交换。
struct TaskCloudOAuth {
    let kind: TaskCloudKind
    let clientID: String
    let redirect: String
    let scheme: String
    let scope: String
    let state = UUID().uuidString
    let verifier = UUID().uuidString + UUID().uuidString

    // 读取各服务注册的公开客户端标识。
    static func registeredID(_ kind: TaskCloudKind) -> String? {
        let key = kind == .google ? "GoogleDriveClientID" : "OneDriveClientID"
        guard !kind.isDAV, let id = Bundle.main.object(forInfoDictionaryKey: key) as? String, !id.isEmpty else { return nil }
        return id
    }

    // 按已注册的客户端构造授权流程。
    init(_ kind: TaskCloudKind) throws {
        self.kind = kind
        guard let id = Self.registeredID(kind) else {
            throw TaskCloudHTTP.err("安装包缺少\(kind.name)客户端ID")
        }
        clientID = id
        if kind == .google {
            scheme = id.split(separator: ".").reversed().joined(separator: ".")
            redirect = scheme + ":/oauth2redirect"
            scope = "https://www.googleapis.com/auth/drive.file"
        } else {
            scheme = "msauth." + (Bundle.main.bundleIdentifier ?? "com.iwmei.taskforiwmei")
            redirect = scheme + "://auth"
            scope = "offline_access Files.ReadWrite"
        }
    }

    // 请求服务授权并绑定此次回调。
    var url: URL {
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let base = kind == .google ? "https://accounts.google.com/o/oauth2/v2/auth" : "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        var fields = ["client_id": clientID, "redirect_uri": redirect, "scope": scope, "response_type": "code",
                      "state": state, "code_challenge": challenge, "code_challenge_method": "S256"]
        if kind == .google { fields["access_type"] = "offline"; fields["prompt"] = "consent select_account" }
        else { fields["prompt"] = "select_account" }
        return TaskCloudHTTP.query(URL(string: base)!, fields)
    }

    // 核对回调后换取可刷新凭证，再验证账户的归档目录。
    func connect(_ callback: URL) async throws -> TaskCloudAccount {
        let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let values = parts?.queryItems ?? []
        guard callback.scheme == scheme, (kind == .google ? callback.path == "/oauth2redirect" : callback.host == "auth"),
              values.filter({ $0.name == "state" }).map(\.value) == [state],
              let code = values.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw TaskCloudHTTP.err("登录回调无效")
        }
        var account = TaskCloudAccount(kind: kind, name: kind.name)
        account = try await tokens(["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": redirect], account)
        let client = TaskCloudClient(account: account)
        account.user = try await client.identity()
        try await client.verifyWrite()
        return account
    }

    // 账户未过期时直接复用当前凭证。
    func refresh(_ account: TaskCloudAccount) async throws -> TaskCloudAccount {
        if account.expires > Date().timeIntervalSince1970 + 60 { return account }
        return try await tokens(["grant_type": "refresh_token", "refresh_token": account.secret], account)
    }

    // 按OAuth表单编码交换，不记录令牌或授权码。
    private func tokens(_ fields: [String: String], _ old: TaskCloudAccount) async throws -> TaskCloudAccount {
        let url = URL(string: kind == .google ? "https://oauth2.googleapis.com/token" : "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
        var fields = fields
        fields["client_id"] = clientID
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let form = fields.map { key, value in
            key + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        let (data, _) = try await TaskCloudHTTP.send(url, "POST", type: "application/x-www-form-urlencoded", body: Data(form.utf8))
        let result = try TaskCloudHTTP.json(data)
        guard let access = result["access_token"] as? String, !access.isEmpty,
              let lifetime = result["expires_in"] as? NSNumber, lifetime.doubleValue > 0 else { throw TaskCloudHTTP.err("云端授权无效") }
        var account = old
        account.access = access
        account.expires = Date().timeIntervalSince1970 + lifetime.doubleValue
        account.secret = result["refresh_token"] as? String ?? old.secret
        return account
    }
}

// 使用各服务原生接口创建目录、写入及读取原始文件。
struct TaskCloudClient {
    let account: TaskCloudAccount
    static let rootName = "TrollTaskArchive"
    private static let google = URL(string: "https://www.googleapis.com/drive/v3")!
    private static let googleUpload = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!
    private static let graph = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!
    private var auth: String? {
        if !account.kind.isDAV { return "Bearer " + account.access }
        if account.user.isEmpty && account.secret.isEmpty { return nil }
        return "Basic " + Data((account.user + ":" + account.secret).utf8).base64EncodedString()
    }

    // 返回OAuth账户对应的网盘身份。
    func identity() async throws -> String {
        if account.kind == .google {
            let url = TaskCloudHTTP.query(Self.google.appendingPathComponent("about"), ["fields": "user(permissionId)"])
            let (data, _) = try await TaskCloudHTTP.send(url, "GET", auth: auth)
            let result = try TaskCloudHTTP.json(data)
            guard let id = (result["user"] as? TaskFields)?["permissionId"] as? String else { throw TaskCloudHTTP.err("无法确认网盘账户") }
            return id
        }
        let (data, _) = try await TaskCloudHTTP.send(Self.graph, "GET", auth: auth)
        return try Self.itemID(TaskCloudHTTP.json(data))
    }

    // 建立固定归档目录。
    func root() async throws -> String {
        let parent = account.kind.isDAV ? try account.davURL().absoluteString : "root"
        return try await folder(Self.rootName, parent: parent)
    }

    // 真实上传并读回连接探测，避免把只读账户加入归档列表。
    func verifyWrite() async throws {
        if account.kind.isDAV { try await checkDAV(try account.davURL()) }
        let parent = try await root()
        let data = Data("TrollTask".utf8)
        let key: String
        do {
            key = try await put(data, name: ".trolltask-check", parent: parent)
        } catch let issue as NSError where [403, 405, 501].contains(issue.code) {
            throw TaskCloudHTTP.err("归档目录不能上传（\(issue.code)）", issue.code)
        }
        do {
            guard try await get(key) == data else { throw TaskCloudHTTP.err("写入校验失败") }
        } catch {
            try? await removeProbe(key)
            throw error
        }
        try? await removeProbe(key)
    }

    // 仅清理本次验证写入的文件。
    private func removeProbe(_ key: String) async throws {
        let url: URL
        switch account.kind {
        case .baidu, .dav: url = try davKey(key)
        case .one: url = graphItem(key)
        case .google: url = Self.google.appendingPathComponent("files").appendingPathComponent(key)
        }
        _ = try await TaskCloudHTTP.send(url, "DELETE", auth: auth, extra: [404])
    }

    // 检查WebDAV地址响应实际集合属性。
    private func checkDAV(_ url: URL) async throws {
        let body = Data(#"<propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>"#.utf8)
        let (data, reply) = try await TaskCloudHTTP.send(url, "PROPFIND", auth: auth,
            type: "application/xml; charset=utf-8", body: body, headers: ["Depth": "0"])
        let xml = XMLParser(data: data)
        let collection = TaskDAVCollection()
        xml.shouldProcessNamespaces = true
        xml.delegate = collection
        guard reply.statusCode == 207, xml.parse(), collection.found else { throw TaskCloudHTTP.err("地址不是WebDAV目录") }
    }

    // 将已有回执映射到当前地址，只在当前入口发请求。
    private func davKey(_ key: String) throws -> URL {
        guard var current = URLComponents(url: try account.davURL(), resolvingAgainstBaseURL: false),
              let reference = URLComponents(string: key), reference.user == nil, reference.password == nil,
              reference.query == nil, reference.fragment == nil else {
            throw TaskCloudHTTP.err("附件地址无效")
        }
        let roots = [account.endpoint] + (account.kind == .baidu ? account.previousEndpoints ?? [] : [])
        for root in roots {
            var base = account
            base.endpoint = root
            guard let url = try? base.davURL(), let source = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  reference.scheme == source.scheme, reference.host == source.host, reference.port == source.port,
                  reference.percentEncodedPath.hasPrefix(source.percentEncodedPath) else { continue }
            let suffix = reference.percentEncodedPath.dropFirst(source.percentEncodedPath.count)
            guard !suffix.isEmpty, suffix.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                guard let part = String($0).removingPercentEncoding else { return false }
                return !part.isEmpty && part != "." && part != ".." && !part.contains("/") && !part.contains("\\")
            }) else { break }
            current.percentEncodedPath += suffix
            if let resolved = current.url { return resolved }
        }
        throw TaskCloudHTTP.err("附件地址无效")
    }

    // 确保同名目录存在，便于重复请求。
    func folder(_ name: String, parent: String) async throws -> String {
        switch account.kind {
        case .baidu, .dav:
            guard let base = URL(string: parent) else { throw TaskCloudHTTP.err("目录地址无效") }
            let url = base.appendingPathComponent(name, isDirectory: true)
            let (_, reply) = try await TaskCloudHTTP.send(url, "MKCOL", auth: auth, extra: [405])
            if reply.statusCode == 405 { try await checkDAV(url) }
            return url.absoluteString
        case .google:
            let type = "application/vnd.google-apps.folder"
            if let id = try await googleFind(name, parent: parent, folder: true) { return id }
            return try await googleCreate(name, parent: parent, mime: type)
        case .one:
            let item = graphItem(parent).appendingPathComponent("children")
            let lookup = graphItem(parent + ":").appendingPathComponent(name)
            let (found, status) = try await TaskCloudHTTP.send(lookup, "GET", auth: auth, extra: [404])
            if status.statusCode != 404 { return try Self.folderID(TaskCloudHTTP.json(found)) }
            let body = try JSONSerialization.data(withJSONObject: ["name": name, "folder": [:], "@microsoft.graph.conflictBehavior": "fail"] as TaskFields)
            let (data, reply) = try await TaskCloudHTTP.send(item, "POST", auth: auth, type: "application/json", body: body, extra: [409])
            if reply.statusCode == 409 {
                let (existing, _) = try await TaskCloudHTTP.send(lookup, "GET", auth: auth)
                return try Self.folderID(TaskCloudHTTP.json(existing))
            }
            return try Self.folderID(TaskCloudHTTP.json(data))
        }
    }

    // Google按同一父目录和文件名查找当前应用可见的条目。
    private func googleFind(_ name: String, parent: String, folder: Bool) async throws -> String? {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let relation = folder ? "=" : "!="
        let q = "'\(parent)' in parents and name = '\(escaped)' and trashed = false and mimeType \(relation) 'application/vnd.google-apps.folder'"
        let url = TaskCloudHTTP.query(Self.google.appendingPathComponent("files"), ["q": q, "fields": "files(id)", "pageSize": "1"])
        let (data, _) = try await TaskCloudHTTP.send(url, "GET", auth: auth)
        return (try TaskCloudHTTP.json(data)["files"] as? [TaskFields])?.first?["id"] as? String
    }

    // 新建Google条目后按服务返回的文件ID写入。
    private func googleCreate(_ name: String, parent: String, mime: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parent], "mimeType": mime])
        let (data, _) = try await TaskCloudHTTP.send(Self.google.appendingPathComponent("files"), "POST",
            auth: auth, type: "application/json", body: body)
        return try Self.itemID(TaskCloudHTTP.json(data))
    }

    // Graph路径和ID定位共用入口。
    private func graphItem(_ key: String) -> URL {
        if key == "root" || key == "root:" { return Self.graph.appendingPathComponent(key) }
        return Self.graph.appendingPathComponent("items").appendingPathComponent(key)
    }

    // 从各原生服务响应读取有效条目标识。
    private static func itemID(_ result: TaskFields) throws -> String {
        guard let id = result["id"] as? String, !id.isEmpty else { throw TaskCloudHTTP.err("云端文件标识缺失") }
        return id
    }

    // 已存在的OneDrive同名项必须是文件夹。
    private static func folderID(_ result: TaskFields) throws -> String {
        guard result["folder"] is TaskFields else { throw TaskCloudHTTP.err("同名归档路径不是目录") }
        return try itemID(result)
    }

    // 按固定文件名覆盖重试，返回可再次读取的标识。
    func put(_ data: Data, name: String, parent: String) async throws -> String {
        let type = "application/octet-stream"
        switch account.kind {
        case .baidu, .dav:
            guard let base = URL(string: parent) else { throw TaskCloudHTTP.err("目录地址无效") }
            let url = base.appendingPathComponent(name)
            _ = try await TaskCloudHTTP.send(url, "PUT", auth: auth, type: type, body: data)
            return url.absoluteString
        case .one:
            let url = graphItem(parent + ":").appendingPathComponent(name + ":").appendingPathComponent("content")
            let (body, _) = try await TaskCloudHTTP.send(url, "PUT", auth: auth, type: type, body: data)
            return try Self.itemID(TaskCloudHTTP.json(body))
        case .google:
            let existing = try await googleFind(name, parent: parent, folder: false)
            let id: String
            if let existing { id = existing }
            else { id = try await googleCreate(name, parent: parent, mime: type) }
            let file = Self.googleUpload.appendingPathComponent(id)
            if data.count <= 5_000_000 {
                let url = TaskCloudHTTP.query(file, ["uploadType": "media"])
                _ = try await TaskCloudHTTP.send(url, "PATCH", auth: auth, type: type, body: data)
            } else {
                let url = TaskCloudHTTP.query(file, ["uploadType": "resumable"])
                let (_, reply) = try await TaskCloudHTTP.send(url, "PATCH", auth: auth, type: "application/json; charset=utf-8",
                    body: Data("{}".utf8), headers: ["X-Upload-Content-Type": type, "X-Upload-Content-Length": String(data.count)])
                guard let location = reply.value(forHTTPHeaderField: "Location"), let upload = URL(string: location),
                      upload.scheme == "https", upload.host == "www.googleapis.com" else {
                    throw TaskCloudHTTP.err("GoogleDrive上传地址无效")
                }
                _ = try await TaskCloudHTTP.send(upload, "PUT", auth: auth, type: type, body: data,
                    headers: ["Content-Range": "bytes 0-\(data.count - 1)/\(data.count)"])
            }
            return id
        }
    }

    // 读取一个远端原件，正文和鉴权不经过Web视图。
    func get(_ key: String) async throws -> Data {
        let url: URL
        switch account.kind {
        case .baidu, .dav: url = try davKey(key)
        case .one: url = graphItem(key).appendingPathComponent("content")
        case .google: url = TaskCloudHTTP.query(Self.google.appendingPathComponent("files").appendingPathComponent(key), ["alt": "media"])
        }
        return try await TaskCloudHTTP.send(url, "GET", auth: auth).0
    }
}

// 识别DAV集合属性。
private final class TaskDAVCollection: NSObject, XMLParserDelegate {
    var found = false

    // 检查标准命名空间和集合元素。
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if namespaceURI == "DAV:" && elementName == "collection" { found = true }
    }
}
