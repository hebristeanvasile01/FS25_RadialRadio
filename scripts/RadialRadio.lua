-- FS25_RadialRadio by FS Modding
-- GTA style radio wheel: hold Q in a vehicle, move the mouse, release to tune.

RadialRadio = {}
RadialRadio.dir = g_currentModDirectory
-- Q is taken by ATTACH/DETACH in this setup. CapsLock is unused; fallback is "-" (minus).
RadialRadio.KEY = Input.KEY_capslock or Input.KEY_minus
RadialRadio.KEY_LABEL = Input.KEY_capslock and "CapsLock" or "-"

-- Stations as enumerated from the game (index = g_soundPlayer.currentChannel). Rescan with console command: rrScan
RadialRadio.stations = {
    [0] = "TropicalisimaLatino", "TheQueensRockPalace", "PixelTunes", "LaMusique", "KjpFM", "DasEWerk",
    "CountryRoadsFM", "ClassicalRadioNetwork", "11thFloorRadio", "TruckSimFM", "Simulator Radio",
    "Simulator Hits", "Simulator Vibes", "Hive365", "TruckStopRadio", "TSR Country", "TSR Rock",
    "TSR Dance", "TruckersFM", "Upbeat", "Simulator FM", "181.FM", "181.FM Real Country", "Heartbeat Radio",
}
RadialRadio.count = 24

RadialRadio.isOpen = false
RadialRadio.selected = nil      -- station index, or -1 = radio off
RadialRadio.mouseX, RadialRadio.mouseY = 0.5, 0.5
RadialRadio.icons = {}
RadialRadio.pending = nil
RadialRadio.method = nil
RadialRadio.scan = nil
RadialRadio.drawErrorLogged = false


-- ---------------------------------------------------------------- camera lock while the wheel is open
local function lockCamera()
    if VehicleCamera == nil or Utils == nil or Utils.overwrittenFunction == nil then
        Logging.info("[RadialRadio] camera lock: VehicleCamera not available")
        return
    end
    local hooked = {}
    for _, fname in ipairs({ "actionEventLookLeftRight", "actionEventLookUpDown" }) do
        local orig = VehicleCamera[fname]
        if type(orig) == "function" then
            VehicleCamera[fname] = Utils.overwrittenFunction(orig, function(self, superFunc, ...)
                if RadialRadio.isOpen then return end
                return superFunc(self, ...)
            end)
            hooked[#hooked + 1] = fname
        end
    end
    if PlayerInputComponent ~= nil then
        for _, fname in ipairs({ "onInputLook", "onInputLookLeftRight", "onInputLookUpDown" }) do
            local orig = PlayerInputComponent[fname]
            if type(orig) == "function" then
                PlayerInputComponent[fname] = Utils.overwrittenFunction(orig, function(self, superFunc, ...)
                    if RadialRadio.isOpen then return end
                    return superFunc(self, ...)
                end)
                hooked[#hooked + 1] = "Player." .. fname
            end
        end
    end
    Logging.info("[RadialRadio] camera lock hooked: %s", table.concat(hooked, ", "))
end
pcall(lockCamera)

local function log(fmt, ...) Logging.info("[RadialRadio] " .. fmt, ...) end

function RadialRadio:displayName(idx)
    local raw = self.stations[idx] or ("Station " .. tostring(idx))
    local sp = g_soundPlayer
    local rep = sp and sp.channelNameReplacements and sp.channelNameReplacements[string.lower(raw)]
    return rep or raw
end

function RadialRadio:getIconOverlay(idx)
    local raw = self.stations[idx]
    if raw == nil then return nil end
    local key = string.lower(raw)
    if self.icons[key] == nil then
        local path = g_soundPlayer and g_soundPlayer.channelIcons and g_soundPlayer.channelIcons[key]
        if path ~= nil then
            local ok, id = pcall(createImageOverlay, path)
            self.icons[key] = (ok and id and id ~= 0) and id or false
        else
            self.icons[key] = false
        end
    end
    return self.icons[key] or nil
end

function RadialRadio:abbrev(idx)
    local name = self:displayName(idx)
    name = string.gsub(name, " FM$", "")
    local s = ""
    for w in string.gmatch(name, "%S+") do
        s = s .. string.sub(w, 1, 1)
        if #s >= 3 then break end
    end
    return string.upper(s)
end

-- "Radio range = Always" means the game setting radioVehicleOnly is false
function RadialRadio:radioAnywhere()
    local v
    local ok = pcall(function() v = g_gameSettings:getValue(GameSettings.SETTING.RADIO_VEHICLE_ONLY) end)
    if not ok or v == nil then
        ok = pcall(function() v = g_gameSettings:getValue("radioVehicleOnly") end)
    end
    if not self.rangeLogged then
        self.rangeLogged = true
        log("radio vehicle only setting = %s", tostring(v))
    end
    return v == false
end

function RadialRadio:canOpen()
    if g_currentMission == nil or g_soundPlayer == nil then return false end
    if g_gui ~= nil and g_gui:getIsGuiVisible() then return false end
    if g_localPlayer == nil then return false end
    if g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() ~= nil then return true end
    return self:radioAnywhere()
end

function RadialRadio:open()
    self.isOpen = true
    self.selected = nil
    self.moved = false
    self.mouseX, self.mouseY = 0.5, 0.5
    pcall(function() g_inputBinding:setShowMouseCursor(true) end)
    self.blurOk = false
    if g_depthOfFieldManager ~= nil and g_depthOfFieldManager.setBlurState ~= nil then
        self.blurOk = pcall(function() g_depthOfFieldManager:setBlurState(true) end)
    end
    if not self.blurLogged then
        self.blurLogged = true
        log("background blur: %s", self.blurOk and "on" or "not available")
        local m = g_depthOfFieldManager
        log("g_depthOfFieldManager = %s", tostring(m))
        if type(m) == "table" then
            local names = {}
            for k, v in pairs(m) do names[#names + 1] = tostring(k) .. ":" .. type(v) end
            local mt = getmetatable(m)
            if mt ~= nil and type(mt.__index) == "table" then
                for k, v in pairs(mt.__index) do names[#names + 1] = "class." .. tostring(k) .. ":" .. type(v) end
            end
            for _, gn in ipairs({"DepthOfFieldManager", "DepthOfFieldManager_mt"}) do
                local g = rawget(_G, gn)
                if type(g) == "table" then
                    for k, v in pairs(g) do names[#names + 1] = gn .. "." .. tostring(k) .. ":" .. type(v) end
                end
            end
            table.sort(names)
            log("dof members: %s", table.concat(names, ", "))
        end
    end
end

function RadialRadio:close(apply)
    if not self.isOpen then return end
    self.isOpen = false
    pcall(function() g_inputBinding:setShowMouseCursor(false) end)
    if g_depthOfFieldManager ~= nil and g_depthOfFieldManager.setBlurState ~= nil then
        pcall(function() g_depthOfFieldManager:setBlurState(false) end)
    end
    if apply and self.selected ~= nil then self:tune(self.selected) end
end

-- ---------------------------------------------------------------- tuning
function RadialRadio:currentIndex()
    return g_soundPlayer and g_soundPlayer.currentChannel or -1
end

function RadialRadio:tune(idx)
    local sp = g_soundPlayer
    if sp == nil then return end
    if idx == -1 then
        pcall(function() sp:pause() end)
        log("radio off")
        return
    end
    if not sp:getIsPlaying() then pcall(function() sp:play() end) end
    if idx == self:currentIndex() then return end
    self.pending = { target = idx, timer = 0, steps = 0 }
end

-- Only nextChannel/previousChannel are used (verified safe). Steps the shortest way, one step at a time.
local STEP_MS = 350

function RadialRadio:updatePending(dt)
    local p = self.pending
    local sp = g_soundPlayer
    if p == nil or sp == nil then return end
    if sp.currentChannel == p.target then
        self.pending = nil
        return
    end
    p.timer = p.timer + dt
    if p.timer < STEP_MS then return end
    p.timer = 0
    if sp.switchInNextFrame then return end
    local n = self.count
    local fwd = (p.target - sp.currentChannel) % n
    local ok, err
    if fwd <= n / 2 then
        ok, err = pcall(function() sp:nextChannel() end)
    else
        ok, err = pcall(function() sp:previousChannel() end)
    end
    if not ok then log("step error: %s", tostring(err)); self.pending = nil; return end
    p.steps = p.steps + 1
    if p.steps > n then
        log("tuning gave up after %d steps", p.steps)
        self.pending = nil
    end
end

-- ---------------------------------------------------------------- scan (console: rrScan)
function RadialRadio:consoleScan()
    local sp = g_soundPlayer
    if sp == nil or not sp.initialized then return "Start the radio first (press 5 in a vehicle)." end
    self.scan = { start = sp.currentChannel, steps = 0, timer = 0, names = {} }
    return "Scanning stations, wait ~20 s..."
end

function RadialRadio:updateScan(dt)
    local s = self.scan
    local sp = g_soundPlayer
    if s == nil or sp == nil then return end
    s.timer = s.timer + dt
    if s.timer < 700 then return end
    s.timer = 0
    if s.steps > 0 then
        local idx, name = sp.currentChannel, sp.currentChannelName
        s.names[idx] = (name ~= nil and name ~= "") and name or (self.stations[idx] or ("Station " .. idx))
        if idx == s.start or s.steps >= 80 then
            local n = 0
            local newList = {}
            for i, nm in pairs(s.names) do newList[i] = nm; n = n + 1 end
            self.stations = newList
            self.count = n
            log("scan done: %d stations", n)
            self.scan = nil
            return
        end
    end
    s.steps = s.steps + 1
    pcall(function() sp:nextChannel() end)
end

-- ---------------------------------------------------------------- selection + drawing
function RadialRadio:updateSelection()
    local W, H = g_screenWidth or 1920, g_screenHeight or 1080
    local vx = (self.mouseX - 0.5) * (W / H)
    local vy = (self.mouseY - 0.5)
    local dist = math.sqrt(vx * vx + vy * vy)
    if dist < 0.10 then
        if dist < 0.08 and self.moved then self.selected = -1 end
        return
    end
    self.moved = true
    local a = (math.atan2 or math.atan)(vx, vy)
    if a < 0 then a = a + 2 * math.pi end
    local step = 2 * math.pi / self.count
    self.selected = math.floor(a / step + 0.5) % self.count
end

local function rect(self, x, y, w, h, r, g, b, a)
    setOverlayColor(self.pix, r, g, b, a)
    renderOverlay(self.pix, x, y, w, h)
end

function RadialRadio:tex(name)
    if self.texs == nil then self.texs = {} end
    if self.texs[name] == nil then
        local ok, id = pcall(createImageOverlay, self.dir .. "textures/" .. name .. ".dds")
        self.texs[name] = (ok and id and id ~= 0) and id or false
    end
    return self.texs[name] or nil
end

-- draws a texture as a circle of diameter d (screen height units) centered on (cx, cy)
local function circle(self, name, cx, cy, d, r, g, b, a)
    local id = self:tex(name)
    if id == nil then return end
    local k = (g_screenHeight or 1080) / (g_screenWidth or 1920)
    setOverlayColor(id, r, g, b, a)
    renderOverlay(id, cx - d * k / 2, cy - d / 2, d * k, d)
end

function RadialRadio:drawWheel()
    local W, H = g_screenWidth or 1920, g_screenHeight or 1080
    local k = H / W
    if self.pix == nil then
        self.pix = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    rect(self, 0, 0, 1, 1, 0, 0, 0, self.blurOk and 0.30 or 0.50)

    local Ro = 0.20                 -- outer radius of the glass ring
    local R = Ro * 0.90             -- radius where the station bubbles sit
    local D = 0.042                 -- bubble diameter
    local cur = self:currentIndex()
    local playing = g_soundPlayer:getIsPlaying()
    local step = 2 * math.pi / self.count

    circle(self, "rr_ring", 0.5, 0.5, Ro * 2, 1, 1, 1, 1)

    local selIdx = self.selected
    for pass = 1, 2 do
        for i = 0, self.count - 1 do
            local sel = (selIdx == i)
            if (pass == 1 and not sel) or (pass == 2 and sel) then
                local a = i * step
                local cx = 0.5 + math.sin(a) * R * k
                local cy = 0.5 + math.cos(a) * R
                local d = sel and D * 2.1 or D
                if sel then circle(self, "rr_glow", cx, cy, d * 2.6, 1, 1, 1, 0.9) end
                circle(self, "rr_disc", cx, cy, d, 1, 1, 1, sel and 1 or 0.85)
                local icon = self:getIconOverlay(i)
                local isz = d * 0.92
                if icon ~= nil then
                    setOverlayColor(icon, 1, 1, 1, sel and 1 or 0.9)
                    renderOverlay(icon, cx - isz * k / 2, cy - isz / 2, isz * k, isz)
                else
                    setTextColor(1, 1, 1, 1)
                    setTextBold(true)
                    setTextAlignment(RenderText.ALIGN_CENTER)
                    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
                    renderText(cx, cy, d * 0.40, self:abbrev(i))
                end
                if playing and cur == i then
                    circle(self, "rr_disc", cx, cy - d / 2 - 0.010, 0.010, 0.43, 0.85, 0.18, 1)
                end
            end
        end
    end

    -- center glass disc with the hovered (or current) station
    local shown = selIdx
    if shown == nil then shown = playing and cur or -1 end
    local offSel = (shown == -1)
    circle(self, "rr_glow", 0.5, 0.5, 0.25, 1, 1, 1, 0.45)
    circle(self, "rr_disc", 0.5, 0.5, 0.19, offSel and 1 or 1, offSel and 0.55 or 1, offSel and 0.55 or 1, 1)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    if offSel then
        renderText(0.5, 0.5, 0.030, "OFF")
    else
        local icon = self:getIconOverlay(shown)
        if icon ~= nil then
            local isz = 0.135
            setOverlayColor(icon, 1, 1, 1, 1)
            renderOverlay(icon, 0.5 - isz * k / 2, 0.5 - isz / 2, isz * k, isz)
        else
            renderText(0.5, 0.5, 0.042, self:abbrev(shown))
        end
    end

    local label = offSel and "Radio off" or self:displayName(shown)
    renderText(0.5, 0.5 - Ro - 0.06, 0.028, label)

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    setTextColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------- engine hooks
function RadialRadio:keyEvent(unicode, sym, modifier, isDown)
    if sym ~= self.KEY then return end
    if isDown then
        if not self.isOpen and self:canOpen() then self:open() end
    else
        self:close(true)
    end
end

function RadialRadio:mouseEvent(posX, posY, isDown, isUp, button)
    if self.isOpen then self.mouseX, self.mouseY = posX, posY end
end

function RadialRadio:update(dt)
    if self.isOpen then
        if not self:canOpen() then self:close(false) else self:updateSelection() end
    end
    self:updatePending(dt)
    self:updateScan(dt)
end

function RadialRadio:draw()
    if not self.isOpen then return end
    local ok, err = pcall(self.drawWheel, self)
    if not ok and not self.drawErrorLogged then
        self.drawErrorLogged = true
        log("draw error: %s", tostring(err))
    end
end

function RadialRadio:loadMap()
    addConsoleCommand("rrScan", "Rescan the radio stations for the radial wheel", "consoleScan", self)
    log("loaded. Hold %s in a vehicle for the radio wheel.", self.KEY_LABEL)
end

addModEventListener(RadialRadio)
