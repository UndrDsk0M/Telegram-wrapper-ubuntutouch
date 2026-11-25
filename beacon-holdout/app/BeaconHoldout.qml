import QtQuick 2.4
import QtMultimedia 5.0
import "World.js" as World
import "View.js" as View

Rectangle {
    id: game
    width: 800
    height: 450
    color: "#11100d"
    focus: true

    property var runState: World.newGame()
    property string phase: "ready"
    property int hp: 100
    property int ammo: 10
    property int reserve: 70
    property int wave: 0
    property int score: 0
    property int alive: 0
    property bool loading: false
    property bool muted: false
    property bool paused: false
    property bool tapShot: false
    property bool fireHeld: false
    property bool reloadTap: false
    property real turn: 0
    property real forward: 0
    property real strafe: 0
    property real lastFrame: 0
    property var touches: ({})
    property var keys: ({})
    readonly property real scaleFactor: Math.max(0.62, Math.min(width / 800, height / 450))
    readonly property color paper: "#f4e6c9"
    readonly property color mutedPaper: "#b8ac90"
    readonly property color amber: "#dfa166"

    function resetControls() {
        touches = {}
        keys = {}
        turn = 0
        forward = 0
        strafe = 0
        tapShot = false
        fireHeld = false
        reloadTap = false
    }

    function startRun() {
        runState = World.newGame()
        World.begin(runState)
        paused = false
        resetControls()
        updateDisplay()
        forceActiveFocus()
        lastFrame = Date.now()
        worldView.requestPaint()
    }

    function pauseRun() {
        if (phase !== "playing")
            return
        paused = true
        resetControls()
    }

    function resumeRun() {
        paused = false
        lastFrame = Date.now()
        forceActiveFocus()
    }

    function updateDisplay() {
        phase = runState.phase
        hp = runState.health
        ammo = runState.ammo
        reserve = runState.reserve
        wave = runState.wave
        score = runState.score
        alive = runState.enemies.length + runState.remaining
        loading = runState.reloading > 0
    }

    function pointIn(point, zone) {
        return point.x >= zone.x && point.x <= zone.x + zone.width &&
               point.y >= zone.y && point.y <= zone.y + zone.height
    }

    function hasRole(role) {
        for (var id in touches) {
            if (touches[id].role === role)
                return true
        }
        return false
    }

    function pressPoints(points) {
        for (var i = 0; i < points.length; i++) {
            var p = points[i]
            if (touches[p.pointId])
                continue
            if (pointIn(p, pauseButton)) {
                pauseRun()
                return
            }
            var role = "idle"
            if (pointIn(p, fireButton) && !hasRole("fire")) {
                role = "fire"
                fireHeld = true
                tapShot = true
            } else if (pointIn(p, reloadButton)) {
                role = "reload"
                reloadTap = true
            } else if (p.x < width * 0.47 && !hasRole("move")) {
                role = "move"
            } else if (p.x >= width * 0.47 && !hasRole("look")) {
                role = "look"
            }
            touches[p.pointId] = { role: role, startX: p.x, startY: p.y, x: p.x }
        }
    }

    function updatePoints(points) {
        for (var i = 0; i < points.length; i++) {
            var p = points[i]
            var state = touches[p.pointId]
            if (!state)
                continue
            if (state.role === "move") {
                var radius = 51 * scaleFactor
                var dx = (p.x - state.startX) / radius
                var dy = (p.y - state.startY) / radius
                var distance = Math.sqrt(dx * dx + dy * dy)
                if (distance < 0.10) {
                    forward = 0
                    strafe = 0
                } else {
                    forward = -dy / Math.max(1, distance)
                    strafe = dx / Math.max(1, distance)
                }
            } else if (state.role === "look" || (state.role === "fire" && !hasRole("look"))) {
                turn += (p.x - state.x) * 0.005 / scaleFactor
                state.x = p.x
            }
        }
    }

    function releasePoints(points) {
        for (var i = 0; i < points.length; i++) {
            var id = points[i].pointId
            var state = touches[id]
            if (!state)
                continue
            if (state.role === "move") {
                forward = 0
                strafe = 0
            } else if (state.role === "fire") {
                fireHeld = false
            }
            delete touches[id]
        }
    }

    function tick(delta) {
        var oldShot = runState.shotEvent
        var oldWave = runState.waveEvent
        var input = {
            forward: forward + (keys[Qt.Key_W] ? 1 : 0) - (keys[Qt.Key_S] ? 1 : 0),
            strafe: strafe + (keys[Qt.Key_D] ? 1 : 0) - (keys[Qt.Key_A] ? 1 : 0),
            turn: turn + delta * 2.3 * ((keys[Qt.Key_Right] ? 1 : 0) - (keys[Qt.Key_Left] ? 1 : 0)),
            fire: fireHeld || tapShot || !!keys[Qt.Key_Space],
            reload: reloadTap || !!keys[Qt.Key_R]
        }
        turn = 0
        tapShot = false
        reloadTap = false
        World.advance(runState, delta, input)
        if (!muted) {
            if (runState.shotEvent !== oldShot)
                shot.play()
            if (runState.waveEvent !== oldWave)
                waveSound.play()
        }
        updateDisplay()
        worldView.requestPaint()
    }

    Keys.onPressed: {
        if (event.key === Qt.Key_Escape) {
            if (paused)
                resumeRun()
            else
                pauseRun()
            event.accepted = true
        } else if (!paused && phase === "playing") {
            keys[event.key] = true
            event.accepted = true
        }
    }
    Keys.onReleased: {
        if (!event.isAutoRepeat)
            delete keys[event.key]
    }

    Timer {
        interval: 34
        repeat: true
        running: !paused && phase === "playing"
        onTriggered: {
            var now = Date.now()
            var delta = (now - lastFrame) / 1000
            lastFrame = now
            game.tick(delta)
        }
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state !== Qt.ApplicationActive)
                game.pauseRun()
        }
    }

    SoundEffect { id: shot; source: "shot.wav"; volume: 0.54 }
    SoundEffect { id: waveSound; source: "wave.wav"; volume: 0.5 }

    Canvas {
        id: worldView
        width: 320
        height: 180
        anchors.centerIn: parent
        scale: Math.min(game.width / width, game.height / height)
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onPaint: View.paint(getContext("2d"), width, height, game.runState)
        onAvailableChanged: if (available) requestPaint()
    }

    MultiPointTouchArea {
        anchors.fill: parent
        z: 1
        enabled: phase === "playing" && !paused
        minimumTouchPoints: 1
        maximumTouchPoints: 5
        mouseEnabled: true
        onPressed: game.pressPoints(touchPoints)
        onUpdated: game.updatePoints(touchPoints)
        onReleased: game.releasePoints(touchPoints)
        onCanceled: game.releasePoints(touchPoints)
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 61 * scaleFactor
        visible: phase === "playing" && !paused
        z: 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#e8191711" }
            GradientStop { position: 1.0; color: "#00191711" }
        }
    }

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 13 * scaleFactor
        spacing: 4 * scaleFactor
        visible: phase === "playing" && !paused
        z: 3
        Text {
            text: "HEALTH " + game.hp
            color: game.paper
            font.bold: true
            font.pixelSize: 13 * scaleFactor
        }
        Rectangle {
            width: 106 * scaleFactor
            height: 5 * scaleFactor
            color: "#4d4535"
            Rectangle {
                width: parent.width * game.hp / 100
                height: parent.height
                color: game.hp > 30 ? "#b7ad75" : "#d36a50"
            }
        }
    }

    Column {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 10 * scaleFactor
        spacing: 2 * scaleFactor
        visible: phase === "playing" && !paused
        z: 3
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: game.alive === 0 ? (game.wave === 0 ? "SIGNAL LOST" : "WAVE CLEAR") : "WAVE " + game.wave + " / " + World.maxWaves
            color: game.amber
            font.bold: true
            font.pixelSize: 20 * scaleFactor
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: game.alive > 0 ? game.alive + " remaining  ·  " + game.score + " pts" : game.score + " pts"
            color: game.paper
            font.pixelSize: 12 * scaleFactor
        }
    }

    ActionTile {
        id: pauseButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12 * scaleFactor
        width: 78 * scaleFactor
        height: 38 * scaleFactor
        sizing: scaleFactor
        label: "Pause"
        z: 4
        visible: phase === "playing" && !paused
        onActivated: game.pauseRun()
    }

    Rectangle {
        width: 116 * scaleFactor
        height: width
        radius: width / 2
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 20 * scaleFactor
        z: 3
        visible: phase === "playing" && !paused
        color: "#70231f16"
        border.color: "#938366"
        border.width: 1

        Rectangle {
            width: 36 * scaleFactor
            height: width
            radius: width / 2
            x: (parent.width - width) / 2 + strafe * 30 * scaleFactor
            y: (parent.height - height) / 2 - forward * 30 * scaleFactor
            color: "#a8b3a17e"
            border.color: "#b9a984"
        }
    }

    Rectangle {
        id: fireButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 19 * scaleFactor
        width: 91 * scaleFactor
        height: width
        radius: width / 2
        z: 3
        visible: phase === "playing" && !paused
        color: game.fireHeld ? "#c28660" : "#a4402d20"
        border.width: 2
        border.color: "#e3a675"
        Text {
            anchors.centerIn: parent
            text: "FIRE"
            color: game.paper
            font.bold: true
            font.pixelSize: 16 * scaleFactor
        }
    }

    Rectangle {
        id: reloadButton
        anchors.right: fireButton.left
        anchors.rightMargin: 12 * scaleFactor
        anchors.bottom: fireButton.bottom
        width: 91 * scaleFactor
        height: 48 * scaleFactor
        z: 3
        visible: phase === "playing" && !paused
        radius: 4 * scaleFactor
        color: "#b9262217"
        border.color: "#8a7959"
        Text {
            anchors.centerIn: parent
            text: game.loading ? "Loading…" : game.ammo + " / " + game.reserve
            color: game.paper
            font.bold: true
            font.pixelSize: 14 * scaleFactor
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#bb15130e"
        z: 5
        visible: phase !== "playing" || paused

        Column {
            anchors.centerIn: parent
            width: Math.min(game.width * 0.86, 540 * scaleFactor)
            spacing: 14 * scaleFactor

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 55 * scaleFactor
                height: 3 * scaleFactor
                color: game.amber
            }
            Text {
                width: parent.width
                text: game.paused ? "HOLD FIRE" : game.phase === "defeat" ? "THE BUNKER FELL" :
                      game.phase === "victory" ? "SIGNAL RESTORED" : "BEACON HOLDOUT"
                horizontalAlignment: Text.AlignHCenter
                color: game.paper
                font.bold: true
                font.pixelSize: 36 * scaleFactor
            }
            Text {
                width: parent.width
                text: game.paused ? "Wave " + game.wave + "  ·  " + game.score + " points" :
                    game.phase === "defeat" ? "Reached wave " + game.wave + "  ·  " + game.score + " points" :
                    game.phase === "victory" ? "All five waves cleared  ·  " + game.score + " points" :
                    "Hold the relay bunker through five waves."
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: game.mutedPaper
                font.pixelSize: 16 * scaleFactor
            }
            Text {
                width: parent.width
                visible: game.phase === "ready" && !game.paused
                text: "Drag left to move. Drag right to aim. Hold FIRE to shoot or drag it to aim while firing. Tap ammo to reload."
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: game.paper
                font.pixelSize: 14 * scaleFactor
            }
            ActionTile {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 190 * scaleFactor
                height: 46 * scaleFactor
                sizing: scaleFactor
                primary: true
                label: game.paused ? "Resume" : game.phase === "ready" ? "Start defense" : "Play again"
                onActivated: {
                    if (game.paused)
                        game.resumeRun()
                    else
                        game.startRun()
                }
            }
            ActionTile {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 112 * scaleFactor
                height: 34 * scaleFactor
                sizing: 0.82 * scaleFactor
                label: game.muted ? "Sound off" : "Sound on"
                onActivated: game.muted = !game.muted
            }
        }
    }
}
