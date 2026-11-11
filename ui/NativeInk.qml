// Writing with the pen at native speed, using xochitl's own pen pipeline: the
// ink appears as fast as in a notebook. Needs the rm-sdk xovi extension.
//
// xochitl draws strokes while they're written but doesn't give them to apps,
// so finished strokes come from the app's backend, which records them from
// the digitizer (backend/pen_strokes.h), through addScreenStroke(). This item
// then keeps and draws them, and the eraser end of the pen removes the strokes
// it crosses.
//
// On a PC, or without the extension, the mouse draws instead.
//
//   NativeInk {
//       id: ink
//       anchors.fill: parent
//       onStrokesEdited: save(ink.strokes)
//   }
//   // In the AppLoad endpoint's onMessageReceived, for the backend's strokes:
//   ink.addScreenStroke(stroke.points, stroke.eraser)
import QtQuick

Item {
    id: ink

    // Strokes, each a flat list of x, y coordinates in this item
    property var strokes: []
    property real lineWidth: 3
    // How close the eraser must pass to ink to erase it, in pixels
    property real eraserRadius: 20
    // Whether xochitl's native ink is in use, rather than the fallback
    readonly property bool isNative: nativeSurface !== null

    // After a stroke was added or erased, e.g. to save them
    signal strokesEdited()

    // Adds a stroke recorded by the backend, in screen pixels: a flat list of
    // x, y coordinates. Eraser strokes erase the ink they pass over. Strokes
    // starting outside this item, like pen taps on buttons, are ignored.
    function addScreenStroke(points, eraser) {
        const local = []
        for (let i = 0; i + 1 < points.length; i += 2) {
            const point = mapFromGlobal(points[i], points[i + 1])
            local.push(point.x, point.y)
        }
        addStroke(local, eraser)
    }

    function addStroke(points, eraser) {
        if (points.length < 2 || points[0] < 0 || points[1] < 0 || points[0] > width || points[1] > height) {
            return
        }
        if (eraser) {
            erase(points)
        } else {
            strokes = strokes.concat([points])
        }
        canvas.requestPaint()
        strokesEdited()
    }

    function clear() {
        strokes = []
        canvas.requestPaint()
        strokesEdited()
    }

    // Removes the points the eraser passed over, splitting strokes where cut
    function erase(eraserPoints) {
        const radius = eraserRadius * eraserRadius
        let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
        for (let j = 0; j + 1 < eraserPoints.length; j += 2) {
            left = Math.min(left, eraserPoints[j] - eraserRadius)
            right = Math.max(right, eraserPoints[j] + eraserRadius)
            top = Math.min(top, eraserPoints[j + 1] - eraserRadius)
            bottom = Math.max(bottom, eraserPoints[j + 1] + eraserRadius)
        }
        const erased = (x, y) => {
            if (x < left || x > right || y < top || y > bottom) {
                return false
            }
            for (let j = 0; j + 1 < eraserPoints.length; j += 2) {
                const dx = x - eraserPoints[j]
                const dy = y - eraserPoints[j + 1]
                if (dx * dx + dy * dy <= radius) {
                    return true
                }
            }
            return false
        }
        const result = []
        for (const stroke of strokes) {
            let piece = []
            let cut = false
            for (let i = 0; i + 1 < stroke.length; i += 2) {
                if (erased(stroke[i], stroke[i + 1])) {
                    cut = true
                    if (piece.length >= 4) {
                        result.push(piece)
                    }
                    piece = []
                } else {
                    piece.push(stroke[i], stroke[i + 1])
                }
            }
            // A single point left alone is a dot only if the stroke was one
            if (piece.length >= 4 || (!cut && piece.length >= 2)) {
                result.push(piece)
            }
        }
        strokes = result
    }

    onStrokesChanged: canvas.requestPaint()

    // Finished strokes
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "black"
            ctx.lineWidth = ink.lineWidth
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            for (const stroke of ink.strokes) {
                ctx.beginPath()
                ctx.moveTo(stroke[0], stroke[1])
                for (let i = 2; i + 1 < stroke.length; i += 2) {
                    ctx.lineTo(stroke[i], stroke[i + 1])
                }
                if (stroke.length === 2) {
                    ctx.lineTo(stroke[0] + 0.5, stroke[1] + 0.5)
                }
                ctx.stroke()
            }
            // The native ink stays on screen until something repaints it;
            // now the strokes are drawn here, it can go
            if (ink.nativeSurface) {
                Qt.callLater(() => { if (ink.nativeSurface) ink.nativeSurface.clearFramebuffer() })
            }
        }
    }

    // Native ink. xochitl's pen manager only routes the pen to surfaces on its
    // main window, so the surface goes there, over this item, while it's
    // visible, and is destroyed with it.
    property var nativeSurface: null
    property var nativeHandler: null
    property var penInputOwner: null

    function findPenInputOwner() {
        let top = ink
        while (top.parent) {
            top = top.parent
        }
        const queue = [top]
        while (queue.length > 0) {
            const item = queue.shift()
            if (item !== ink && ("penInput" in item) && item.penInput) {
                return item
            }
            for (const child of item.children) {
                queue.push(child)
            }
        }
        return null
    }

    function createNative() {
        if (nativeSurface || !visible || width <= 0 || height <= 0) {
            return
        }
        penInputOwner = penInputOwner || findPenInputOwner()
        if (!penInputOwner) {
            return
        }
        try {
            nativeHandler = Qt.createQmlObject(
                "import xofm.libs.devicesceneview; ScenePenInputHandler {}", ink)
            nativeHandler.sampleRate = penInputOwner.penInput.sampleRate
            nativeHandler.lineThickness = 2
            // xochitl's default eraser trace (2.4) roughly matches a 14 pixel radius
            nativeHandler.eraserThickness = 2.4 * eraserRadius / 14
            const transforms = Qt.createQmlObject("import RmSdk; import QtQml; QtObject { function identity() { return Transforms.identity() } }", ink)
            nativeSurface = Qt.createQmlObject("import com.remarkable; PenInputSurface {}", ink)
            nativeSurface.parent = penInputOwner
            nativeSurface.z = 100000
            nativeSurface.handler = nativeHandler
            nativeSurface.manager = penInputOwner.penInput.surfaceManager
            placeNative()
            const identity = transforms.identity()
            nativeSurface.setTransform(identity)
            nativeHandler.setTransform(identity, identity)
            penInputOwner.penInput.surfaceManager.registerInput(nativeSurface)
            transforms.destroy()
        } catch (error) {
            console.log("NativeInk: native ink unavailable, using the fallback:", error)
            destroyNative()
        }
    }

    function destroyNative() {
        if (nativeSurface) {
            nativeSurface.visible = false
            nativeSurface.destroy()
        }
        if (nativeHandler) {
            nativeHandler.destroy()
        }
        nativeSurface = null
        nativeHandler = null
        if (penInputOwner) {
            penInputOwner.penInput.surfaceManager.updateRegions()
        }
    }

    function placeNative() {
        if (!nativeSurface) {
            return
        }
        const position = ink.mapToItem(penInputOwner, 0, 0)
        if (nativeSurface.x !== position.x || nativeSurface.y !== position.y
                || nativeSurface.width !== ink.width || nativeSurface.height !== ink.height) {
            nativeSurface.x = position.x
            nativeSurface.y = position.y
            nativeSurface.width = ink.width
            nativeSurface.height = ink.height
            penInputOwner.penInput.surfaceManager.updateRegions()
        }
    }

    onVisibleChanged: visible ? createNative() : destroyNative()
    onWidthChanged: Qt.callLater(() => { createNative(); placeNative() })
    onHeightChanged: Qt.callLater(() => { createNative(); placeNative() })
    Component.onCompleted: Qt.callLater(createNative)
    Component.onDestruction: destroyNative()

    // Follows the item when the app's window moves, e.g. going fullscreen
    Timer {
        interval: 300
        repeat: true
        running: ink.nativeSurface !== null
        onTriggered: ink.placeNative()
    }

    // Fallback: the mouse draws, e.g. in appload-run
    MouseArea {
        anchors.fill: parent
        enabled: !ink.isNative
        property var points: []
        onPressed: mouse => points = [mouse.x, mouse.y]
        onPositionChanged: mouse => points.push(mouse.x, mouse.y)
        onReleased: {
            ink.addStroke(points, false)
            points = []
        }
    }
}
