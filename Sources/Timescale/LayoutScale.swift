import SwiftUI

enum LayoutScale {
  static let none: CGFloat = 0
  static let unit: CGFloat = 4
  static let xSmall = unit
  static let small = unit * 2
  static let medium = unit * 3
  static let large = unit * 4
  static let xLarge = unit * 5
  static let xxLarge = unit * 6

  static let popoverWidth: CGFloat = 400
}

enum TypographyScale {
  static let heading: Font = .headline
  static let headerTime: Font = .headline.monospacedDigit()
  static let rowTitle: Font = .body.weight(.medium)
  static let rowValue: Font = .body.weight(.semibold).monospacedDigit()
  static let detail: Font = .caption
  static let supporting: Font = .caption2.monospacedDigit()
  static let action: Font = .callout
}
