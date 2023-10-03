local addonName, addonTable = ...;
local CTL = _G.ChatThrottleLib

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

            if string.find(msg, "%d+") then
                self:DebugPrint(name, "requested specific layer", msg)
                if string.find(string.lower(msg), "not.-%d+") then
                    self:DebugPrint(name, "requested specific layer with not:", msg)
                    self:DebugPrint("Ignoring him")
                    return
                end
                if not containsNumber(msg, addonTable.NWB.currentLayer) then
                    self:DebugPrint(name, "layer condition unsatisfied:", msg)
                    self:DebugPrint("current layer:", addonTable.NWB.currentLayer)
                    return
                end
                self:DebugPrint(name, "layer condition satisfied", msg)
            end

            self:DebugPrint("Matched trigger", trigger, "in message", msg)

            -- check if we've already invited this player in the last 2 hours
            if event ~= "CHAT_MSG_WHISPER" then
                if self.cache[name_without_realm] then
                    local entry = self.cache[name_without_realm]

                    -- delete players from cache that are over 2 hours
                    if entry.time + self.invite_delay < time() then
                        self:DebugPrint("Removing ", player.name, " from cache")
                        self.cache[name_without_realm] = nil
                    else
                        -- dont invite player if they got invited in the last 2 hours
                        self:DebugPrint("Already invited", name, "in the last 2 hours")
                        return
                    end

                end
            end

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
        -- storing table, for some future parameters
        self.cache[segments[1]] = { time = time() - 100 }
    end

    if segments[2] == "declines" then
        self.cache[segments[1]] = { time = time() - 100 }
        self:DebugPrint("Adding ", segments[1], " to cache, reason: declined invite")
    end

    if segments[3] == "invited" then
        if addonTable.NWB ~= nil
                and addonTable.NWB.currentLayer ~= 0
                and self.db.profile.whisper == true then
            CTL:SendChatMessage("NORMAL", segments[4], "[AutoLayer] layer " .. addonTable.NWB.currentLayer .. ", for specific layer try 'LFL 1,2,3,4' etc.",
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
