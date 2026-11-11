import QtQuick
import net.asivery.AppLoad 1.0

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    // Must match backend/main.cpp
    readonly property int msgSave: 1
    readonly property int msgState: 100

    property string tab: "life"

    // Life counters
    property int playerCount: 2
    property int startingLife: 20
    // 100 for games with life in the thousands, like Yu-Gi-Oh: taps then count by 100
    property int lifeScale: 1
    readonly property var startingLives: lifeScale === 1 ? [20, 25, 30, 40] : [4000, 8000, 10000, 16000]
    readonly property bool gameInProgress: lives.some(life => life !== startingLife)
        || counters.some(playerCounters => playerCounters.some(value => value !== 0))
    property var lives: [20, 20]
    property var counters: [[0, 0, 0, 0], [0, 0, 0, 0]] // 4 small counters per player
    property var lifeHistory: [[20], [20]]                // life totals per player, oldest first

    // Dice
    readonly property var dice: [
        { name: "Coin", sides: 2 }, { name: "d4", sides: 4 }, { name: "d6", sides: 6 }, { name: "d8", sides: 8 },
        { name: "d10", sides: 10 }, { name: "d12", sides: 12 }, { name: "d20", sides: 20 }, { name: "d100", sides: 100 }
    ]
    property int diceCount: 1
    property var lastRoll: null     // { name, values, text }
    property var history: []        // descriptions of previous rolls, newest first
    property int rollNumber: 0      // shown with each roll, so rolling the same result again visibly changes the screen

    // Free-hand notes
    property bool notesOpen: false
    property var notes: []          // strokes, each a flat list of x, y coordinates

    // Called by AppLoad when the app is closed; stops the backend
    function unloading() {
        backend.terminate()
    }

    function resetLives() {
        const reset = []
        for (let i = 0; i < playerCount; i++) {
            reset.push(startingLife)
        }
        lives = reset
        counters = reset.map(() => [0, 0, 0, 0])
        lifeHistory = reset.map(life => [life])
        save()
    }

    function changeCounter(player, counter, delta) {
        const updated = counters.map(playerCounters => playerCounters.slice())
        updated[player][counter] += delta
        counters = updated
        save()
    }

    // Changes made in quick succession make a single history entry: with merge,
    // the last entry is updated instead of adding one. Returns whether the
    // change left an entry to merge into.
    function changeLife(player, delta, merge) {
        const updated = lives.slice()
        updated[player] += delta
        lives = updated

        const history = lifeHistory.map(totals => totals.slice())
        const totals = history[player]
        if (merge && totals.length > 1) {
            totals[totals.length - 1] = updated[player]
        } else {
            totals.push(updated[player])
        }
        // Changes that cancel out leave no trace
        let hasEntry = true
        if (totals.length > 1 && totals[totals.length - 1] === totals[totals.length - 2]) {
            totals.pop()
            hasEntry = false
        }
        history[player] = totals.slice(-200)
        lifeHistory = history
        save()
        return hasEntry
    }

    function roll(die) {
        const values = []
        for (let i = 0; i < diceCount; i++) {
            values.push(Math.floor(Math.random() * die.sides) + 1)
        }
        let text
        if (die.sides === 2) {
            const faces = values.map(value => value === 1 ? "Heads" : "Tails")
            text = faces.join(", ")
        } else if (values.length > 1) {
            text = values.join(" + ") + " = " + values.reduce((a, b) => a + b, 0)
        } else {
            text = String(values[0])
        }
        if (lastRoll !== null) {
            history = [lastRoll.label + ": " + lastRoll.text].concat(history).slice(0, 12)
        }
        rollNumber++
        lastRoll = {
            label: (values.length > 1 ? values.length + " × " : "") + die.name,
            values: values,
            coin: die.sides === 2,
            text: text
        }
        save()
    }

    // Saves a moment after the last change, not on every tap
    function save() {
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: backend.sendMessage(root.msgSave, JSON.stringify({
            tab: root.tab,
            playerCount: root.playerCount,
            startingLife: root.startingLife,
            lifeScale: root.lifeScale,
            lives: root.lives,
            counters: root.counters,
            lifeHistory: root.lifeHistory,
            diceCount: root.diceCount,
            lastRoll: root.lastRoll,
            history: root.history,
            rollNumber: root.rollNumber,
            notes: root.notes
        }))
    }

    AppLoad {
        id: backend
        applicationID: "dice"
        onMessageReceived: (type, contents) => {
            if (type !== root.msgState) {
                return
            }
            const state = JSON.parse(contents)
            if (state.lives && state.lives.length === state.playerCount) {
                root.playerCount = state.playerCount
                root.startingLife = state.startingLife
                root.lifeScale = state.lifeScale || 1
                root.lives = state.lives
                root.counters = state.counters && state.counters.length === state.playerCount
                    ? state.counters : state.lives.map(() => [0, 0, 0, 0])
                root.lifeHistory = state.lifeHistory && state.lifeHistory.length === state.playerCount
                    ? state.lifeHistory : state.lives.map(life => [life])
            }
            if (state.tab) {
                root.tab = state.tab
            }
            if (state.diceCount) {
                root.diceCount = state.diceCount
            }
            root.lastRoll = state.lastRoll || null
            root.history = state.history || []
            root.rollNumber = state.rollNumber || 0
            root.notes = state.notes || []
        }
    }

    // Tabs
    Row {
        id: tabs
        anchors {
            top: parent.top
            topMargin: 16
            horizontalCenter: parent.horizontalCenter
        }
        height: 80
        spacing: 16
        Button {
            width: 300
            text: "Life"
            fontSize: 36
            checked: root.tab === "life"
            onClicked: { root.tab = "life"; root.save() }
        }
        Button {
            width: 300
            text: "Dice"
            fontSize: 36
            checked: root.tab === "dice"
            onClicked: { root.tab = "dice"; root.save() }
        }
    }

    Button {
        anchors {
            top: parent.top
            topMargin: 16
            left: parent.left
            leftMargin: 16
        }
        width: 130
        height: 80
        text: "Notes"
        fontSize: 34
        onClicked: {
            root.notesOpen = true
            notesCanvas.redrawAll()
        }
    }

    // Switches between counting life by 1 and by 100
    Button {
        id: scaleButton
        anchors {
            top: parent.top
            topMargin: 16
            right: parent.right
            rightMargin: 16
        }
        width: 130
        height: 80
        visible: root.tab === "life"
        // Switching resets the lives, so ask again during a game
        property bool confirming: false
        text: confirming ? "Sure?" : "×100"
        fontSize: 34
        checked: root.lifeScale === 100 !== confirming
        onClicked: {
            if (root.gameInProgress && !confirming) {
                confirming = true
                scaleConfirmTimer.restart()
                return
            }
            confirming = false
            root.lifeScale = root.lifeScale === 1 ? 100 : 1
            root.startingLife = root.lifeScale === 1 ? 20 : 8000
            root.resetLives()
        }
        Timer {
            id: scaleConfirmTimer
            interval: 3000
            onTriggered: scaleButton.confirming = false
        }
    }

    // Life counters
    Item {
        id: lifeView
        anchors {
            top: tabs.bottom
            topMargin: 16
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 16
        }
        visible: root.tab === "life"

        Row {
            id: lifeSettings
            height: 64
            spacing: 10

            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "Players"
                font.pixelSize: 26
            }
            Repeater {
                model: [1, 2, 3, 4]
                delegate: Button {
                    width: 60
                    text: modelData
                    checked: root.playerCount === modelData
                    onClicked: {
                        root.playerCount = modelData
                        root.resetLives()
                    }
                }
            }
            Item { width: 14; height: 1 }
            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "Life"
                font.pixelSize: 26
            }
            Repeater {
                model: root.startingLives
                delegate: Button {
                    width: 70
                    text: modelData >= 1000 ? modelData / 1000 + "k" : modelData
                    checked: root.startingLife === modelData
                    onClicked: {
                        root.startingLife = modelData
                        root.resetLives()
                    }
                }
            }
            Item { width: 14; height: 1 }
            Button {
                id: resetButton
                // Ask again before throwing away a game in progress
                property bool confirming: false
                width: 120
                text: confirming ? "Sure?" : "Reset"
                checked: confirming
                onClicked: {
                    if (confirming) {
                        confirming = false
                        root.resetLives()
                    } else {
                        confirming = true
                        confirmTimer.restart()
                    }
                }
                Timer {
                    id: confirmTimer
                    interval: 3000
                    onTriggered: resetButton.confirming = false
                }
            }
        }

        // Players across the table face the other way: the top row is upside down
        Item {
            id: players
            anchors {
                top: lifeSettings.bottom
                topMargin: 16
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            readonly property int topCount: root.playerCount === 1 ? 0 : root.playerCount === 4 ? 2 : 1
            readonly property int bottomCount: root.playerCount - topCount
            readonly property real rowHeight: (height - (topCount ? spacing : 0)) / (topCount ? 2 : 1)
            readonly property real spacing: 16

            Repeater {
                model: root.playerCount
                delegate: PlayerPanel {
                    readonly property bool onTop: index < players.topCount
                    readonly property int column: onTop ? index : index - players.topCount
                    readonly property int columns: onTop ? players.topCount : players.bottomCount
                    x: column * (players.width + players.spacing) / columns
                    y: onTop ? 0 : players.height - players.rowHeight
                    width: (players.width + players.spacing) / columns - players.spacing
                    height: players.rowHeight
                    upsideDown: onTop
                    player: index
                }
            }
        }
    }

    // Dice
    Column {
        id: diceView
        anchors {
            top: tabs.bottom
            topMargin: 24
            left: parent.left
            right: parent.right
            margins: 16
        }
        spacing: 20
        visible: root.tab === "dice"

        Row {
            height: 64
            spacing: 10
            Text {
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "How many"
                font.pixelSize: 26
            }
            Repeater {
                model: [1, 2, 3, 4, 5]
                delegate: Button {
                    width: 70
                    text: modelData
                    checked: root.diceCount === modelData
                    onClicked: { root.diceCount = modelData; root.save() }
                }
            }
        }

        Grid {
            id: diceGrid
            columns: 4
            spacing: 16
            readonly property real keyWidth: (diceView.width - 3 * spacing) / 4
            Repeater {
                model: root.dice
                delegate: Button {
                    width: diceGrid.keyWidth
                    height: 140
                    text: modelData.name
                    fontSize: 44
                    onClicked: root.roll(modelData)
                }
            }
        }

        // Result of the last roll
        Rectangle {
            width: parent.width
            height: 420
            border.width: 3
            radius: 12

            Text {
                anchors {
                    top: parent.top
                    left: parent.left
                    margins: 16
                }
                text: root.lastRoll ? root.lastRoll.label : "Tap a die to roll"
                font.pixelSize: 32
            }
            Text {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 16
                }
                visible: root.lastRoll !== null
                text: "#" + root.rollNumber
                font.pixelSize: 28
                color: "#606060"
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.lastRoll && root.lastRoll.values.length > 1 ? -30 : 10
                visible: root.lastRoll !== null
                text: {
                    if (!root.lastRoll) {
                        return ""
                    }
                    if (root.lastRoll.coin) {
                        return root.lastRoll.values.length === 1 ? root.lastRoll.text
                            : root.lastRoll.values.filter(v => v === 1).length + " heads"
                    }
                    return String(root.lastRoll.values.reduce((a, b) => a + b, 0))
                }
                font.pixelSize: root.lastRoll && root.lastRoll.coin ? 110 : 200
                font.bold: true
            }
            // The individual dice, when rolling several
            Text {
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 24
                    horizontalCenter: parent.horizontalCenter
                }
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.lastRoll !== null && root.lastRoll.values.length > 1
                text: root.lastRoll ? root.lastRoll.text : ""
                font.pixelSize: 36
            }
        }

        Text {
            visible: root.history.length > 0
            text: "Previous rolls"
            font.pixelSize: 28
            font.bold: true
        }
        Repeater {
            model: root.history.slice(0, 8)
            delegate: Text {
                text: modelData
                font.pixelSize: 26
                elide: Text.ElideRight
                width: diceView.width
            }
        }
    }

    // A blank page to write on with the pen, over everything else
    Rectangle {
        id: notesPage
        anchors.fill: parent
        z: 100
        visible: root.notesOpen
        color: "white"

        // Nothing below reacts while the page is open
        MouseArea {
            anchors.fill: parent
        }

        Button {
            anchors {
                top: parent.top
                topMargin: 16
                left: parent.left
                leftMargin: 16
            }
            width: 130
            height: 80
            text: "Back"
            fontSize: 34
            onClicked: root.notesOpen = false
        }
        Button {
            id: clearNotesButton
            anchors {
                top: parent.top
                topMargin: 16
                right: parent.right
                rightMargin: 16
            }
            width: 130
            height: 80
            property bool confirming: false
            text: confirming ? "Sure?" : "Clear"
            fontSize: 34
            checked: confirming
            onClicked: {
                if (!confirming) {
                    confirming = true
                    clearNotesTimer.restart()
                    return
                }
                confirming = false
                root.notes = []
                root.save()
                notesCanvas.redrawAll()
            }
            Timer {
                id: clearNotesTimer
                interval: 3000
                onTriggered: clearNotesButton.confirming = false
            }
        }

        Rectangle {
            anchors {
                top: parent.top
                topMargin: 112
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 16
            }
            border.width: 3
            radius: 12

            Canvas {
                id: notesCanvas
                anchors.fill: parent
                anchors.margins: 4

                property var current: null       // the stroke being drawn
                property var pendingSegments: []
                property bool pendingRedraw: false

                function redrawAll() {
                    pendingRedraw = true
                    pendingSegments = []
                    requestPaint()
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.strokeStyle = "black"
                    ctx.lineWidth = 4
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    if (pendingRedraw) {
                        ctx.clearRect(0, 0, width, height)
                        for (const stroke of root.notes) {
                            ctx.beginPath()
                            ctx.moveTo(stroke[0], stroke[1])
                            for (let i = 2; i < stroke.length; i += 2) {
                                ctx.lineTo(stroke[i], stroke[i + 1])
                            }
                            if (stroke.length === 2) {
                                ctx.lineTo(stroke[0] + 0.5, stroke[1] + 0.5)
                            }
                            ctx.stroke()
                        }
                        pendingRedraw = false
                    }
                    for (const segment of pendingSegments) {
                        ctx.beginPath()
                        ctx.moveTo(segment[0], segment[1])
                        ctx.lineTo(segment[2], segment[3])
                        ctx.stroke()
                    }
                    pendingSegments = []
                }

                // Only the pen writes: it arrives as plain mouse events, while
                // touches are synthesized ones, so a resting palm leaves no marks
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    onPressed: mouse => {
                        if (mouse.source !== Qt.MouseEventNotSynthesized) {
                            mouse.accepted = false
                            return
                        }
                        notesCanvas.current = [Math.round(mouse.x), Math.round(mouse.y)]
                    }
                    onPositionChanged: mouse => {
                        const stroke = notesCanvas.current
                        if (!stroke) {
                            return
                        }
                        const x = Math.round(mouse.x)
                        const y = Math.round(mouse.y)
                        const lastX = stroke[stroke.length - 2]
                        const lastY = stroke[stroke.length - 1]
                        if (x === lastX && y === lastY) {
                            return
                        }
                        stroke.push(x, y)
                        notesCanvas.pendingSegments.push([lastX, lastY, x, y])
                        notesCanvas.markDirty(Qt.rect(Math.min(lastX, x) - 4, Math.min(lastY, y) - 4,
                                                      Math.abs(lastX - x) + 8, Math.abs(lastY - y) + 8))
                    }
                    onReleased: {
                        if (notesCanvas.current) {
                            root.notes = root.notes.concat([notesCanvas.current])
                            notesCanvas.current = null
                            root.save()
                        }
                    }
                    onCanceled: notesCanvas.current = null
                }
            }
        }
    }

    component PlayerPanel: Item {
        id: panel
        property int player
        property bool upsideDown: false
        property int recentChange: 0   // shown for a moment, to see what a series of taps added up to
        property bool recentEntry: false // whether the current series of taps has a history entry

        function change(delta) {
            const merge = recentTimer.running && recentEntry
            recentEntry = root.changeLife(player, delta, merge)
            recentChange += delta
            recentTimer.restart()
        }

        Timer {
            id: recentTimer
            interval: 2500
            onTriggered: panel.recentChange = 0
        }

        Rectangle {
            anchors.fill: parent
            rotation: panel.upsideDown ? 180 : 0
            border.width: 4
            radius: 16

            readonly property real lifeSize: Math.min(width * 0.32, height * 0.36)
            readonly property real historyWidth: root.lifeScale === 1 ? 46 : 74
            // The life total sits above the small counters
            readonly property real lifeOffset: -height * 0.14

            Text {
                anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                    topMargin: 12
                }
                text: "Player " + (panel.player + 1)
                font.pixelSize: 26
            }
            Text {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 12
                }
                visible: panel.recentChange !== 0
                text: (panel.recentChange > 0 ? "+" : "−") + Math.abs(panel.recentChange)
                font.pixelSize: 34
                font.bold: true
            }

            // Tap the left half to lose life, the right half to gain it
            Text {
                anchors {
                    left: parent.left
                    leftMargin: parent.historyWidth + 20
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: parent.lifeOffset
                }
                text: "−"
                font.pixelSize: parent.lifeSize * 0.5
                color: "#808080"
            }
            Text {
                anchors {
                    right: parent.right
                    rightMargin: parent.width * 0.06
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: parent.lifeOffset
                }
                text: "+"
                font.pixelSize: parent.lifeSize * 0.5
                color: "#808080"
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: parent.lifeOffset
                anchors.horizontalCenterOffset: parent.historyWidth / 2
                // Shrinks to fit totals in the thousands between the − and +
                width: parent.width * 0.64 - parent.historyWidth
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 24
                text: root.lives[panel.player] ?? ""
                font.pixelSize: parent.lifeSize
                font.bold: true
            }
            TapHandler {
                onTapped: (point) => panel.change((point.position.x < parent.width / 2 ? -1 : 1) * root.lifeScale)
            }

            // Life history, newest at the bottom; the oldest scroll off the top
            Item {
                anchors {
                    top: parent.top
                    topMargin: 52
                    bottom: lifeButtons.top
                    bottomMargin: 12
                    left: parent.left
                    leftMargin: 12
                }
                width: parent.historyWidth
                clip: true
                Column {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    Repeater {
                        model: root.lifeHistory[panel.player] || []
                        delegate: Text {
                            width: parent.width
                            text: modelData
                            font.pixelSize: 20
                            color: "#505050"
                        }
                    }
                }
            }

            // Small counters, for poison, commander damage and such
            Row {
                id: smallCounters
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 12
                    horizontalCenter: parent.horizontalCenter
                }
                readonly property real counterWidth: Math.min(96, (parent.width - 40) / 4 - spacing)
                spacing: Math.min(28, parent.width * 0.04)
                Repeater {
                    model: 4
                    delegate: Column {
                        id: counter
                        required property int index
                        readonly property int value: (root.counters[panel.player] || [])[index] ?? 0
                        spacing: 4
                        Button {
                            width: parent.parent.counterWidth
                            height: 48
                            text: "+"
                            onClicked: root.changeCounter(panel.player, counter.index, 1)
                        }
                        Text {
                            width: parent.parent.counterWidth
                            horizontalAlignment: Text.AlignHCenter
                            text: counter.value < 0 ? "−" + -counter.value : counter.value
                            font.pixelSize: 40
                            font.bold: counter.value !== 0
                            color: counter.value !== 0 ? "black" : "#909090"
                            // Taps between the buttons shouldn't change the life total
                            TapHandler {
                                gesturePolicy: TapHandler.WithinBounds
                            }
                        }
                        Button {
                            width: parent.parent.counterWidth
                            height: 48
                            text: "−"
                            onClicked: root.changeCounter(panel.player, counter.index, -1)
                        }
                    }
                }
            }

            Row {
                id: lifeButtons
                anchors {
                    bottom: smallCounters.top
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: 16
                }
                height: Math.min(64, parent.height * 0.18)
                spacing: 16
                Button {
                    width: root.lifeScale === 1 ? 90 : 120
                    text: "−" + 5 * root.lifeScale
                    onClicked: panel.change(-5 * root.lifeScale)
                }
                Button {
                    width: root.lifeScale === 1 ? 90 : 120
                    text: "+" + 5 * root.lifeScale
                    onClicked: panel.change(5 * root.lifeScale)
                }
            }
        }
    }

    component Button: Rectangle {
        id: button
        property string text
        property bool checked: false
        property int fontSize: 28
        signal clicked()

        height: parent.height
        radius: 8
        border.width: 3
        color: checked ? "black" : "white"

        Text {
            anchors.centerIn: parent
            text: button.text
            font.pixelSize: button.fontSize
            color: button.checked ? "white" : "black"
        }
        TapHandler {
            // Takes the tap for itself, so the player panel around a button doesn't also count it
            gesturePolicy: TapHandler.WithinBounds
            onTapped: button.clicked()
        }
    }
}
