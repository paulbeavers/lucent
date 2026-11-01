// A tooltip for whatever item it is placed in: shown half a second after
// `hovered` turns true, gone the moment it turns false.
//
// It opens outside the bar, just past the edge away from the screen's edge,
// rather than against the item: anchored to the item, a tip in the 58px panel
// would sit over the panel itself.

import QtQuick
import Quickshell

Item {
    id: tip

    property Item target: parent
    property string text: ""
    property bool rich: false
    property bool hovered: false
    // Which way it opens: below a bar at the top, above one at the bottom.
    property bool below: Settings.barAtTop

    property bool shown: false
    property rect at: Qt.rect(0, 0, 0, 0)

    onHoveredChanged: {
        if (hovered && text !== "") {
            delay.restart();
        } else {
            delay.stop();
            shown = false;
        }
    }

    Timer {
        id: delay
        interval: 500
        onTriggered: {
            const win = tip.target.QsWindow.window;
            if (!win)
                return;
            const p = tip.target.mapToItem(null, 0, 0);
            tip.at = Qt.rect(p.x, tip.below ? win.height : 0, tip.target.width, 0);
            tip.shown = true;
        }
    }

    LazyLoader {
        active: tip.shown

        PopupWindow {
            visible: true
            anchor.window: tip.target.QsWindow.window
            anchor.rect.x: tip.at.x
            anchor.rect.y: tip.at.y
            anchor.rect.width: tip.at.width
            anchor.rect.height: 1
            anchor.edges: tip.below ? Edges.Bottom : Edges.Top
            anchor.gravity: tip.below ? Edges.Bottom : Edges.Top
            anchor.adjustment: PopupAdjustment.Slide
            color: "transparent"
            implicitWidth: label.implicitWidth + 20
            implicitHeight: label.implicitHeight + 14

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: tip.below ? 4 : 0
                anchors.bottomMargin: tip.below ? 0 : 4
                radius: 8
                color: Theme.c("mantle")
                border.width: 1
                border.color: Theme.c("surface0")

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: tip.text
                    textFormat: tip.rich ? Text.RichText : Text.PlainText
                    color: Theme.c("text")
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }
        }
    }
}
