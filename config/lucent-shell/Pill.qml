// One module in the bar: a label on a rounded background, with clicks, scroll
// and a tooltip. The shape is waybar's style.css — padding 0 10px, margin
// 2px either side, radius 8 — and the height is Settings.pillHeight.

import QtQuick

Item {
    id: pill

    property string text: ""
    // A glyph drawn beside the text, 4px from it: closer than the two
    // spaces waybar's formats used, and the same whatever the font's space.
    property string icon: ""
    property color fg: Theme.c("text")
    property color bg: "transparent"
    property color hoverBg: bg
    property color hoverFg: fg
    property string tip: ""
    property bool richTip: false
    // Tighter in the panel, whose right-hand side otherwise reaches in
    // towards the dock in the middle; waybar's 10 in the top bar's islands.
    property int padX: Settings.panelMode ? 6 : 10
    property int fontSize: 14
    // Glyphs sit a little larger than the figures beside them.
    property int iconSize: fontSize + 2
    property int fontWeight: Font.DemiBold
    readonly property bool hovered: mouse.containsMouse

    // button is Qt.LeftButton, Qt.MiddleButton or Qt.RightButton.
    signal clicked(int button)
    // One step per notch, whatever the device: +1 up, -1 down.
    signal scrolled(int step)

    visible: text !== "" || icon !== ""
    implicitWidth: box.width + (Settings.panelMode ? 2 : 4)
    implicitHeight: Settings.pillHeight

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: content.implicitWidth + 2 * pill.padX
        height: parent.height
        radius: 8
        color: pill.hovered ? pill.hoverBg : pill.bg
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on width { NumberAnimation { duration: 150 } }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: pill.icon !== "" && pill.text !== "" ? 4 : 0

            Text {
                visible: pill.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                color: pill.hovered ? pill.hoverFg : pill.fg
                font.family: Theme.font
                font.pixelSize: pill.iconSize
                font.weight: pill.fontWeight
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                visible: pill.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.hovered ? pill.hoverFg : pill.fg
                font.family: Theme.font
                font.pixelSize: pill.fontSize
                font.weight: pill.fontWeight
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        property real wheel: 0
        onClicked: event => pill.clicked(event.button)
        // A touchpad sends many small deltas; a notch is 120.
        onWheel: event => {
            wheel += event.angleDelta.y;
            while (Math.abs(wheel) >= 120) {
                const step = wheel > 0 ? 1 : -1;
                wheel -= step * 120;
                pill.scrolled(step);
            }
        }
    }

    HoverTip {
        target: box
        text: pill.tip
        rich: pill.richTip
        hovered: mouse.containsMouse
    }
}
