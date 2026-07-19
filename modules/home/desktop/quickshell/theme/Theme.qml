pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wallpaper-driven Material You palette. Matugen renders
// /tmp/qs_colors.json (template: modules/home/programs/matugen/templates/
// qs_colors.json.template) on every wallpaper change; FileView watches it
// so recolors apply the moment the file lands — no polling.
//
// Token names are matugen's native snake_case Material You names. QML
// forbids camelCase names starting with "on" + uppercase (parsed as
// signal handlers), so on_surface etc. stay snake_case throughout.
//
// The adapter defaults below are the Material 3 baseline dark scheme,
// used until the first generation of a boot exists (/tmp starts empty;
// the wallpaper timer fires ~5s after login and self-heals this).
Singleton {
    id: root

    readonly property color primary: adapter.primary
    readonly property color on_primary: adapter.on_primary
    readonly property color primary_container: adapter.primary_container
    readonly property color on_primary_container: adapter.on_primary_container
    readonly property color secondary: adapter.secondary
    readonly property color on_secondary: adapter.on_secondary
    readonly property color secondary_container: adapter.secondary_container
    readonly property color on_secondary_container: adapter.on_secondary_container
    readonly property color tertiary: adapter.tertiary
    readonly property color tertiary_container: adapter.tertiary_container
    readonly property color error: adapter.error
    readonly property color on_error: adapter.on_error
    readonly property color error_container: adapter.error_container
    readonly property color surface: adapter.surface
    readonly property color on_surface: adapter.on_surface
    readonly property color on_surface_variant: adapter.on_surface_variant
    readonly property color surface_container_lowest: adapter.surface_container_lowest
    readonly property color surface_container_low: adapter.surface_container_low
    readonly property color surface_container: adapter.surface_container
    readonly property color surface_container_high: adapter.surface_container_high
    readonly property color surface_container_highest: adapter.surface_container_highest
    readonly property color outline: adapter.outline
    readonly property color outline_variant: adapter.outline_variant
    readonly property color inverse_surface: adapter.inverse_surface
    readonly property color shadow: adapter.shadow

    // Single source of truth for shell typography (families installed by
    // modules/system/fonts.nix).
    readonly property string fontFamily: "JetBrains Mono"
    readonly property string iconFontFamily: "Iosevka Nerd Font"

    FileView {
        id: colorFile

        path: "/tmp/qs_colors.json"
        watchChanges: true
        onFileChanged: reload()
        // File missing (fresh boot) or torn mid-write: keep current values
        // and retry shortly.
        onLoadFailed: retry.start()

        adapter: JsonAdapter {
            id: adapter

            property string primary: "#d0bcff"
            property string on_primary: "#381e72"
            property string primary_container: "#4f378b"
            property string on_primary_container: "#eaddff"
            property string secondary: "#ccc2dc"
            property string on_secondary: "#332d41"
            property string secondary_container: "#4a4458"
            property string on_secondary_container: "#e8def8"
            property string tertiary: "#efb8c8"
            property string tertiary_container: "#633b48"
            property string error: "#f2b8b5"
            property string on_error: "#601410"
            property string error_container: "#8c1d18"
            property string surface: "#141218"
            property string on_surface: "#e6e0e9"
            property string on_surface_variant: "#cac4d0"
            property string surface_container_lowest: "#0f0d13"
            property string surface_container_low: "#1d1b20"
            property string surface_container: "#211f26"
            property string surface_container_high: "#2b2930"
            property string surface_container_highest: "#36343b"
            property string outline: "#938f99"
            property string outline_variant: "#49454f"
            property string inverse_surface: "#e6e0e9"
            property string shadow: "#000000"
        }
    }

    Timer {
        id: retry

        interval: 2000
        onTriggered: colorFile.reload()
    }
}
