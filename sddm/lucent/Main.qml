// The login screen, drawn by SDDM's Qt 6 greeter.
//
// Laid out like hyprlock.conf, so logging in and unlocking look like the same
// screen: the wallpaper dimmed, a large clock, the date, and one rounded field.
// The colours are Catppuccin Mocha Blue, install.sh's DEFAULT_THEME. They are
// fixed: the greeter runs as the sddm user before anyone has logged in, so
// there is no chosen theme to follow yet.
//
// Try it without logging out:
//     sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/lucent

import QtQuick

Rectangle {
    id: root
    width: 1280
    height: 800
    color: "#1e1e2e"

    readonly property color crust:    "#11111b"
    readonly property color surface0: "#313244"
    readonly property color overlay:  "#6c7086"
    readonly property color subtext:  "#a6adc8"
    readonly property color text:     "#cdd6f4"
    readonly property color accent:   "#74c7ec"
    readonly property color red:      "#f38ba8"
    readonly property string font:    "JetBrainsMono Nerd Font"

    property bool failed: false
    property bool busy: false

    // The uwsm session gives a proper systemd user session, which portals and
    // user units rely on; tuigreet was started with it for the same reason.
    // Plain Hyprland is the fallback when uwsm is not installed.
    property int sessionIndex: {
        for (var i = 0; i < sessionModel.rowCount(); i++) {
            var name = String(sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "")
            if (name.indexOf("uwsm") !== -1)
                return i
        }
        return sessionModel.lastIndex
    }

    // Last time's user. Before anyone has logged in there is none, and on a
    // machine with a single account that one is the answer, so a fresh
    // install opens straight on the password.
    function defaultUser() {
        if (userModel.lastUser !== "")
            return userModel.lastUser
        if (userModel.count === 1)
            return String(userModel.data(userModel.index(0, 0), Qt.UserRole + 1) || "")
        return ""
    }

    function login() {
        if (user.text === "" || busy)
            return
        busy = true
        failed = false
        sddm.login(user.text, password.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failed = true
            password.text = ""
            password.forceActiveFocus()
        }
        function onLoginSucceeded() {
            root.failed = false
        }
    }

    Image {
        anchors.fill: parent
        source: "background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle {
        anchors.fill: parent
        color: root.crust
        opacity: 0.45
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date()
            clock.text = Qt.formatTime(now, "HH:mm")
            date.text = Qt.formatDate(now, "dddd, d MMMM")
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -root.height * 0.05
        spacing: 14

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.text
            font.family: root.font
            font.weight: Font.ExtraBold
            font.pixelSize: Math.round(Math.min(root.height * 0.15, 150))
        }

        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.text
            font.family: root.font
            font.pixelSize: 26
            bottomPadding: 50
        }

        // The user. Last time's name is filled in, and it is a plain field
        // rather than a list, so a second account is typed in like anywhere
        // else. Enter moves on to the password.
        TextInput {
            id: user
            anchors.horizontalCenter: parent.horizontalCenter
            width: field.width
            horizontalAlignment: TextInput.AlignHCenter
            text: root.defaultUser()
            color: root.text
            selectionColor: root.surface0
            font.family: root.font
            font.pixelSize: 20
            KeyNavigation.tab: password
            onAccepted: password.forceActiveFocus()

            Text {
                anchors.centerIn: parent
                visible: user.text === ""
                text: "User name"
                color: root.subtext
                font: user.font
            }
        }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 380
            height: 58
            radius: 14
            color: root.surface0
            border.width: 2
            border.color: root.failed ? root.red : root.accent

            TextInput {
                id: password
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                color: root.text
                font.family: root.font
                font.pixelSize: 22
                font.letterSpacing: 4
                clip: true
                enabled: !root.busy
                KeyNavigation.backtab: user
                onTextEdited: root.failed = false
                onAccepted: root.login()
            }

            Text {
                anchors.centerIn: parent
                visible: password.text === "" && !root.busy
                text: root.failed ? "Wrong password" : "Enter password"
                color: root.failed ? root.red : root.subtext
                font.family: root.font
                font.pixelSize: 18
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Caps Lock is on"
            color: root.red
            opacity: keyboard.capsLock ? 1 : 0
            font.family: root.font
            font.pixelSize: 16
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28
        text: sddm.hostName
        color: root.subtext
        font.family: root.font
        font.pixelSize: 16
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: 30

        Repeater {
            model: [
                { label: "  Restart",   can: sddm.canReboot,   act: function () { sddm.reboot() } },
                { label: "  Shut down", can: sddm.canPowerOff, act: function () { sddm.powerOff() } }
            ]

            Text {
                visible: modelData.can
                text: modelData.label
                color: area.containsMouse ? root.text : root.subtext
                font.family: root.font
                font.pixelSize: 16

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.act()
                }
            }
        }
    }

    Component.onCompleted: {
        if (user.text === "")
            user.forceActiveFocus()
        else
            password.forceActiveFocus()
    }
}
