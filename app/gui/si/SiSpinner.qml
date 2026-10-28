import QtQuick
import QtQuick.Shapes
import StandIn 1.0

// A 2px accent arc that turns
Item {
    id: spinner

    property int size: 20
    property color color: Theme.accent

    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: spinner.color
            strokeWidth: Math.max(2, spinner.size / 16)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: spinner.size / 2
                centerY: spinner.size / 2
                radiusX: spinner.size / 2 - 2
                radiusY: spinner.size / 2 - 2
                startAngle: 0
                sweepAngle: 270
            }
        }

        RotationAnimator on rotation {
            running: spinner.visible
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }
}
