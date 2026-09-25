import CoreGraphics

/// Rows and columns of equal cells, for the App Icons and Thumbnails styles.
struct GridLayout: Equatable {
    let count: Int
    let columns: Int
    let cellSize: CGSize
    let spacing: CGFloat

    var rows: Int {
        columns == 0 ? 0 : (count + columns - 1) / columns
    }

    var contentSize: CGSize {
        CGSize(
            width: CGFloat(columns) * cellSize.width + CGFloat(max(columns - 1, 0)) * spacing,
            height: CGFloat(rows) * cellSize.height + CGFloat(max(rows - 1, 0)) * spacing
        )
    }

    /// Cells of a fixed size, as many per row as fit.
    static func fixed(count: Int, cellSize: CGSize, spacing: CGFloat, availableWidth: CGFloat) -> GridLayout {
        let fitting = Int((availableWidth + spacing) / (cellSize.width + spacing))
        return GridLayout(count: count, columns: max(1, min(count, fitting)), cellSize: cellSize, spacing: spacing)
    }

    /// The largest cells that fit all `count` windows in `available`, up to
    /// `maxCellWidth`. Prefers fewer rows when cells come out the same size.
    /// Below `minCellWidth`, cells stay at that size and the grid scrolls.
    ///
    /// A cell is `width` wide and `width * aspectRatio + extraHeight` tall:
    /// the preview plus a title line.
    static func fitting(
        count: Int,
        in available: CGSize,
        spacing: CGFloat,
        aspectRatio: CGFloat,
        extraHeight: CGFloat,
        minCellWidth: CGFloat,
        maxCellWidth: CGFloat
    ) -> GridLayout {
        func cell(_ width: CGFloat) -> CGSize {
            // Whole points, rounded down, so a grid that fits never scrolls by a fraction.
            CGSize(width: width, height: (width * aspectRatio + extraHeight).rounded(.down))
        }
        guard count > 0 else {
            return GridLayout(count: 0, columns: 0, cellSize: cell(maxCellWidth), spacing: spacing)
        }

        var bestColumns = 1
        var bestWidth: CGFloat = 0
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let byWidth = (available.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let rowHeight = (available.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let byHeight = (rowHeight - extraHeight) / aspectRatio
            let width = min(byWidth, byHeight, maxCellWidth)
            if width >= bestWidth - 0.5 {
                bestColumns = columns
                bestWidth = width
            }
        }

        if bestWidth >= minCellWidth {
            return GridLayout(count: count, columns: bestColumns, cellSize: cell(bestWidth.rounded(.down)), spacing: spacing)
        }
        return fixed(count: count, cellSize: cell(minCellWidth), spacing: spacing, availableWidth: available.width)
    }

    /// The frame of cell `index`, with the origin at the top left. A last row
    /// that isn't full is centered.
    func frame(ofCell index: Int) -> CGRect {
        let row = index / columns
        let column = index % columns
        let cellsInRow = row == rows - 1 ? count - row * columns : columns
        let rowWidth = CGFloat(cellsInRow) * cellSize.width + CGFloat(cellsInRow - 1) * spacing
        let inset = (contentSize.width - rowWidth) / 2
        return CGRect(
            x: inset + CGFloat(column) * (cellSize.width + spacing),
            y: CGFloat(row) * (cellSize.height + spacing),
            width: cellSize.width,
            height: cellSize.height
        )
    }
}
