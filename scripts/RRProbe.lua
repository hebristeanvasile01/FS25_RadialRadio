-- FS25_RadialRadio probe v3: enumerates stations by cycling nextChannel (starts once radio is initialized). Remove later.
RRProbe = {}
RRProbe.state = "wait"   -- wait -> dump -> cycle -> done
RRProbe.timer = 0
RRProbe.list = {}

local function dumpTable(name, t, depth)
    if type(t) ~= "table" then Logging.info("[RR3] %s = %s", name, tostring(t)); return end
    local c = 0
    for k, v in pairs(t) do
        c = c + 1
        if c > 40 then Logging.info("[RR3] %s ...", name); break end
        if type(v) == "table" and depth > 0 then dumpTable(name .. "." .. tostring(k), v, depth - 1)
        else Logging.info("[RR3] %s.%s : %s = %s", name, tostring(k), type(v), tostring(v)) end
    end
end

function RRProbe:update(dt)
    local sp = g_soundPlayer
    if sp == nil or g_currentMission == nil then return end
    self.timer = self.timer + dt
    if self.state == "wait" then
        if sp.initialized and self.timer > 3000 then self.state = "dump"; self.timer = 0 end
    elseif self.state == "dump" then
        Logging.info("[RR3] ===== dump =====")
        Logging.info("[RR3] current=%s name='%s' noArgName='%s'", tostring(sp.currentChannel), tostring(sp.currentChannelName), tostring(sp:getChannelName()))
        dumpTable("channelItemMapping", sp.channelItemMapping, 2)
        for k, v in pairs(_G) do
            local s = string.lower(tostring(k))
            if type(v) == "function" and (string.find(s, "channel") or string.find(s, "radio") or string.find(s, "streaming") or string.find(s, "musicplayer")) then
                Logging.info("[RR3] global function %s", tostring(k))
            end
        end
        self.start = sp.currentChannel
        self.steps = 0
        self.state = "cycle"; self.timer = 0
    elseif self.state == "cycle" then
        if self.timer >= 700 then
            self.timer = 0
            if self.steps > 0 then
                local idx, name = sp.currentChannel, sp.currentChannelName
                Logging.info("[RR3] step %d: channel=%s name='%s'", self.steps, tostring(idx), tostring(name))
                if idx == self.start or self.steps >= 60 then
                    self.state = "done"
                    Logging.info("[RR3] ===== cycle finished (%d steps) =====", self.steps)
                    return
                end
            end
            self.steps = self.steps + 1
            pcall(function() sp:nextChannel() end)
        end
    end
end

addModEventListener(RRProbe)
