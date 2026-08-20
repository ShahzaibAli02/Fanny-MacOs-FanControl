# Localization

Fan Control uses the standard macOS bundle localization mechanism. At launch,
macOS selects the best matching language from the user's system language order
or the per-application language selected in **System Settings → General →
Language & Region**. No network service, account, or third-party runtime is
used.

## Included languages

| Language | Locale directory |
|---|---|
| English (development language) | `Localization/en.lproj` |
| French | `Localization/fr.lproj` |
| German | `Localization/de.lproj` |
| Spanish | `Localization/es.lproj` |
| Simplified Chinese | `Localization/zh-Hans.lproj` |

Every directory contains `Localizable.strings`. The build script copies these
directories into `Fan Control.app/Contents/Resources`, where macOS discovers
them through the bundle's standard `CFBundleLocalizations` metadata.

## Verification status

The English and French interfaces have been manually verified in the app.
German, Spanish, and Simplified Chinese are included for broader coverage, but
they have **not** yet been tested in the app or reviewed by native speakers.
They should be reviewed before presenting them as release-ready translations.

## Updating a translation

1. Use the English file as the complete key list.
2. Keep the text left of `=` exactly unchanged; it is the source key used by
   SwiftUI and the `L10n` helper.
3. Preserve format placeholders such as `%@`, `%d`, and `%.1f` in the same
   order and type as the English entry.
4. Do not translate SMC register identifiers, units, or product names unless a
   locale convention genuinely requires it.
5. Build the app and select that language in macOS to review labels, menus,
   help text, authorization errors, and chart controls.

SwiftUI text literals use the bundle automatically. `Core/Localization.swift`
is used only where a label is assembled dynamically at runtime, so it follows
the identical macOS lookup and fallback behaviour.
