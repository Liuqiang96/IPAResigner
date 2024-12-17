//
//  ResignService.swift
//  IPAResigner
//
//  Created by 刘强 on 2024/12/16.
//
import Foundation

class ResignService {
    enum ResignError: LocalizedError {
        case invalidIPAPath
        case invalidProvisioningProfile
        case signFailed(String)
        case zipFailed
        case unzipFailed
        case tempDirCreationFailed
        case certificateNotFound
        
        var errorDescription: String? {
            switch self {
            case .invalidIPAPath:
                return "无效的 IPA 文件路径"
            case .invalidProvisioningProfile:
                return "无效的描述文件或无法提取 entitlements"
            case .signFailed(let message):
                return "签名失败: \(message)"
            case .zipFailed:
                return "打包 IPA 文件失败"
            case .unzipFailed:
                return "解压 IPA 文件失败"
            case .tempDirCreationFailed:
                return "创建临时目录失败"
            case .certificateNotFound:
                return "未找到有效的证书"
            }
        }
    }
    
    struct SigningIdentity: Hashable {
        let id: String
        let name: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: SigningIdentity, rhs: SigningIdentity) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    typealias ProgressCallback = (String) -> Void
    
    private let ipaPath: String
    private let provisioningProfilePath: String
    private let selectedIdentity: SigningIdentity
    private let newBundleId: String?
    private let outputPath: String
    private let progress: ProgressCallback
    
    init(ipaPath: String,
         provisioningProfilePath: String,
         selectedIdentity: SigningIdentity,
         newBundleId: String?,
         outputPath: String,
         progress: @escaping ProgressCallback) {
        self.ipaPath = ipaPath
        self.provisioningProfilePath = provisioningProfilePath
        self.selectedIdentity = selectedIdentity
        self.newBundleId = newBundleId
        self.outputPath = outputPath
        self.progress = progress
    }
    
    func resign() async throws {
        // 创建临时工作目录
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 解压IPA
        progress("正在解压IPA...")
        let payloadDir = tempDir.appendingPathComponent("Payload")
        try unzipIPA(to: tempDir)
        
        // 获取app路径
        guard let appPath = try getAppPath(in: payloadDir) else {
            throw ResignError.invalidIPAPath
        }
        
        // 替换描述文件
        progress("正在替换描述文件...")
        try replaceProvisioningProfile(at: appPath)
        
        // 修改Info.plist（如果需要）
        if let newBundleId = newBundleId {
            progress("正在更新Bundle ID...")
            try updateBundleId(at: appPath, to: newBundleId)
        }
        
        // 重签名
        progress("正在重签名...")
        try signApp(at: appPath)
        
        // 打包新的IPA
        progress("正在打包新的IPA...")
        try createNewIPA(from: tempDir)
        
        progress("重签名完成！")
    }
    
    private func log(_ message: String) {
        print("[ResignService] \(message)")
        progress(message)
    }
    
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir,
                                             withIntermediateDirectories: true)
        return tempDir
    }
    
    private func unzipIPA(to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", ipaPath, "-d", directory.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ResignError.unzipFailed
        }
    }
    
    private func getAppPath(in payloadDir: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: payloadDir,
                                                                 includingPropertiesForKeys: nil)
        return contents.first { $0.pathExtension == "app" }
    }
    
    private func replaceProvisioningProfile(at appPath: URL) throws {
        let embedProfilePath = appPath.appendingPathComponent("embedded.mobileprovision")
        if FileManager.default.fileExists(atPath: embedProfilePath.path) {
            try FileManager.default.removeItem(at: embedProfilePath)
        }
        try FileManager.default.copyItem(atPath: provisioningProfilePath,
                                       toPath: embedProfilePath.path)
    }
    
    private func updateBundleId(at appPath: URL, to newBundleId: String) throws {
        let infoPlistPath = appPath.appendingPathComponent("Info.plist")
        guard let dict = NSMutableDictionary(contentsOfFile: infoPlistPath.path) else {
            return
        }
        dict["CFBundleIdentifier"] = newBundleId
        dict.write(toFile: infoPlistPath.path, atomically: true)
    }
    
    private func signApp(at appPath: URL) throws {
        // 签名所有框架和动态库
        let frameworksPath = appPath.appendingPathComponent("Frameworks")
        if FileManager.default.fileExists(atPath: frameworksPath.path) {
            let frameworks = try FileManager.default.contentsOfDirectory(at: frameworksPath,
                                                                       includingPropertiesForKeys: nil)
            for framework in frameworks {
                try sign(path: framework.path)
            }
        }
        
        // 签名主应用
        try sign(path: appPath.path)
    }
    
    private func sign(path: String) throws {
        log("开始签名: \(path)")
        
        // 从描述文件中提取 entitlements
        let entitlementsPath = try extractEntitlements()
        defer { try? FileManager.default.removeItem(atPath: entitlementsPath) }
        
        // 使用选择的证书身份进行签名
        let process = Process()
        let pipe = Pipe()
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.environment = ["CODESIGN_ALLOCATE": "/Applications/Xcode.app/Contents/Developer/usr/bin/codesign_allocate"]
        let keychainPath = try getDefaultKeychainPath()
        process.arguments = [
            "-f",                    // 强制签名
            "-s", selectedIdentity.id,  // 使用证书的 SHA-1 标识符
            "--entitlements", entitlementsPath,
            "--keychain", keychainPath,
            path
        ]
        
        log("执行签名命令: codesign -f -s \"\(selectedIdentity.id)\" --entitlements \(entitlementsPath) --keychain \(keychainPath) \(path)")
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            log("签名失败: \(errorMessage)")
            throw ResignError.signFailed(errorMessage)
        }
        
        log("签名成功")
    }
    
    private func getDefaultKeychainPath() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["default-keychain", "-d", "user"]
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        var path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        log("默认钥匙串路径: \(path)")
        return path
    }
    
    private func extractEntitlements() throws -> String {
        log("从描述文件中提取 entitlements...")
        
        let entitlementsPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).plist")
            .path
        
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "cms",
            "-D",
            "-i",
            provisioningProfilePath
        ]
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ResignError.invalidProvisioningProfile
        }
        
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            throw ResignError.invalidProvisioningProfile
        }
        
        let entitlementsData = try PropertyListSerialization.data(fromPropertyList: entitlements,
                                                                format: .xml,
                                                                options: 0)
        try entitlementsData.write(to: URL(fileURLWithPath: entitlementsPath))
        
        log("Entitlements 已提取到: \(entitlementsPath)")
        return entitlementsPath
    }
    
    private func createNewIPA(from tempDir: URL) throws {
        log("开始打包 IPA...")
        
        var finalOutputPath = outputPath
        if !finalOutputPath.lowercased().hasSuffix(".ipa") {
            finalOutputPath += ".ipa"
        }
        
        if FileManager.default.fileExists(atPath: finalOutputPath) {
            try FileManager.default.removeItem(atPath: finalOutputPath)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tempDir
        process.arguments = [
            "-qry",
            finalOutputPath,
            "Payload"
        ]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            log("打包失败: \(errorMessage)")
            throw ResignError.zipFailed
        }
        
        log("IPA 已打包到: \(finalOutputPath)")
    }
    
    func getAvailableIdentities() throws -> [SigningIdentity] {
        let keychainPath = try getDefaultKeychainPath()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-identity",
            "-v",
            "-p", "codesigning",
            keychainPath
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let output = try pipe.fileHandleForReading.readToEnd().flatMap { String(data: $0, encoding: .utf8) } ?? ""
        
        return output.components(separatedBy: .newlines)
            .compactMap { line -> SigningIdentity? in
                // 1) 49D094AFF3B420616057E1B552B0A2CF1B308F3F "Apple Development: Qiang Liu (56HWTSU5A7)"
                guard line.contains("\"") else { return nil }
                
                // 提取完整的 SHA-1 值
                if let shaRange = line.range(of: "[A-F0-9]{40}", options: .regularExpression),
                   let nameRange = line.range(of: "\".*\"", options: .regularExpression) {
                    let id = String(line[shaRange])
                    let name = String(line[nameRange])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return SigningIdentity(id: id, name: name)
                }
                return nil
            }
    }
} 
