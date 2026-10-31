pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    anchors.fill: parent

    property real x1: 0
    property real y1: 0
    property real x2: 0
    property real y2: 0
    property color strokeColor: "red"
    property real strokeWidth: 3
    property bool showHead: true
    property bool dotted: false

    readonly property real _angle: Math.atan2(root.y2 - root.y1, root.x2 - root.x1)
    readonly property real _headLen: root.strokeWidth * 4
    readonly property real _headAngle: Math.PI / 7
    readonly property real _head1X: root.x2 - root._headLen * Math.cos(root._angle - root._headAngle)
    readonly property real _head1Y: root.y2 - root._headLen * Math.sin(root._angle - root._headAngle)
    readonly property real _head2X: root.x2 - root._headLen * Math.cos(root._angle + root._headAngle)
    readonly property real _head2Y: root.y2 - root._headLen * Math.sin(root._angle + root._headAngle)

    // Back notch of the head triangle — the midpoint between the two barbs.
    // The shaft stops here instead of at the tip, so it sits fully behind
    // the head instead of poking a round-cap bulge past it.
    readonly property real _notchX: (root._head1X + root._head2X) / 2
    readonly property real _notchY: (root._head1Y + root._head2Y) / 2
    readonly property real _shaftEndX: root.showHead ? root._notchX : root.x2
    readonly property real _shaftEndY: root.showHead ? root._notchY : root.y2

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            strokeStyle: root.dotted ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: root.dotted ? [2, 3] : []
            startX: root.x1; startY: root.y1
            PathLine { x: root._shaftEndX; y: root._shaftEndY }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.showHead ? root.strokeColor : "transparent"
            startX: root._head1X; startY: root._head1Y
            PathLine { x: root.x2; y: root.y2 }
            PathLine { x: root._head2X; y: root._head2Y }
            PathLine { x: root._head1X; y: root._head1Y }
        }
    }
}
