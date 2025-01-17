local addonName, addonTable = ...;
local CTL = _G.ChatThrottleLib

local player_cache = {}
local kick_player = nil

local function containsNumber(str, value)
    for v in string.gmatch(str, "%d+") do
        if tonumber(value) == tonumber(v) then
            return true
        end
    end
    return false
end


C_Timer.After(0.1, function()
    for name in LibStub("AceAddon-3.0"):IterateAddons() do
        if name == "NovaWorldBuffs" then
            addonTable.NWB = LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs")
            return
        end
    end

    if addonTable.NWB == nil then
        AutoLayer:Print("Could not find NovaWorldBuffs, disabling NovaWorldBuffs integration")
    end
end)

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(event, msg, name, _, channel)
    if not self.db.profile.enabled then
        return
    end

    local name_without_realm = ({ strsplit("-", name) })[1]
    if name_without_realm == UnitName("player") then
        return
    end

    local triggers = AutoLayer:ParseTriggers()

    for _, trigger in ipairs(triggers) do
        if string.find(string.lower(msg), "%f[%a]"..string.lower(trigger).."%f[%A]") then
            -- much efficency, much wow!
            local blacklist = AutoLayer:ParseBlacklist()
            for _, black in ipairs(blacklist) do
                if string.match(string.lower(msg), string.lower(black)) then
                    self:DebugPrint("Matched blacklist", black, "in message", msg)
                    return
                end
            end

            self:DebugPrint("Matched trigger", trigger, "in message", msg)
            if string.find(msg, "%d+") then
                self:DebugPrint(name, "requested specific layer", msg)
                if string.find(string.lower(msg), "not.-%d+") then
                    self:DebugPrint(name, "contains 'not' in layer request, ignoring for now:", msg)
                    return
                end
                if not containsNumber(msg, addonTable.NWB.currentLayer) then
                    self:DebugPrint(name, "layer condition unsatisfied:", msg)
                    self:DebugPrint("Current layer:", addonTable.NWB.currentLayer)
                    return
                end
                self:DebugPrint(name, "layer condition satisfied", msg)
            end

            -- check if we've already invited this player in the last 5 minutes
            if event ~= "CHAT_MSG_WHISPER" then
                for i, player in ipairs(player_cache) do
                    -- delete players from cache that are over 5 minutes old
                    if player.time + 300 < time() then
                        self:DebugPrint("Removing ", player.name, " from cache")
                        table.remove(player_cache, i)
                    end

                    --self:DebugPrint("Checking ", player.name, " against ", name)
                    --self:DebugPrint("Time: ", player.time, " + 300 < ", time(), " = ", player.time + 300 < time())

                    local player_name_without_realm = ({ strsplit("-", player.name) })[1]

                    -- dont invite player if they got invited in the last 5 minutes

                    if player.name == name_without_realm or player_name_without_realm == name_without_realm and player.time + 300 > time() then
                        self:DebugPrint("Already invited", name, "in the last 5 minutes")
                        return
                    end
                end
            end

            --end

            ---@diagnostic disable-next-line: undefined-global
            InviteUnit(name)

            -- check if group is full
            if self.db.profile.autokick and GetNumGroupMembers() >= 4 then
                self:DebugPrint("Group is full, kicking")

                -- kick first member after group leader
                for i = 4, GetNumGroupMembers() do
                    if UnitIsGroupLeader("player") and i ~= 1 then
                        kick_player = GetRaidRosterInfo(i)
                    end
                end

                return
            end

            return
        end
    end
end

---@diagnostic disable-next-line: inject-field
function AutoLayer:ProcessSystemMessages(_, a)
    if not self.db.profile.enabled then
        return
    end

    local segments = { strsplit(" ", a) }

    -- X joins the party
    if segments[2] == "joins" then
        self.db.profile.layered = self.db.profile.layered + 1

        table.insert(player_cache, { name = segments[1], time = time() - 100 })
    end

    if segments[2] == "declines" then
        table.insert(player_cache, { name = segments[1], time = time() })
        self:DebugPrint("Adding ", segments[1], " to cache, reason: declined invite")
    end

    if segments[3] == "invited" then
        if addonTable.NWB ~= nil and addonTable.NWB.currentLayer ~= 0 and self.db.profile.whisper == true then
            CTL:SendChatMessage("NORMAL", segments[4], "[AutoLayer] invited to layer " .. addonTable.NWB.currentLayer,
                "WHISPER", nil,
                segments[4])
        end
    end
end

function AutoLayer:HandleAutoKick()
    if not self.db.profile.enabled then
        return
    end

    if self.db.profile.autokick and kick_player ~= nil then
        self:DebugPrint("Kicking ", kick_player)
        UninviteUnit(kick_player)
        kick_player = nil
    end
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_SYSTEM", "ProcessSystemMessages")

function JoinLFGChannel()
    JoinChannelByName("LookingForGroup")
    local channel_num = GetChannelName("LookingForGroup")
    if channel_num == 0 then
        print("Failed to join LookingForGroup channel")
    else
        print("Successfully joined LookingForGroup channel.")
    end

    for i = 1, 10 do
        if _G['ChatFrame' .. i] then
            ChatFrame_RemoveChannel(_G['ChatFrame' .. i], "LookingForGroup")
        end
    end
end

function ProccessQueue()
    if #addonTable.send_queue > 0 then
        local payload = table.remove(addonTable.send_queue, 1)
        local channel_num = GetChannelName("LookingForGroup")
        if channel_num == 0 then
            JoinLFGChannel()
            do return end
        end

        CTL:SendChatMessage("BULK", "LookingForGroup", payload, "CHANNEL", nil, channel_num)
    end
end

C_Timer.After(1, function()
    WorldFrame:HookScript("OnMouseDown", function(self, button)
        AutoLayer:HandleAutoKick()
        ProccessQueue()
    end)
end)

local f = CreateFrame("Frame", "Test", UIParent)
f:SetScript("OnKeyDown", ProccessQueue)
f:SetPropagateKeyboardInput(true)
