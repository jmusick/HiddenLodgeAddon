---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName) --[[@as HiddenLodgeAddon]]

function HiddenLodge:EnsureRCLootCouncilColumn()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not ace then
        return false, "AceAddon-3.0 is not available."
    end

    local rc = ace:GetAddon("RCLootCouncil", true)
    if not rc then
        return false, "RCLootCouncil is not loaded."
    end

    local voting = rc.GetModule and rc:GetModule("RCVotingFrame", true)
    if not voting then
        return false, "RCVotingFrame module is unavailable."
    end

    local function preparednessSort(tableObj, rowa, rowb, sortbycol)
        local column = tableObj.cols[sortbycol]
        local a = tableObj:GetRow(rowa)
        local b = tableObj:GetRow(rowb)
        if not (a and b) then
            return false
        end

        local at = self:GetPreparednessTierSortValue(self:GetPreparednessTierForCandidate(a.name))
        local bt = self:GetPreparednessTierSortValue(self:GetPreparednessTierForCandidate(b.name))

        if at == bt then
            local an = tostring(a.name or "")
            local bn = tostring(b.name or "")
            if an == bn then
                return false
            end
            local direction = column.sort or column.defaultsort or 1
            if direction == 1 then
                return an < bn
            end
            return an > bn
        end

        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            return at < bt
        end
        return at > bt
    end

    local function setCellPreparedness(rowFrame, frame, data, cols, row, realrow, column)
        local name = data and data[realrow] and data[realrow].name or nil
        local tier = self:GetPreparednessTierForCandidate(name)
        local r, g, b = self:GetPreparednessTierColor(tier)
        frame.text:SetText(tier)
        frame.text:SetTextColor(r, g, b, 1)
        if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
            data[realrow].cols[column].value = self:GetPreparednessTierSortValue(tier)
        end
    end

    local function greatVaultSort(tableObj, rowa, rowb, sortbycol)
        local column = tableObj.cols[sortbycol]
        local a = tableObj:GetRow(rowa)
        local b = tableObj:GetRow(rowb)
        if not (a and b) then
            return false
        end

        local ascore = self:GetGreatVaultScoreForCandidate(a.name)
        local bscore = self:GetGreatVaultScoreForCandidate(b.name)
        local av = ascore or -1
        local bv = bscore or -1

        if av == bv then
            local an = tostring(a.name or "")
            local bn = tostring(b.name or "")
            if an == bn then
                return false
            end
            local direction = column.sort or column.defaultsort or 1
            if direction == 1 then
                return an < bn
            end
            return an > bn
        end

        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            return av < bv
        end
        return av > bv
    end

    local function setCellGreatVault(rowFrame, frame, data, cols, row, realrow, column)
        local name = data and data[realrow] and data[realrow].name or nil
        local score = self:GetGreatVaultScoreForCandidate(name)
        if score == nil then
            frame.text:SetText("-")
            frame.text:SetTextColor(0.70, 0.70, 0.70, 1)
            if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
                data[realrow].cols[column].value = -1
            end
            return
        end

        local r, g, b = self:GetGreatVaultScoreColor(score)
        frame.text:SetText(tostring(score))
        frame.text:SetTextColor(r, g, b, 1)
        if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
            data[realrow].cols[column].value = score
        end
    end

    local function attendanceSort(tableObj, rowa, rowb, sortbycol)
        local column = tableObj.cols[sortbycol]
        local a = tableObj:GetRow(rowa)
        local b = tableObj:GetRow(rowb)
        if not (a and b) then
            return false
        end

        local ascore = self:GetAttendanceScoreForCandidate(a.name)
        local bscore = self:GetAttendanceScoreForCandidate(b.name)
        local av = ascore or -1
        local bv = bscore or -1

        if av == bv then
            local an = tostring(a.name or "")
            local bn = tostring(b.name or "")
            if an == bn then
                return false
            end
            local direction = column.sort or column.defaultsort or 1
            if direction == 1 then
                return an < bn
            end
            return an > bn
        end

        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            return av < bv
        end
        return av > bv
    end

    local function setCellAttendance(rowFrame, frame, data, cols, row, realrow, column)
        local name = data and data[realrow] and data[realrow].name or nil
        local score = self:GetAttendanceScoreForCandidate(name)
        if score == nil then
            frame.text:SetText("-")
            frame.text:SetTextColor(0.70, 0.70, 0.70, 1)
            if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
                data[realrow].cols[column].value = -1
            end
            return
        end

        local r, g, b = self:GetAttendanceScoreColor(score)
        frame.text:SetText(string.format("%.1f", score))
        frame.text:SetTextColor(r, g, b, 1)
        if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
            data[realrow].cols[column].value = score
        end
    end

    local function raidSignupSort(tableObj, rowa, rowb, sortbycol)
        local column = tableObj.cols[sortbycol]
        local a = tableObj:GetRow(rowa)
        local b = tableObj:GetRow(rowb)
        if not (a and b) then
            return false
        end

        local aStatus, _, aSignedAt = self:GetRaidSignupForCandidate(a.name)
        local bStatus, _, bSignedAt = self:GetRaidSignupForCandidate(b.name)
        local aRank = self:GetRaidSignupSortValue(aStatus)
        local bRank = self:GetRaidSignupSortValue(bStatus)
        local aTs = tonumber(aSignedAt) or 0
        local bTs = tonumber(bSignedAt) or 0

        if aRank == bRank and aTs == bTs then
            local an = tostring(a.name or "")
            local bn = tostring(b.name or "")
            if an == bn then
                return false
            end
            local direction = column.sort or column.defaultsort or 1
            if direction == 1 then
                return an < bn
            end
            return an > bn
        end

        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            if aRank == bRank then
                return aTs < bTs
            end
            return aRank < bRank
        end
        if aRank == bRank then
            return aTs > bTs
        end
        return aRank > bRank
    end

    local function setCellRaidSignup(rowFrame, frame, data, cols, row, realrow, column)
        local name = data and data[realrow] and data[realrow].name or nil
        local statusKey, statusLabel, signedAt = self:GetRaidSignupForCandidate(name)
        local signedAtText = self:FormatRaidSignupSignedAt(signedAt)
        local text = statusLabel
        if signedAtText ~= "-" then
            text = statusLabel .. " " .. signedAtText
        end

        local r, g, b = self:GetRaidSignupColor(statusKey)
        frame.text:SetText(text)
        frame.text:SetTextColor(r, g, b, 1)

        if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
            local rank = self:GetRaidSignupSortValue(statusKey)
            local ts = tonumber(signedAt) or 0
            data[realrow].cols[column].value = rank * 10000000000 + ts
        end
    end

    local function droptimizerSort(tableObj, rowa, rowb, sortbycol)
        local column = tableObj.cols[sortbycol]
        local a = tableObj:GetRow(rowa)
        local b = tableObj:GetRow(rowb)
        if not (a and b) then
            return false
        end

        local itemId = self:GetCurrentRCLootItemId(voting)
        local adelta = select(1, self:GetDroptimizerUpgradeForCandidate(a.name, itemId))
        local bdelta = select(1, self:GetDroptimizerUpgradeForCandidate(b.name, itemId))
        local av = adelta or -999999999
        local bv = bdelta or -999999999

        if av == bv then
            local an = tostring(a.name or "")
            local bn = tostring(b.name or "")
            if an == bn then
                return false
            end
            local direction = column.sort or column.defaultsort or 1
            if direction == 1 then
                return an < bn
            end
            return an > bn
        end

        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            return av < bv
        end
        return av > bv
    end

    local function setCellDroptimizer(rowFrame, frame, data, cols, row, realrow, column)
        local name = data and data[realrow] and data[realrow].name or nil
        local itemId = self:GetCurrentRCLootItemId(voting)
        local delta, pct = self:GetDroptimizerUpgradeForCandidate(name, itemId)

        if not itemId then
            frame.text:SetText("?")
            frame.text:SetTextColor(0.70, 0.70, 0.70, 1)
            if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
                data[realrow].cols[column].value = -999999999
            end
            return
        end

        frame.text:SetText(self:FormatDroptimizerUpgrade(delta, pct))
        local r, g, b = self:GetDroptimizerUpgradeColor(delta)
        frame.text:SetTextColor(r, g, b, 1)

        if data and data[realrow] and data[realrow].cols and data[realrow].cols[column] then
            data[realrow].cols[column].value = delta or -999999999
        end
    end

    local preparednessColumnExists = false
    local greatVaultColumnExists = false
    local attendanceColumnExists = false
    local raidSignupColumnExists = false
    local droptimizerColumnExists = false
    for _, col in ipairs(voting.scrollCols or {}) do
        if col.colName == "preparednessTier" then
            col.DoCellUpdate = setCellPreparedness
            col.comparesort = preparednessSort
            preparednessColumnExists = true
        elseif col.colName == "greatVaultScore" then
            col.DoCellUpdate = setCellGreatVault
            col.comparesort = greatVaultSort
            greatVaultColumnExists = true
        elseif col.colName == "attendanceScore" then
            col.DoCellUpdate = setCellAttendance
            col.comparesort = attendanceSort
            attendanceColumnExists = true
        elseif col.colName == "raidSignup" then
            col.DoCellUpdate = setCellRaidSignup
            col.comparesort = raidSignupSort
            raidSignupColumnExists = true
        elseif col.colName == "droptimizerUpgrade" then
            col.DoCellUpdate = setCellDroptimizer
            col.comparesort = droptimizerSort
            droptimizerColumnExists = true
        end
    end

    if not preparednessColumnExists then
        tinsert(voting.scrollCols, {
            name = "Prep",
            DoCellUpdate = setCellPreparedness,
            colName = "preparednessTier",
            width = 70,
            align = "CENTER",
            comparesort = preparednessSort,
            sortnext = 2,
        })
    end

    if not greatVaultColumnExists then
        tinsert(voting.scrollCols, {
            name = "GV",
            DoCellUpdate = setCellGreatVault,
            colName = "greatVaultScore",
            width = 52,
            align = "CENTER",
            comparesort = greatVaultSort,
            sortnext = 2,
        })
    end

    if not attendanceColumnExists then
        tinsert(voting.scrollCols, {
            name = "Att",
            DoCellUpdate = setCellAttendance,
            colName = "attendanceScore",
            width = 56,
            align = "CENTER",
            comparesort = attendanceSort,
            sortnext = 2,
        })
    end

    if not raidSignupColumnExists then
        tinsert(voting.scrollCols, {
            name = "Signup",
            DoCellUpdate = setCellRaidSignup,
            colName = "raidSignup",
            width = 136,
            align = "LEFT",
            comparesort = raidSignupSort,
            sortnext = 2,
        })
    end

    if not droptimizerColumnExists then
        tinsert(voting.scrollCols, {
            name = "Upgrade",
            DoCellUpdate = setCellDroptimizer,
            colName = "droptimizerUpgrade",
            width = 114,
            align = "LEFT",
            comparesort = droptimizerSort,
            sortnext = 2,
        })
    end

    if voting.frame and voting.frame.UpdateSt then
        voting.frame.UpdateSt()
    end
    if voting.frame and voting.frame.st and voting.frame.st.Refresh then
        voting.frame.st:Refresh()
    end

    return true
end

HiddenLodge:RegisterIntegration("rclootcouncil", {
    addon = "RCLootCouncil",
    init = function(self)
        return self:EnsureRCLootCouncilColumn()
    end,
})
