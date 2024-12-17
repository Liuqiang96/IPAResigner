//
//  ContentView.swift
//  IPAResigner
//
//  Created by 刘强 on 2024/12/16.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var ipaPath: String = ""
    @State private var provisioningProfilePath: String = ""
    @State private var selectedIdentity: ResignService.SigningIdentity?
    @State private var availableIdentities: [ResignService.SigningIdentity] = []
    @State private var newBundleId: String = ""
    @State private var outputPath: String = ""
    @State private var isResigning = false
    @State private var progress = ""
    @State private var error: Error?
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("iOS IPA 重签名工具")
                .font(.title)
                .padding()
            
            // IPA文件选择
            HStack {
                TextField("IPA文件路径", text: $ipaPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("选择IPA") {
                    selectIPA()
                }
            }
            
            // 描述文件选择
            HStack {
                TextField("描述文件路径", text: $provisioningProfilePath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("选择描述文件") {
                    selectProvisioningProfile()
                }
            }
            
            // 证书选择
            Picker("签名证书", selection: $selectedIdentity) {
                Text("请选择证书").tag(nil as ResignService.SigningIdentity?)
                ForEach(availableIdentities, id: \.id) { identity in
                    Text(identity.name).tag(identity as ResignService.SigningIdentity?)
                }
            }
            .onAppear {
                loadAvailableIdentities()
            }
            
            // Bundle ID
            TextField("Bundle ID (可选)", text: $newBundleId)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            // 输出路径选择
            HStack {
                TextField("输出路径", text: $outputPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("选择输出路径") {
                    selectOutputPath()
                }
            }
            
            // 重签名按钮
            Button(action: {
                resign()
            }) {
                Text("开始重签名")
                    .frame(minWidth: 100)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isResigning)
            
            // 进度信息
            if !progress.isEmpty {
                Text(progress)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .multilineTextAlignment(.leading)
            }
            
            if isResigning {
                ProgressView()
                    .padding(.top, 10)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 600)
    }
    
    private func selectIPA() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "ipa")!]
        
        if panel.runModal() == .OK {
            ipaPath = panel.url?.path ?? ""
        }
    }
    
    private func selectProvisioningProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "mobileprovision")!]
        
        if panel.runModal() == .OK {
            provisioningProfilePath = panel.url?.path ?? ""
        }
    }
    
    private func selectOutputPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择输出目录"
        
        if panel.runModal() == .OK {
            let selectedPath = panel.url?.path ?? ""
            // 获取原始 IPA 的文件名
            let originalFileName = (ipaPath as NSString).lastPathComponent
            let originalNameWithoutExt = (originalFileName as NSString).deletingPathExtension
            // 创建新的输出路径
            outputPath = (selectedPath as NSString).appendingPathComponent("\(originalNameWithoutExt)_resigned.ipa")
        }
    }
    
    private func loadAvailableIdentities() {
        do {
            // 创建一个临时的 ResignService 实例，只用于获取证书列表
            let service = ResignService(
                ipaPath: "",
                provisioningProfilePath: "",
                selectedIdentity: .init(id: "", name: ""),  // 临时的空身份
                newBundleId: nil,
                outputPath: "",
                progress: { _ in }
            )
            availableIdentities = try service.getAvailableIdentities()
        } catch {
            self.error = error
        }
    }
    
    private func resign() {
        guard let identity = selectedIdentity else {
            error = ResignService.ResignError.certificateNotFound
            return
        }
        
        isResigning = true
        error = nil
        progress = ""
        
        let service = ResignService(
            ipaPath: ipaPath,
            provisioningProfilePath: provisioningProfilePath,
            selectedIdentity: identity,
            newBundleId: newBundleId.isEmpty ? nil : newBundleId,
            outputPath: outputPath,
            progress: { message in
                DispatchQueue.main.async {
                    self.progress = message
                }
            }
        )
        
        Task {
            do {
                try await service.resign()
                DispatchQueue.main.async {
                    self.isResigning = false
                    self.progress = "重签名完成"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isResigning = false
                    self.error = error
                    self.progress = "重签名失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
