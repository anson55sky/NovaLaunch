// 整体搬迁自 SearchService.swift 的 String 扩展
// 唯一变化：加 public
import Foundation

public extension String {
    /// 中文转拼音全拼（使用 CFStringTransform 纯 Apple API）
    func toPinyin() -> String {
        let mutable = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).replacingOccurrences(of: " ", with: "")
    }

    /// 中文转拼音首字母
    func toPinyinInitials() -> String {
        let pinyin = toPinyin()
        return pinyin.compactMap { char -> String? in
            guard let scalar = char.unicodeScalars.first else { return nil }
            if scalar.value >= 0x41, scalar.value <= 0x5A {
                return String(char)
            } else if scalar.value >= 0x61, scalar.value <= 0x7A {
                return String(char)
            }
            return nil
        }.joined()
    }
}
