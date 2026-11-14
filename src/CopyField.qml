import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A labelled, read-only value with a copy button.
RowLayout {
    id: field
    property string label
    property string value

    spacing: 12

    Label {
        text: field.label
        color: "#9a9aa2"
        elide: Text.ElideRight
        Layout.preferredWidth: 110
    }

    TextField {
        text: field.value
        readOnly: true
        selectByMouse: true
        font.family: "monospace"
        Layout.fillWidth: true
    }

    Button {
        id: copyButton
        property bool copied: false
        text: copied ? qsTr("Copied") : qsTr("Copy")
        flat: true
        focusPolicy: Qt.NoFocus
        Layout.preferredWidth: 96
        onClicked: {
            backend.copy(field.value)
            copied = true
            reset.restart()
        }
        Timer { id: reset; interval: 1500; onTriggered: copyButton.copied = false }
    }
}
