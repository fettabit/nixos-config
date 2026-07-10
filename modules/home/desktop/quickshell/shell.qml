import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
        name: "volume"
        description: "Toggle the island volume panel"
        onPressed: island.toggle("volume")
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

    // Scripting/testing entry: qs -c island ipc call island toggle <name>
    IpcHandler {
        target: "island"

        function toggle(feature: string): void {
            island.toggle(feature);
        }

        function collapse(): void {
            island.collapse();
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
    }
}
