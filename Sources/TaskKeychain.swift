// 共用系统钥匙串，按App身份和用途隔离认证数据。
enum TaskKeychain {
    // 构造同一App内的用途键。
    private static func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "TrollTask") + "." + service,
         kSecAttrAccount as String: "default"]
    }

    // 区分没有记录和系统无法读取。
    static func rd(_ service: String) throws -> Data? {
        var request = query(service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "无法读取认证"])
        }
        return data
    }

    // 单条钥匙串写入保留原来的设备和解锁约束。
    static func sv(_ service: String, _ data: Data?) throws {
        var request = query(service)
        var status: OSStatus
        if let data {
            status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                request[kSecValueData as String] = data
                request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(request as CFDictionary, nil)
            }
        } else {
            status = SecItemDelete(request as CFDictionary)
            if status == errSecItemNotFound { return }
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "认证未保存"])
        }
    }
}
