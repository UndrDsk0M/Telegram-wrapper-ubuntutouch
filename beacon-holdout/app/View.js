.pragma library

.import "World.js" as World

var columns = 112
var depths = []
var colors = {
    "#": [112, 105, 89],
    B: [112, 111, 77],
    C: [125, 91, 62],
    D: [84, 100, 89]
}

function rgb(r, g, b) {
    return "rgb(" + Math.floor(r) + "," + Math.floor(g) + "," + Math.floor(b) + ")"
}

function polygon(context, points, color) {
    context.fillStyle = color
    context.beginPath()
    context.moveTo(points[0], points[1])
    for (var i = 2; i < points.length; i += 2)
        context.lineTo(points[i], points[i + 1])
    context.closePath()
    context.fill()
}

function creature(context, x, ground, size, state, enemy) {
    var bounce = Math.sin(state.time * 7.5 + enemy.step) * size * 0.025
    var arm = Math.cos(state.time * 7.5 + enemy.step) * size * 0.07
    var y = ground - size + bounce
    context.save()
    context.translate(x, y)
    var outline = "#201f18"
    var coat = enemy.flash > 0 ? "#c98456" : "#77724d"
    var face = enemy.flash > 0 ? "#edd0a4" : "#a59a69"
    context.fillStyle = "#181811"
    context.fillRect(-size * 0.27, size * 0.925, size * 0.54, size * 0.06)
    polygon(context, [-size * 0.20,size * 0.44,size * 0.19,size * 0.44,size * 0.15,size * 0.96,
                      size * 0.035,size * 0.96,0,size * 0.67,-size * 0.065,size * 0.96,
                      -size * 0.18,size * 0.96], outline)
    polygon(context, [-size * 0.24,size * 0.26,-size * 0.14,size * 0.20,size * 0.17,size * 0.20,
                      size * 0.25,size * 0.28,size * 0.17,size * 0.62,-size * 0.16,size * 0.64], coat)
    polygon(context, [-size * 0.18,size * 0.25,-size * 0.34,size * 0.43 + arm,-size * 0.29,size * 0.59 + arm,
                      -size * 0.20,size * 0.56 + arm,-size * 0.24,size * 0.43 + arm,-size * 0.10,size * 0.33], coat)
    polygon(context, [size * 0.16,size * 0.26,size * 0.34,size * 0.40 - arm,size * 0.31,size * 0.58 - arm,
                      size * 0.22,size * 0.58 - arm,size * 0.23,size * 0.43 - arm,size * 0.09,size * 0.32], coat)
    context.fillStyle = "#3e3c2b"
    context.fillRect(-size * 0.17, size * 0.49, size * 0.34, size * 0.045)
    polygon(context, [-size * 0.12,size * 0.05,-size * 0.07,0,size * 0.07,0,size * 0.13,size * 0.065,
                      size * 0.10,size * 0.20,-size * 0.08,size * 0.21,-size * 0.13,size * 0.14], face)
    context.fillStyle = "#423b2a"
    context.fillRect(-size * 0.13, size * 0.034, size * 0.26, size * 0.047)
    context.fillRect(-size * 0.04, size * 0.162, size * 0.08, size * 0.025)
    if (size > 10) {
        context.fillStyle = "#f5b75c"
        context.fillRect(-size * 0.079, size * 0.095, size * 0.042, Math.max(1, size * 0.022))
        context.fillRect(size * 0.037, size * 0.095, size * 0.042, Math.max(1, size * 0.022))
    }
    context.restore()
}

function heldTool(context, width, height, state) {
    var bob = Math.sin(state.step) * 3
    var x = width * 0.52 + Math.sin(state.step * 0.5) * 2
    var y = height + bob + (state.reloading > 0 ? Math.sin(state.reloading * Math.PI / 1.1) * 30 : 0)
    context.save()
    context.translate(x, y)
    polygon(context, [12,0,5,-24,15,-45,31,-44,41,-20,65,0], "#1d1a13")
    polygon(context, [30,0,15,-9,15,-37,22,-49,34,-49,46,-29,48,-12,55,0], "#675137")
    polygon(context, [19,-19,18,-47,23,-63,34,-62,38,-47,44,-18,32,-11], "#363b35")
    polygon(context, [23,-54,24,-69,33,-69,36,-54], "#2c2c24")
    polygon(context, [20,-50,24,-55,34,-55,38,-50,34,-45,24,-45], "#8d8968")
    context.fillStyle = "#132322"
    context.fillRect(24, -49, 9, 4)
    context.fillStyle = "#e2ac63"
    context.fillRect(25, -48, state.ammo > 0 ? state.ammo * 0.7 : 1, 2)
    polygon(context, [-13,0,-7,-9,8,-21,16,-20,20,-10,13,0], "#655c3d")
    if (state.fired > 0) {
        polygon(context, [14,-65,23,-72,18,-89,27,-82,34,-103,37,-81,52,-87,44,-73,50,-66,34,-72], "#ef8b3c")
        polygon(context, [22,-68,28,-76,32,-89,34,-76,45,-78,38,-69,33,-72], "#ffd985")
    }
    context.restore()
}

function paint(context, width, height, state) {
    context.clearRect(0, 0, width, height)
    var horizon = height * 0.49
    var ceiling = context.createLinearGradient(0, 0, 0, horizon)
    ceiling.addColorStop(0, "#171813")
    ceiling.addColorStop(1, "#66634a")
    context.fillStyle = ceiling
    context.fillRect(0, 0, width, horizon)
    var floor = context.createLinearGradient(0, horizon, 0, height)
    floor.addColorStop(0, "#57543c")
    floor.addColorStop(1, "#26241c")
    context.fillStyle = floor
    context.fillRect(0, horizon, width, height - horizon)
    context.fillStyle = "rgba(15,14,10,0.25)"
    for (var band = 0; band < 6; band++) {
        var offset = 15 + band * band * 3
        context.fillRect(0, horizon + offset, width, 1)
        context.fillRect(0, horizon - offset, width, 1)
    }

    var dirX = Math.cos(state.angle)
    var dirY = Math.sin(state.angle)
    var plane = 0.71
    var focal = width / (plane * 2)
    var columnWidth = width / columns
    for (var i = 0; i < columns; i++) {
        var perspective = plane * (2 * (i + 0.5) / columns - 1)
        var hit = World.ray(state.x, state.y, dirX - dirY * perspective, dirY + dirX * perspective)
        var distance = Math.max(0.08, hit.distance)
        depths[i] = distance
        var size = focal / distance
        var top = horizon - size * 0.5
        var color = colors[hit.wall] || colors["#"]
        var light = (hit.side ? 0.8 : 1.0) / (1 + distance * 0.115)
        if (hit.u < 0.035 || hit.u > 0.968)
            light *= 0.62
        var px = Math.floor(i * columnWidth)
        var pw = Math.ceil((i + 1) * columnWidth) - px
        context.fillStyle = rgb(color[0] * light, color[1] * light, color[2] * light)
        context.fillRect(px, top, pw, size + 1)
        context.fillStyle = "rgba(17,16,13,0.36)"
        context.fillRect(px, top + size * 0.24, pw, Math.max(1, size * 0.019))
        context.fillRect(px, top + size * 0.70, pw, Math.max(1, size * 0.023))
        context.fillRect(px, top + size * 0.89, pw, size * 0.11)
        if (hit.wall === "B" && hit.u > 0.27 && hit.u < 0.73) {
            var glow = 0.81 + 0.07 * Math.sin(state.time * 5 + hit.u)
            context.fillStyle = rgb(227 * glow * light, 161 * glow * light, 81 * glow * light)
            context.fillRect(px, top + size * 0.16, pw, Math.max(1, size * 0.10))
        }
        if (hit.wall === "D" && hit.u > 0.17 && hit.u < 0.83) {
            context.fillStyle = "rgba(22,28,24,0.43)"
            context.fillRect(px, top + size * 0.37, pw, size * 0.20)
        }
    }

    var sprites = []
    for (i = 0; i < state.enemies.length; i++) {
        var enemy = state.enemies[i]
        var tx = enemy.x - state.x
        var ty = enemy.y - state.y
        var depth = tx * dirX + ty * dirY
        if (depth > 0.17)
            sprites.push({ enemy: enemy, depth: depth, sideways: -tx * dirY + ty * dirX })
    }
    sprites.sort(function(a, b) { return b.depth - a.depth })
    for (i = 0; i < sprites.length; i++) {
        var sprite = sprites[i]
        var sx = width * 0.5 + focal * sprite.sideways / sprite.depth
        var spriteSize = focal * 0.84 / sprite.depth
        var from = Math.max(0, Math.floor((sx - spriteSize * 0.36) / columnWidth))
        var to = Math.min(columns - 1, Math.ceil((sx + spriteSize * 0.36) / columnWidth))
        if (from > to)
            continue
        context.save()
        context.beginPath()
        var visible = false
        var runStart = -1
        for (var strip = from; strip <= to + 1; strip++) {
            if (strip <= to && depths[strip] > sprite.depth) {
                if (runStart < 0)
                    runStart = strip
            } else if (runStart >= 0) {
                var left = Math.floor(runStart * columnWidth)
                context.rect(left, 0, Math.ceil(strip * columnWidth) - left, height)
                runStart = -1
                visible = true
            }
        }
        if (visible) {
            context.clip()
            context.globalAlpha = Math.max(0.36, 1 / (1 + sprite.depth * 0.049))
            creature(context, sx, horizon + focal * 0.5 / sprite.depth, spriteSize, state, sprite.enemy)
        }
        context.restore()
    }

    heldTool(context, width, height, state)
    if (state.damage > 0) {
        context.fillStyle = "rgba(129,24,10," + (state.damage * 1.23) + ")"
        context.fillRect(0, 0, width, height)
    }
    if (state.phase === "playing") {
        var cross = state.hit > 0 ? "#ef9857" : "#f0e3bf"
        var xc = Math.floor(width / 2)
        var yc = Math.floor(horizon)
        context.fillStyle = cross
        context.fillRect(xc - 9, yc, 6, 1)
        context.fillRect(xc + 4, yc, 6, 1)
        context.fillRect(xc, yc - 8, 1, 5)
        context.fillRect(xc, yc + 4, 1, 5)
        context.fillRect(xc, yc, 1, 1)
    }
}
