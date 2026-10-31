import CoreGraphics

/// Supplies deterministic estimates while AppKit resolves exact hosted SwiftUI row heights.
struct SidebarWorkspaceTableRowHeightCalculator {
    var defaultWorkspaceHeight: CGFloat {
        estimatedWorkspaceHeight(fontScale: 1, titleLineCount: 1, auxiliaryLineCount: 0)
    }

    func estimatedWorkspaceHeight(
        fontScale: CGFloat,
        titleLineCount: Int,
        auxiliaryLineCount: Int
    ) -> CGFloat {
        let scale = max(0.5, fontScale)
        let titleLines = max(1, titleLineCount)
        let auxiliaryLines = max(0, auxiliaryLineCount)
        let titleHeight = CGFloat(titleLines) * 15 * scale
        let auxiliaryHeight = CGFloat(auxiliaryLines) * 12 * scale
        let interlineSpacing = auxiliaryLines > 0 ? CGFloat(auxiliaryLines) * 4 : 0
        return ceil(16 + titleHeight + auxiliaryHeight + interlineSpacing)
    }

    /// Group headers have deterministic, layout-free heights, so the estimate
    /// is the authoritative height itself. Delegating to
    /// ``SidebarGroupHeaderTableCellView/preferredHeight(model:)`` keeps the two
    /// from diverging on the font scale (`model.fontScale`, not the global
    /// magnification), the name size, or the top gap — any mismatch settles the
    /// first row when the real measurement lands.
    @MainActor
    func estimatedGroupHeaderHeight(model: SidebarGroupHeaderRowModel) -> CGFloat {
        SidebarGroupHeaderTableCellView.preferredHeight(model: model)
    }
}
