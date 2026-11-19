import CmuxSettings
import Foundation
import os

/// Settings-file parsing for the `workspaceColors` section.
extension CmuxSettingsFileStore {
    func parseWorkspaceColorsSection(
        _ section: [String: Any],
        sourcePath: String,
        snapshot: inout ResolvedSettingsSnapshot
    ) {
        if let raw = jsonString(section["indicatorStyle"]) {
            let indicatorKey = SettingCatalog().workspaceColors.indicatorStyle
            let normalized = (WorkspaceIndicatorStyle.decodeFromJSON(raw) ?? indicatorKey.defaultValue).rawValue
            let accepted = Set(WorkspaceIndicatorStyle.allCases.map(\.rawValue)).union([
                "rail", "border", "wash", "lift", "typography", "washRail", "blueWashColorRail",
            ])
            guard accepted.contains(raw) else {
                logInvalid("workspaceColors.indicatorStyle", sourcePath: sourcePath)
                return
            }
            snapshot.managedUserDefaults[indicatorKey.userDefaultsKey] = .string(normalized)
        }
        if section.keys.contains("selectionColor") {
            guard let value = parseNullableHex(
                section["selectionColor"],
                path: "workspaceColors.selectionColor",
                sourcePath: sourcePath
            ) else { return }
            snapshot.managedUserDefaults["sidebarSelectionColorHex"] = .nullableString(value)
        }
        if section.keys.contains("subtleSelection") {
            if let value = jsonBool(section["subtleSelection"]) {
                snapshot.managedUserDefaults[SettingCatalog().workspaceColors.subtleSelection.userDefaultsKey] = .bool(value)
            } else {
                logInvalid("workspaceColors.subtleSelection", sourcePath: sourcePath)
            }
        }
        if section.keys.contains("brightenInDarkMode") {
            if let value = jsonBool(section["brightenInDarkMode"]) {
                snapshot.managedUserDefaults[SettingCatalog().workspaceColors.brightenInDarkMode.userDefaultsKey] = .bool(value)
            } else {
                logInvalid("workspaceColors.brightenInDarkMode", sourcePath: sourcePath)
            }
        }
        if section.keys.contains("unselectedFillOpacity") {
            if let value = jsonDouble(section["unselectedFillOpacity"]), value.isFinite {
                snapshot.managedUserDefaults[SettingCatalog().workspaceColors.unselectedFillOpacity.userDefaultsKey] =
                    .double(min(max(value, 0), 1))
            } else {
                logInvalid("workspaceColors.unselectedFillOpacity", sourcePath: sourcePath)
            }
        }
        if section.keys.contains("autoColor") {
            let autoColorKey = SettingCatalog().workspaceColors.autoColor
            if let mode = WorkspaceAutoColorMode.decodeFromJSON(section["autoColor"]) {
                snapshot.managedUserDefaults[autoColorKey.userDefaultsKey] = .string(mode.rawValue)
            } else {
                logInvalid(autoColorKey.id, sourcePath: sourcePath)
            }
        }
        if section.keys.contains("notificationBadgeColor") {
            guard let value = parseNullableHex(
                section["notificationBadgeColor"],
                path: "workspaceColors.notificationBadgeColor",
                sourcePath: sourcePath
            ) else { return }
            snapshot.managedUserDefaults["sidebarNotificationBadgeColorHex"] = .nullableString(value)
        }
        if section.keys.contains("colors") {
            guard let rawColors = section["colors"] as? [String: Any] else {
                logInvalid("workspaceColors.colors", sourcePath: sourcePath)
                return
            }

            var normalizedPalette: [String: String] = [:]
            for (rawName, rawValue) in rawColors {
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    cmuxSettingsFileStoreLogger.warning("ignoring empty workspace color name in \(sourcePath, privacy: .private(mask: .hash))")
                    continue
                }
                guard let hex = jsonString(rawValue),
                      let normalizedHex = WorkspaceTabColorSettings.normalizedHex(hex) else {
                    cmuxSettingsFileStoreLogger.warning("ignoring invalid workspace color '\(name, privacy: .private(mask: .hash))' in \(sourcePath, privacy: .private(mask: .hash))")
                    continue
                }
                normalizedPalette[name] = normalizedHex
            }
            snapshot.managedUserDefaults[WorkspaceTabColorSettings.paletteKey] = .stringDictionary(normalizedPalette)
            return
        }

        let validNames = Set(WorkspaceTabColorSettings.defaultPalette.map(\.name))
        var normalizedLegacyPalette: [String: String]? = nil
        if let rawOverrides = section["paletteOverrides"] as? [String: Any] {
            var palette = Dictionary(
                uniqueKeysWithValues: WorkspaceTabColorSettings.defaultPalette.map { ($0.name, $0.hex) }
            )
            for (name, rawValue) in rawOverrides {
                guard validNames.contains(name) else {
                    cmuxSettingsFileStoreLogger.warning("ignoring unknown workspace color '\(name, privacy: .private(mask: .hash))' in \(sourcePath, privacy: .private(mask: .hash))")
                    continue
                }
                guard let hex = jsonString(rawValue),
                      let normalizedHex = WorkspaceTabColorSettings.normalizedHex(hex) else {
                    cmuxSettingsFileStoreLogger.warning("ignoring invalid workspace color override '\(name, privacy: .private(mask: .hash))' in \(sourcePath, privacy: .private(mask: .hash))")
                    continue
                }
                palette[name] = normalizedHex
            }
            normalizedLegacyPalette = palette
        }
        if let rawCustomColors = jsonStringArray(section["customColors"]) {
            var palette = normalizedLegacyPalette ?? Dictionary(
                uniqueKeysWithValues: WorkspaceTabColorSettings.defaultPalette.map { ($0.name, $0.hex) }
            )
            var existingNames = Set(palette.keys)
            var seenCustomHexes: Set<String> = []
            for rawHex in rawCustomColors {
                guard let normalizedHex = WorkspaceTabColorSettings.normalizedHex(rawHex),
                      seenCustomHexes.insert(normalizedHex).inserted else { continue }
                var index = 1
                while existingNames.contains("Custom \(index)") {
                    index += 1
                }
                let name = "Custom \(index)"
                palette[name] = normalizedHex
                existingNames.insert(name)
            }
            normalizedLegacyPalette = palette
        }
        if let normalizedLegacyPalette {
            snapshot.managedUserDefaults[WorkspaceTabColorSettings.paletteKey] = .stringDictionary(normalizedLegacyPalette)
        }
    }
}
