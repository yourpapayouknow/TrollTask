// 集中导入原生Swift核心依赖与共享记录类型。
@_exported import Foundation
@_exported import Dispatch
#if os(iOS)
@_exported import PhotosUI
@_exported import UniformTypeIdentifiers
@_exported import AVFAudio
@_exported import AudioToolbox
@_exported import CoreMotion
#endif
typealias TaskFields = [String: Any]
