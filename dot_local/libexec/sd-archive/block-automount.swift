// block-automount.swift
// 実行している間だけ、外付け／取り外し可能なディスクの自動マウントを拒否する。
// （ディスクイメージ = hdiutil attach したものは拒否しない）
//
// ビルド:  chezmoi apply 時に run_onchange_after_51-sd-archive-build が
//          swiftc -O block-automount.swift -o block-automount を実行する（要 Xcode CLT）
// 実行:    sd-archive が起動・終了を面倒みる。単体なら ./block-automount（Ctrl+C で解除）
//
// 仕組み: Disk Arbitration の「マウント承認コールバック」に登録し、
//         対象ディスクのマウント要求に「不許可」を返す。
//         ボリュームはマウントされないが、/dev/rdiskN の生読み込みはできる。

import Foundation
import DiskArbitration

func str(_ d: NSDictionary, _ k: CFString) -> String? { d[k as String] as? String }
func flag(_ d: NSDictionary, _ k: CFString) -> Bool { (d[k as String] as? Bool) ?? false }

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

let approval: DADiskMountApprovalCallback = { disk, _ in
    guard let desc = DADiskCopyDescription(disk) as NSDictionary? else { return nil }

    let bsd = DADiskGetBSDName(disk).map { String(cString: $0) } ?? "?"
    let proto = str(desc, kDADiskDescriptionDeviceProtocolKey) ?? ""
    let model = str(desc, kDADiskDescriptionDeviceModelKey) ?? ""
    let removable = flag(desc, kDADiskDescriptionMediaRemovableKey)
                 || flag(desc, kDADiskDescriptionMediaEjectableKey)
    let isInternal = flag(desc, kDADiskDescriptionDeviceInternalKey)

    // ディスクイメージは許可（スクリプトが読み取り専用で開くため）
    if proto == "Disk Image" || proto == "Virtual Interface" {
        print("[\(timestamp())] allow  \(bsd) (\(proto))")
        return nil
    }
    // 内蔵・取り外し不可（Mac本体のSSDなど）は許可
    if isInternal && !removable {
        return nil
    }

    print("[\(timestamp())] BLOCK  \(bsd) protocol=\(proto) model=\(model)")
    fflush(stdout)
    let dissenter = DADissenterCreate(
        kCFAllocatorDefault,
        DAReturn(truncatingIfNeeded: kDAReturnNotPermitted),
        "blocked by block-automount" as CFString)
    return Unmanaged.passRetained(dissenter)
}

guard let session = DASessionCreate(kCFAllocatorDefault) else {
    fputs("DASessionCreate に失敗しました\n", stderr)
    exit(1)
}
DARegisterDiskMountApprovalCallback(session, nil, approval, nil)
DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

print("[\(timestamp())] 自動マウントのブロックを開始しました（Ctrl+C で解除）")
fflush(stdout)
CFRunLoopRun()
