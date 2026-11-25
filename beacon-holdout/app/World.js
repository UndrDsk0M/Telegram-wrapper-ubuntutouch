.pragma library

var map = [
    "##############",
    "#............#",
    "#..BB...C....#",
    "#..B....C.C..#",
    "#.......C.C..#",
    "#.CC.......B.#",
    "#......DD....#",
    "#............#",
    "#...C....CC..#",
    "#...C........#",
    "#...C...B.B..#",
    "#.......B....#",
    "#............#",
    "##############"
]
var width = map[0].length
var height = map.length
var maxWaves = 5
var magazine = 10
var starts = [[1.5, 1.5], [12.5, 1.5], [1.5, 12.5], [12.5, 12.5], [7.5, 1.5], [7.5, 12.5]]

function cell(x, y) {
    if (x < 0 || x >= width || y < 0 || y >= height)
        return "#"
    return map[y].charAt(x)
}

function clear(x, y, radius) {
    return cell(Math.floor(x - radius), Math.floor(y - radius)) === "." &&
           cell(Math.floor(x + radius), Math.floor(y - radius)) === "." &&
           cell(Math.floor(x - radius), Math.floor(y + radius)) === "." &&
           cell(Math.floor(x + radius), Math.floor(y + radius)) === "."
}

function move(object, dx, dy, radius) {
    if (clear(object.x + dx, object.y, radius))
        object.x += dx
    if (clear(object.x, object.y + dy, radius))
        object.y += dy
}

function ray(x, y, dx, dy) {
    var tileX = Math.floor(x)
    var tileY = Math.floor(y)
    var deltaX = Math.abs(1 / dx)
    var deltaY = Math.abs(1 / dy)
    var stepX = dx < 0 ? -1 : 1
    var stepY = dy < 0 ? -1 : 1
    var sideX = dx === 0 ? Infinity : (dx < 0 ? x - tileX : tileX + 1 - x) * deltaX
    var sideY = dy === 0 ? Infinity : (dy < 0 ? y - tileY : tileY + 1 - y) * deltaY
    var impact = 0
    var side = 0
    var material = "."
    for (var i = 0; i < width + height; i++) {
        if (sideX < sideY) {
            tileX += stepX
            impact = sideX
            sideX += deltaX
            side = 0
        } else {
            tileY += stepY
            impact = sideY
            sideY += deltaY
            side = 1
        }
        material = cell(tileX, tileY)
        if (material !== ".")
            break
    }
    var coordinate = side === 0 ? y + dy * impact : x + dx * impact
    return { distance: impact, wall: material, side: side, u: coordinate - Math.floor(coordinate) }
}

function newGame() {
    return {
        x: 3.5, y: 7.5, angle: 0, health: 100, ammo: magazine, reserve: 70,
        phase: "ready", wave: 0, remaining: 0, spawnDelay: 0, intermission: 0.8,
        score: 0, kills: 0, enemies: [], fired: 0, hit: 0, damage: 0,
        cooldown: 0, reloading: 0, time: 0, step: 0, path: [], pathTile: -1,
        shotEvent: 0, waveEvent: 0
    }
}

function begin(state) {
    state.phase = "playing"
}

function reload(state) {
    if (state.phase !== "playing" || state.reloading > 0 ||
            state.ammo === magazine || state.reserve === 0)
        return
    state.reloading = 1.1
}

function shoot(state, dx, dy) {
    if (state.cooldown > 0 || state.reloading > 0)
        return
    if (state.ammo === 0) {
        reload(state)
        return
    }
    state.ammo--
    state.shotEvent++
    state.fired = 0.09
    state.cooldown = 0.24
    var wall = ray(state.x, state.y, dx, dy).distance
    var nearest = wall
    var target = -1
    var center = 0
    for (var i = 0; i < state.enemies.length; i++) {
        var enemy = state.enemies[i]
        var relativeX = enemy.x - state.x
        var relativeY = enemy.y - state.y
        var depth = relativeX * dx + relativeY * dy
        var lateral = Math.abs(relativeX * dy - relativeY * dx)
        if (depth > 0 && depth < nearest && lateral < 0.35) {
            target = i
            nearest = depth
            center = lateral
        }
    }
    if (target < 0)
        return
    state.hit = 0.13
    var struck = state.enemies[target]
    struck.flash = 0.18
    struck.health -= center < 0.12 ? 2 : 1
    if (struck.health <= 0) {
        state.enemies.splice(target, 1)
        state.score += 100
        state.kills++
    } else {
        state.score += 15
    }
}

function startWave(state) {
    state.enemies = []
    state.wave++
    state.remaining = 2 + state.wave * 2
    state.spawnDelay = 0.12
    state.waveEvent++
    if (state.wave > 1) {
        state.health = Math.min(100, state.health + 24)
        state.reserve = Math.min(120, state.reserve + 18)
    }
}

function addEnemy(state) {
    var best = starts[0]
    var furthest = -Infinity
    for (var i = 0; i < starts.length; i++) {
        var pad = starts[i]
        var x = pad[0] - state.x
        var y = pad[1] - state.y
        var weight = x * x + y * y + Math.random() * 22
        for (var j = 0; j < state.enemies.length; j++) {
            var near = state.enemies[j]
            if (Math.abs(near.x - pad[0]) + Math.abs(near.y - pad[1]) < 1.5)
                weight -= 100
        }
        if (weight > furthest) {
            furthest = weight
            best = pad
        }
    }
    state.enemies.push({
        x: best[0], y: best[1], health: state.wave < 3 ? 2 : 3,
        flash: 0, attack: 0.4, speed: 0.6 + state.wave * 0.1 + Math.random() * 0.19,
        step: Math.random() * 6
    })
    state.remaining--
    state.spawnDelay = Math.max(0.39, 0.98 - state.wave * 0.1)
}

function updatePaths(state) {
    var x = Math.floor(state.x)
    var y = Math.floor(state.y)
    var tile = y * width + x
    if (tile === state.pathTile)
        return
    state.pathTile = tile
    var queue = [tile]
    var path = []
    path[tile] = 0
    for (var i = 0; i < queue.length; i++) {
        var index = queue[i]
        var directions = [-1, 1, -width, width]
        for (var j = 0; j < directions.length; j++) {
            var near = index + directions[j]
            if (path[near] === undefined && cell(near % width, Math.floor(near / width)) === ".") {
                path[near] = path[index] + 1
                queue.push(near)
            }
        }
    }
    state.path = path
}

function steer(state, enemy) {
    var dx = state.x - enemy.x
    var dy = state.y - enemy.y
    var range = Math.sqrt(dx * dx + dy * dy)
    if (range < 0.001)
        return { x: 0, y: 0, range: range }
    if (ray(enemy.x, enemy.y, dx / range, dy / range).distance > range + 0.18)
        return { x: dx / range, y: dy / range, range: range }
    var position = Math.floor(enemy.y) * width + Math.floor(enemy.x)
    var choices = [-1, 1, -width, width]
    var next = position
    for (var i = 0; i < choices.length; i++) {
        var near = position + choices[i]
        if (state.path[near] !== undefined && state.path[near] < state.path[next])
            next = near
    }
    dx = next % width + 0.5 - enemy.x
    dy = Math.floor(next / width) + 0.5 - enemy.y
    var length = Math.sqrt(dx * dx + dy * dy)
    return { x: length > 0.01 ? dx / length : 0, y: length > 0.01 ? dy / length : 0, range: range }
}

function advance(state, delta, input) {
    if (state.phase !== "playing")
        return
    delta = Math.max(0, Math.min(delta, 0.072))
    state.time += delta
    state.angle = (state.angle + input.turn) % (Math.PI * 2)
    var dx = Math.cos(state.angle)
    var dy = Math.sin(state.angle)
    var length = Math.sqrt(input.forward * input.forward + input.strafe * input.strafe)
    var speed = delta * 2.85 / Math.max(1, length)
    move(state, (dx * input.forward - dy * input.strafe) * speed,
                (dy * input.forward + dx * input.strafe) * speed, 0.2)
    state.step += Math.min(1, length) * delta * 9
    state.fired = Math.max(0, state.fired - delta)
    state.hit = Math.max(0, state.hit - delta)
    state.damage = Math.max(0, state.damage - delta)
    state.cooldown = Math.max(0, state.cooldown - delta)
    if (state.reloading > 0) {
        state.reloading = Math.max(0, state.reloading - delta)
        if (state.reloading === 0) {
            var rounds = Math.min(magazine - state.ammo, state.reserve)
            state.ammo += rounds
            state.reserve -= rounds
        }
    }
    if (input.reload)
        reload(state)
    if (input.fire)
        shoot(state, dx, dy)

    if (state.remaining === 0 && state.enemies.length === 0) {
        if (state.wave === maxWaves) {
            state.phase = "victory"
            return
        }
        state.intermission -= delta
        if (state.intermission <= 0) {
            startWave(state)
            state.intermission = 2.4
        }
    }
    if (state.remaining > 0 && state.enemies.length < 8) {
        state.spawnDelay -= delta
        if (state.spawnDelay <= 0)
            addEnemy(state)
    }

    updatePaths(state)
    for (var i = 0; i < state.enemies.length; i++) {
        var enemy = state.enemies[i]
        enemy.flash = Math.max(0, enemy.flash - delta)
        enemy.attack = Math.max(0, enemy.attack - delta)
        var way = steer(state, enemy)
        if (way.range < 0.77 && ray(state.x, state.y, (enemy.x - state.x) / Math.max(0.001, way.range),
                                   (enemy.y - state.y) / Math.max(0.001, way.range)).distance > way.range) {
            if (enemy.attack === 0) {
                state.health = Math.max(0, state.health - 8 - state.wave * 2)
                state.damage = 0.24
                enemy.attack = 0.83
            }
        } else {
            var nx = way.x
            var ny = way.y
            for (var j = 0; j < state.enemies.length; j++) {
                if (i === j)
                    continue
                var other = state.enemies[j]
                var ox = enemy.x - other.x
                var oy = enemy.y - other.y
                var separation = Math.sqrt(ox * ox + oy * oy)
                if (separation > 0.005 && separation < 0.53) {
                    nx += ox / separation * (0.53 - separation)
                    ny += oy / separation * (0.53 - separation)
                }
            }
            move(enemy, nx * enemy.speed * delta, ny * enemy.speed * delta, 0.18)
        }
    }
    if (state.health <= 0)
        state.phase = "defeat"
}
