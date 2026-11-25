# Beacon Holdout

An original, offline first-person zombie survival game for Ubuntu Touch 16.04. Defend a wartime relay bunker through five waves. The map, characters, artwork, and sound effects were made for this game.

## Controls

- Drag anywhere on the left to move. Drag on the right to turn.
- Hold **FIRE** to shoot. Drag **FIRE** to aim while shooting with the same thumb. Tap the ammo counter to reload.
- Tap **Pause** to take a break. Desktop controls are WASD, the left and right arrow keys, Space to fire, R to reload, and Escape to pause or resume.

## Install

Open the `.click` in File Manager, choose **OpenStore**, and tap **Install**. The package is architecture-independent and targets `ubuntu-sdk-16.04.8`.

## Build

Run `python3 build.py` with the Click builder available. The package goes to `dist/`. For desktop testing, run `qmlscene app/BeaconHoldout.qml` with Qt Quick and Qt Multimedia installed.

The game renders at 320 × 180 and scales the scene to the screen. It targets about 30 frames per second and renders only while playing.
