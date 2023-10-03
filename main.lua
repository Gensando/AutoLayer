---@diagnostic disable: inject-field

local addonName, addonTable = ...;

AutoLayer = LibStub("AceAddon-3.0"):NewAddon("AutoLayer", "AceConsole-3.0", "AceEvent-3.0")
AceGUI = LibStub("AceGUI-3.0")
local minimap_icon = LibStub("LibDBIcon-1.0")

local options = {
    name = "AutoLayer",
    handler = AutoLayer,
    type = "group",
    args = {
        enabled = {
            type = 'toggle',
            name = 'Enabled',
            desc = 'Enable/Disable AutoLayer',
            set = 'SetEnabled',
            get = 'GetEnabled',
            order = 0,
        },

        debug = {
            type = 'toggle',
            name = 'Debug',
            desc = 'Enable/Disable debug messages',
            set = 'SetDebug',
            get = 'GetDebug',
            order = 1,
        },

        triggers = {
            type = 'input',
            name = 'Triggers',
            desc = 'The triggers that will cause the invite message to be sent, seperated by commas',
            set = 'SetTriggers',
            get = 'GetTriggers',
        },

        whisper = {
            type = 'toggle',
            name = 'Send whisper',
            desc = 'Sends a whisper to the player when successfully inviting them with the layer number',
            set = function (info, val)
                AutoLayer.db.profile.whisper = val
            end,
            get = function (info)
                return AutoLayer.db.profile.whisper
            end
        },

        autokick = {
            type = 'toggle',
            name = 'Auto kick',
            -- add red text to desc "test"
            desc =
            'Enable/Disable kicks the last member out if the group is full red \124cffFF0000You need to drag your mouse to trigger it due to an API restriction\124r',
            set = function(info, val)
                AutoLayer.db.profile.autokick = val
            end,
            get = function(info)
                return AutoLayer.db.profile.autokick
            end,
            order = 2,
        },

        blacklist = {
            type = 'input',
            name = 'Blacklist',
            desc = 'The opposite of triggers, if it matches those words in a message it wont invite, seperated by commas',
            set = 'SetBlacklist',
            get = 'GetBlacklist',
        },

        mutesounds = {
            type = 'toggle',
            name = 'Mute annoying sounds',
            desc = 'Mutes party related sounds while autolayer is active',
            set = function(info, val) 
                AutoLayer.db.profile.mutesounds = val

                if val then
                	AutoLayer:MuteAnnoyingSounds()
                else
                    AutoLayer:Print("unmuting")
                    AutoLayer:UnmuteAnnoyingSounds()
                end
            end,
            get = function (info)
            	  return AutoLayer.db.profile.mutesounds
            end
        },

        minimap = {
            type = 'toggle',
            name = 'Hide minimap icon',
            desc = 'Hide/Show the minimap icon',
            order = 4,
            set = function(info, val)
                AutoLayer.db.profile.minimap.hide = val
                if val then
                    minimap_icon:Hide("AutoLayer")
                else
                    minimap_icon:Show("AutoLayer")
                end
            end,
            get = function(info)
                return AutoLayer.db.profile.minimap.hide
            end,
        },
    }
}

local defaults = {
    profile = {
        enabled = true,
        debug = false,
        triggers = "layer, Layer",
        sendMessage = false,
        blacklist = "wts, wtb, guild, lf, lfm, player, enchant",
        mutesounds = true,
        layered = 0,
        minimap = {
            hide = false,
        },
        autokick = true
    }
}

-- put delay here for now, move to settings later
-- can also check if our last layer is same and last time we checked layer
AutoLayer.invite_delay = 60 * 60 * 2 -- 2hrs

function AutoLayer:ClearCache()
    for player_name, _ in pairs(self.cache) do
        if self:IsCacheEntryValid(player_name) then
            self:RemoveCacheEntry(player_name, "cache cleansing")
        end
    end
end

function AutoLayer:AddCacheEntry(player_name, reason)
    reason = reason and reason or "none"
    player_name = ({ strsplit("-", player_name) })[1]

    self:DebugPrint("Adding ", player_name, " to cache, reason:", reason)

    self.cache[player_name] = {
        ["time"] = time() - 100,
        ["layer"] = addonTable.NWB ~= nil and addonTable.NWB.currentLayer or nil
    }
end

function AutoLayer:RemoveCacheEntry(player_name)
    self:DebugPrint("Removing ", player_name, " from cache")
    player_name = ({ strsplit("-", player_name) })[1]
    self.cache[player_name] = nil
end

function AutoLayer:IsCacheEntryValid(player_name)
    if addonTable.NWB == nil then return true end
    if addonTable.NWB.currentLayer == 0 then return true end

    player_name = ({ strsplit("-", player_name) })[1]

    local entry = self.cache[player_name]

    if entry == nil then return false end

    local last_layer = entry.layer ~= nil and entry.layer or addonTable.NWB.currentLayer
    if time() < entry.time + self.invite_delay and last_layer == addonTable.NWB.currentLayer then
        return true
    end
    return false
end

---@diagnostic disable-next-line: duplicate-set-field
function AutoLayer:OnInitialize()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("AutoLayer", options)
    self.db = LibStub("AceDB-3.0"):New("AutoLayerDB", defaults)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("AutoLayer", "AutoLayer")
    local icon = ""

    self.db.char.cache = self.db.char.cache and self.db.char.cache or {}
    -- shortcut
    self.cache = self.db.char.cache

    self:ClearCache()

    if self.db.profile.enabled then
        icon = "Interface\\Icons\\INV_Bijou_Green"
    else
        icon = "Interface\\Icons\\INV_Bijou_Red"
    end

    ---@diagnostic disable-next-line: missing-fields
    local bunnyLDB = LibStub("LibDataBroker-1.1"):NewDataObject("AutoLayer", {
        type = "data source",
        text = "AutoLayer",
        icon = icon,

        -- listen for right click
        OnClick = function(self, button)
            if button == "LeftButton" then
                AutoLayer:Toggle()
            end

            if button == "RightButton" then
                AutoLayer:HopGUI()
            end
        end,

        onMouseUp = function(self, button)
            print(button)
            AutoLayer:Toggle()
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("AutoLayer")
            tooltip:AddLine("Left-click to toggle AutoLayer")
            tooltip:AddLine("Right-click to hop layers")
            tooltip:AddLine("Layered " .. self.db.profile.layered .. " players")

            if addonTable.NWB ~= nil then
                if addonTable.NWB.currentLayer == 0 then
                    tooltip:AddLine("Current layer: unknown, target an NPC")
                else
                    tooltip:AddLine("Current layer: " .. addonTable.NWB.currentLayer)
                end
            end
        end,
    })

    addonTable.bunnyLDB = bunnyLDB

    local frame = CreateFrame("Frame", "MuteSoundFrame")
    frame.MuteSoundFile = MuteSoundFile
    minimap_icon:Register("AutoLayer", bunnyLDB, self.db.profile.minimap)
end


function AutoLayer:MuteAnnoyingSounds()
    MuteSoundFile(567451)
    MuteSoundFile(567490)
end

function AutoLayer:UnmuteAnnoyingSounds()
    UnmuteSoundFile(567451)
    UnmuteSoundFile(567490)
end

function AutoLayer:DebugPrint(...)
    if self.db.profile.debug then
        self:Print(...)
    end
end
