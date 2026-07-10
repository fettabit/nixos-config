pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The shell's single PipeWire writer. Every volume/mute/device change
// routes through here; UI components only read state and call these
// functions. Null-safe throughout: the default sink can be absent at
// startup or vanish on device removal.
// Spec: docs/superpowers/specs/2026-07-09-island-volume-design.md
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    // Hardware outputs for the device list (sink nodes, not app streams).
    readonly property var sinks: [...Pipewire.nodes.values]
        .filter(n => n.isSink && !n.isStream)

    // Bind the sinks so their audio properties are live.
    PwObjectTracker {
        objects: root.sinks
    }

    // One unmute rule (spec): raising the volume unmutes — shared by
    // F12/wheel-up (step) and slider drags (setVolume).
    function setVolume(v: real): void {
        if (!ready)
            return;
        const clamped = Math.max(0, Math.min(1, v));
        if (clamped > sink.audio.volume)
            sink.audio.muted = false;
        sink.audio.volume = clamped;
    }

    function step(dir: int): void {
        if (!ready)
            return;
        // Explicit unmute here too: at 100% a further F12 raises nothing,
        // but must still unmute.
        if (dir > 0 && sink.audio.muted)
            sink.audio.muted = false;
        setVolume(volume + dir * 0.05);
    }

    function toggleMute(): void {
        if (!ready)
            return;
        sink.audio.muted = !sink.audio.muted;
    }

    // Untyped param on purpose: PwNode annotations are not worth the
    // qmlcachegen risk; callers only ever pass nodes from `sinks`.
    function setSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
}
