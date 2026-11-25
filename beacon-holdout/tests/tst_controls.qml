import QtQuick 2.4
import QtTest 1.2
import "../app" as Game

Item {
    width: 800
    height: 450

    Game.BeaconHoldout {
        id: round
        anchors.fill: parent
        muted: true
    }

    TestCase {
        name: "BeaconHoldoutTouch"
        when: windowShown

        function test_move_aim_fire_reload_pause() {
            round.startRun()
            compare(round.phase, "playing")
            var startX = round.runState.x
            var startAngle = round.runState.angle
            var gesture = touchEvent(round)

            gesture.press(0, round, 115, 345).press(1, round, 510, 223).
                press(2, round, 742, 380).commit()
            gesture.move(0, round, 115, 289).move(1, round, 555, 223).
                stationary(2).commit()
            tryVerify(function() {
                return round.runState.x > startX + 0.035 &&
                       round.runState.angle > startAngle + 0.11 &&
                       round.ammo < 10
            }, 2500)
            gesture.release(0, round, 115, 289).release(1, round, 555, 223).
                release(2, round, 742, 380).commit()
            compare(round.forward, 0)
            compare(round.fireHeld, false)

            gesture.press(3, round, 633, 402).commit()
            gesture.release(3, round, 633, 402).commit()
            tryCompare(round, "loading", true, 1000)
            tryCompare(round, "ammo", 10, 2400)
            verify(round.reserve < 70)

            gesture.press(4, round, 749, 30).commit()
            gesture.release(4, round, 749, 30).commit()
            tryCompare(round, "paused", true, 1000)
            round.resumeRun()
            compare(round.paused, false)
        }
    }
}
