//
//  IPAResignerApp.swift
//  IPAResigner
//
//  Created by 刘强 on 2024/12/16.
//

import SwiftUI

@main
struct IPAResignerApp: App {
    init() {
        // 设置环境变量
        setenv("CODESIGN_ALLOCATE", "/Applications/Xcode.app/Contents/Developer/usr/bin/codesign_allocate", 1)
        setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin", 1)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
