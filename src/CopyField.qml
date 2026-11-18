import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A labelled, read-only value with a copy button. Stacked, the label sits
// above the value, which leaves the value more room on a narrow window.
GridLayout {
    id: field
    property string label
    property string value
    property bool secret: false
    property bool rotatable: false
    property bool stacked: false
    signal rotateRequested()

    columns: 3
    columnSpacing: 12
    rowSpacing: 4

    Label {
        text: field.label
        color: theme.dim
        font.pixelSize: 12
        elide: Text.ElideRight
        Layout.row: 0
        Layout.column: 0
        Layout.columnSpan: field.stacked ? 3 : 1
        Layout.fillWidth: field.stacked
        Layout.preferredWidth: 96
    }

    PlainField {
        Layout.row: field.stacked ? 1 : 0
        Layout.column: field.stacked ? 0 : 1
        Layout.columnSpan: field.stacked ? 2 : 1
        text: field.value
        readOnly: true
        secret: field.secret
        rotatable: field.rotatable
        Layout.fillWidth: true
        onRotateRequested: field.rotateRequested()
    }

    // A copy icon, which turns into a tick for a moment once copied.
    PlainButton {
        id: copyButton
        property bool copied: false
        icon: copied ? "M20 6L9 17l-5-5"
                     : "M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2z M4 16a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2"
        iconSize: 14
        Layout.row: field.stacked ? 1 : 0
        Layout.column: 2
        activeFocusOnTab: false
        implicitWidth: 32
        implicitHeight: 32
        onClicked: {
            backend.copy(field.value)
            copied = true
            reset.restart()
        }
        Timer { id: reset; interval: 1500; onTriggered: copyButton.copied = false }

        HoverHandler { id: copyHover }
        ToolTip.visible: copyHover.hovered
        ToolTip.delay: 600
        ToolTip.text: copyButton.copied ? qsTr("Copied") : qsTr("Copy")
    }
}
