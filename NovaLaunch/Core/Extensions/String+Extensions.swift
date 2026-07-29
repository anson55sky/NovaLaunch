import Foundation

extension String {
    /// 返回小写的拼音首字母缩写（框架占位，Phase 2 接入 libpinyin/原生拼音 API）
    var pinyinInitials: String {
        return lowercased()
    }

    /// 返回整串拼音（无空格），框架占位
    var pinyinFull: String {
        return lowercased()
    }

    /// 拼音首字母别名（兼容旧 API，可作为方法调用也可作为属性访问）
    var toPinyinInitials: String { pinyinInitials }
    /// 完整拼音别名（兼容旧 API）
    var toPinyin: String { pinyinFull }
    /// 拼音方法别名（兼容旧代码中 toPinyin() 的调用方式）
    func toPinyinString() -> String { pinyinFull }
    func toPinyinInitialsString() -> String { pinyinInitials }

    /// Swift 5.7+ 原生编辑距离，模糊容错阈值为 2
    func editDistance(to other: String) -> Int {
        return self.difference(from: other).count
    }
}
