// 保存助手连接设置，密钥只存系统钥匙串。
enum TaskAIConfig {
    // 读取现有Tailscale服务与可选认证。
    static func ld()->TaskFields {
        // 只迁移既有默认档，用户后续仍可修改每档真实模型ID。
        if UserDefaults.standard.integer(forKey:"assistant.tiers")==0 {if UserDefaults.standard.string(forKey:"assistant.model")=="fast-model"{UserDefaults.standard.set("deepseek-v4.1-flash",forKey:"assistant.model")};UserDefaults.standard.set(1,forKey:"assistant.tiers")}
        let key=(try? TaskKeychain.rd("assistant")).flatMap{String(data:$0,encoding:.utf8)} ?? ""
        return ["endpoint":UserDefaults.standard.string(forKey:"assistant.endpoint") ?? "http://100.121.131.101:8765/v1","model":UserDefaults.standard.string(forKey:"assistant.model") ?? "deepseek-v4.1-flash","hard_model":UserDefaults.standard.string(forKey:"assistant.hard_model") ?? "glm-5.3","ddl_model":UserDefaults.standard.string(forKey:"assistant.ddl_model") ?? "glm-5.3","key":key]
    }
    // 校验连接信息后保存，认证失败保留原密钥。
    static func sv(_ config:TaskFields) throws {
        _ = try TaskAI.req(["goal":"验证设置"],config)
        let key=config["key"] as? String ?? ""
        try TaskKeychain.sv("assistant",key.isEmpty ? nil : Data(key.utf8))
        UserDefaults.standard.set(config["endpoint"],forKey:"assistant.endpoint");UserDefaults.standard.set(config["model"],forKey:"assistant.model");for key in ["hard_model","ddl_model"]{if let value=config[key] as? String,!value.isEmpty{UserDefaults.standard.set(value,forKey:"assistant."+key)}}
    }
}