import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.island

ShellRoot {
    Island {
        id: island
    }

    // Keybind entry points; Hyprland side (binds.lua, steps 8-11):
    //   bind = <mods>, <key>, global, quickshell:<name>
    GlobalShortcut {
        name: "launcher"
        description: "Toggle the island app launcher"
        onPressed: island.toggle("launcher")
    }

    GlobalShortcut {
        name: "control"
        description: "Toggle the island control center"
        onPressed: island.toggle("control")
    }

    GlobalShortcut {
        name: "wallpapers"
        description: "Toggle the island wallpaper picker"
        onPressed: island.toggle("wallpapers")
    }

    GlobalShortcut {
        name: "volumeUp"
        description: "Raise volume 5% (island flash)"
        onPressed: {
            Audio.step(1);
            island.flash();
        }
    }

    GlobalShortcut {
        name: "volumeDown"
        description: "Lower volume 5% (island flash)"
        onPressed: {
            Audio.step(-1);
            island.flash();
        }
    }

    GlobalShortcut {
        name: "volumeMute"
        description: "Toggle mute (island flash)"
        onPressed: {
            Audio.toggleMute();
            island.flash();
        }
    }

    // The island IS the session notification daemon (atomic swaync
    // replacement, spec). Capability flags: display-only toast — no
    // actions, no markup; images and body text render.
    NotificationServer {
        actionsSupported: false
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        onNotification: n => island.notify(n)
    }

    // Scripting/testing entry: qs -c island ipc call island toggle <name>
    IpcHandler {
        target: "island"

        function toggle(feature: string): void {
            island.toggle(feature);
        }

        function collapse(): void {
            island.collapse();
        }

        function dnd(on: bool): void {
            island.dnd = on;
        }

        function connectivity(tab: string): void {
            island.openConnectivity(tab);
        }

        function connectivitySub(sub: string): void {
            island.openConnectivitySub(sub);
        }

        function search(text: string): void {
            island.search(text);
        }

        function volumeUp(): void {
            Audio.step(1);
            island.flash();
        }

        function volumeDown(): void {
            Audio.step(-1);
            island.flash();
        }

        function volumeMute(): void {
            Audio.toggleMute();
            island.flash();
        }

        // Scripted device-switch verification: ids from `wpctl status`.
        function setSink(id: int): void {
            for (const node of Audio.sinks) {
                if (node.id === id) {
                    Audio.setSink(node);
                    return;
                }
            }
        }
    }
}
