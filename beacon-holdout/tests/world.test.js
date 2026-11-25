const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const world = vm.createContext({});
vm.runInContext(fs.readFileSync("app/World.js", "utf8").replace(".pragma library", ""), world);
vm.runInContext("Math.random = (function() { var n = 4; return function() { n = (1664525*n+1013904223)>>>0; return n/4294967296; }; })()", world);

const neutral = {forward: 0, strafe: 0, turn: 0, reload: false, fire: false};
const state = world.newGame();
assert.equal(state.phase, "ready");
assert.ok(world.clear(state.x, state.y, 0.2));
world.updatePaths(state);
for (const [x, y] of world.starts)
    assert.ok(state.path[Math.floor(y) * world.width + Math.floor(x)] > 0);

const blocked = {x: 1.25, y: 1.5};
world.move(blocked, -0.2, 0, 0.2);
assert.equal(blocked.x, 1.25);
assert.equal(world.ray(1.5, 1.5, -1, 0).distance, 0.5);

const wallTest = world.newGame();
wallTest.x = 2.5;
wallTest.y = 2.5;
wallTest.enemies = [{x: 5.5, y: 2.5, health: 2}];
world.shoot(wallTest, 1, 0);
assert.equal(wallTest.enemies[0].health, 2, "cover must stop a shot");

world.begin(state);
state.ammo = 2;
world.reload(state);
for (let i = 0; i < 17; i++)
    world.advance(state, 0.07, neutral);
assert.equal(state.ammo, world.magazine);
assert.equal(state.reserve, 62);
assert.equal(state.wave, 1);

for (let i = 0; i < 5500 && state.phase === "playing"; i++) {
    let target = null;
    let range = Infinity;
    for (const enemy of state.enemies) {
        const dx = enemy.x - state.x;
        const dy = enemy.y - state.y;
        const length = Math.hypot(dx, dy);
        if (length > 0 && length < range &&
            world.ray(state.x, state.y, dx / length, dy / length).distance > length) {
            target = Math.atan2(dy, dx);
            range = length;
        }
    }
    world.advance(state, 0.034, {
        ...neutral, fire: target !== null,
        turn: target === null ? 0.03 : target - state.angle,
    });
}
assert.equal(state.phase, "victory", "all waves must be possible to clear");
assert.equal(state.wave, 5);
assert.equal(state.kills, 40);
assert.ok(state.score >= 4000);

const defenseless = world.newGame();
world.begin(defenseless);
for (let i = 0; i < 2800 && defenseless.phase === "playing"; i++)
    world.advance(defenseless, 0.034, neutral);
assert.equal(defenseless.phase, "defeat");
assert.equal(defenseless.health, 0);

console.log("Collision, wall occlusion, reload, and all five waves verified");
