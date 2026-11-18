import QtQuick
import QtQuick.Shapes

// A line icon: SVG path data on a 24px grid, stroked in one color and drawn
// at any size (paths from Lucide, ISC license).
Item {
    id: icon
    property string path: ""
    property color color: theme.subtext
    implicitWidth: 12
    implicitHeight: 12

    Shape {
        width: 24
        height: 24
        scale: icon.width / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: icon.color
            strokeWidth: 2.2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.path }
        }
    }
}
