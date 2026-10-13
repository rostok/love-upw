-- Smoke test for the UWP player. Writes diagnostics to <save dir>/diag.txt.
local t = 0
local frame = 0
local lastPixels = ""
local joysticks = {}
local log = {}
local font

local function note(fmt, ...)
    local line = select("#", ...) > 0 and fmt:format(...) or fmt
    log[#log + 1] = line
    love.filesystem.write("diag.txt", table.concat(log, "\n") .. "\n")
end

local function probe(label, fn)
    local ok, a, b, c, d = pcall(fn)
    note("%s: %s %s %s %s %s", label, tostring(ok), tostring(a), tostring(b), tostring(c), tostring(d))
end

-- Busy-waits like a game that loads on the main thread, reporting progress.
-- love.progress comes from the love-uwp player; desktop LÖVE has none.
local function fakeLoading(seconds)
    local progress = love.progress or function() end
    local start = love.timer.getTime()
    local elapsed = 0
    while elapsed < seconds do
        progress("Loading (love.progress demo)", elapsed / seconds)
        elapsed = love.timer.getTime() - start
    end
    progress("Starting", 1)
end

function love.load()
    love.graphics.setBackgroundColor(0.06, 0.09, 0.13)
    note("love.progress: %s", tostring(love.progress ~= nil))
    fakeLoading(3)
    note("LÖVE %d.%d.%d %s", love.getVersion())
    note("OS %s, save dir %s", love.system.getOS(), love.filesystem.getSaveDirectory())
    probe("renderer", love.graphics.getRendererInfo)
    probe("dimensions", love.graphics.getDimensions)
    probe("pixel dimensions", love.graphics.getPixelDimensions)
    probe("dpi scale", love.graphics.getDPIScale)
    probe("window mode", function()
        local w, h, f = love.window.getMode()
        return w, h, f.fullscreen, f.highdpi
    end)
    probe("desktop dimensions", love.window.getDesktopDimensions)
    probe("jit", function() return jit and jit.version, jit and jit.status() end)
    probe("font", function()
        font = love.graphics.newFont(24)
        return font:getHeight(), font:getWidth("Hello")
    end)
    probe("text to canvas", function()
        local canvas = love.graphics.newCanvas(64, 32)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("HHHH", 0, 0)
        love.graphics.setCanvas()
        local data = canvas:newImageData()
        local lit = 0
        data:mapPixel(function(x, y, r, g, b, a)
            if r > 0.5 then lit = lit + 1 end
            return r, g, b, a
        end)
        return "lit pixels", lit
    end)
    probe("canvas formats", function()
        local f = love.graphics.getCanvasFormats()
        return "rgba8", f.rgba8, "r8", f.r8
    end)
end

function love.resize(w, h)
    note("frame %d: resize %d x %d, pixel %d x %d", frame, w, h,
        love.graphics.getPixelWidth(), love.graphics.getPixelHeight())
end

function love.update(dt)
    frame = frame + 1
    local pixels = love.graphics.getPixelWidth() .. "x" .. love.graphics.getPixelHeight()
    if pixels ~= lastPixels then
        note("frame %d: pixels %s", frame, pixels)
        lastPixels = pixels
    end
    t = t + dt
    joysticks = love.joystick.getJoysticks()
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0.92, 0.29, 0.54)
    love.graphics.circle("fill", w / 2 + math.cos(t) * 100, h / 2 + math.sin(t) * 100, 40)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", 2, 2, w - 4, h - 4)
    local lines = {
        ("Window %dx%d, pixels %dx%d, FPS %d"):format(w, h,
            love.graphics.getPixelWidth(), love.graphics.getPixelHeight(), love.timer.getFPS()),
        "Joysticks: " .. #joysticks,
    }
    if font then love.graphics.setFont(font) end
    love.graphics.print(table.concat(lines, "\n"), 20, 20)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
end
