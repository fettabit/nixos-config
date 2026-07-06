import QtQuick
import Quickshell
import qs.theme

// Step-6 scaffold: proves the config loads, Theme recolors live, and a
// top-center pill lands where expected on 5120x1440. Replaced by
// island/Island.qml in step 7.
ShellRoot {
    PanelWindow {
        anchors.top: true
        margins.top: 12
        implicitWidth: 300
        implicitHeight: 46
        color: "transparent"
        // The island floats over windows; it must not reserve layout space.
        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.surface_container
            border.width: 1
            border.color: Theme.primary

            Text {
                anchors.centerIn: parent
                text: "island scaffold"
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 18
            }
        }
    }
}
