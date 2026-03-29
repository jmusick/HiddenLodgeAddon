---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize(value)
    return trim(value):lower()
end

local function canEditPublicNotes()
    if type(CanEditPublicNote) == "function" then
        local ok, result = pcall(CanEditPublicNote)
        if ok then
            return result and true or false
        end
    end

    if C_GuildInfo and type(C_GuildInfo.CanEditPublicNote) == "function" then
        local ok, result = pcall(C_GuildInfo.CanEditPublicNote)
        if ok then
            return result and true or false
        end
    end

    return false
end

local function getDesiredNote(db, fullName)
    if not db then
        return nil
    end

    local byName = db.preferredByName or {}
    local normalizedFull = normalize(fullName)
    local simpleName = normalize((fullName and fullName:match("^(.-)%-")) or fullName)

    if simpleName ~= "" and byName[simpleName] ~= nil then
        return trim(byName[simpleName])
    end

    if normalizedFull ~= "" and byName[normalizedFull] ~= nil then
        return trim(byName[normalizedFull])
    end

    return nil
end

local function collectGuildNoteUpdates(db)
    local updates = {}
    local managed = 0

    local total = GetNumGuildMembers()
    for i = 1, total do
        local fullName, _, _, _, _, _, publicNote = GetGuildRosterInfo(i)
        if fullName then
            local desired = getDesiredNote(db, fullName)
            if desired ~= nil then
                managed = managed + 1
                local current = trim(publicNote)
                if normalize(current) ~= normalize(desired) then
                    updates[#updates + 1] = {
                        index = i,
                        name = fullName,
                        desired = desired,
                    }
                end
            end
        end
    end

    return updates, managed
end

function HiddenLodge:TryAutoApplyAltNotes()
    if self._altNoteSyncApplying then
        return
    end
    if not IsInGuild() then
        return
    end

    local store = self.db and self.db.altNoteSync
    if type(store) ~= "table" then
        return
    end

    local sync = store.sync or {}
    local syncedAt = tonumber(sync.syncedAt) or 0
    local entries = tonumber(sync.entries) or 0
    if syncedAt <= 0 or entries <= 0 then
        return
    end

    local lastApplied = tonumber(store.lastAppliedSyncedAt) or 0
    if syncedAt <= lastApplied then
        return
    end

    if not canEditPublicNotes() then
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end

    local updates, managed = collectGuildNoteUpdates(store)
    if #updates == 0 then
        store.lastAppliedSyncedAt = syncedAt
        if managed > 0 then
            self:Print("Alt-note sync: guild notes already up to date.")
        end
        return
    end

    self._altNoteSyncApplying = true
    local applied = 0
    for _, row in ipairs(updates) do
        local ok = pcall(GuildRosterSetPublicNote, row.index, row.desired)
        if ok then
            applied = applied + 1
        end
    end
    self._altNoteSyncApplying = false

    store.lastAppliedSyncedAt = syncedAt
    self:Print(string.format("Alt-note sync applied: %d updated (%d managed).", applied, managed))
end

function HiddenLodge:HandleAltNoteSyncGuildEvent()
    self:TryAutoApplyAltNotes()
end

function HiddenLodge:OnEnableAltNoteSync()
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "HandleAltNoteSyncGuildEvent")
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "HandleAltNoteSyncGuildEvent")

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    self:TryAutoApplyAltNotes()
end
