import QtQuick
import QtQuick.Controls

// A section heading: a large title, as on Yeptes's overlays, and a line
// under it in a fainter, smaller hand, as in Yeptes's notes panel.
Column {
    id: heading
    property string title: ""
    property string detail: ""
    property color detailColor: theme.faint
    spacing: 1

    Label {
        width: heading.width
        text: heading.title
        color: theme.text
        font.pixelSize: 18
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    Label {
        width: heading.width
        visible: text !== ""
        text: heading.detail
        color: heading.detailColor
        font.family: "monospace"
        font.pixelSize: 10
        elide: Text.ElideRight
    }
}
