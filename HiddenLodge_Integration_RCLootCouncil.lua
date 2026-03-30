---@diagnostic disable: inject-field, undefined-field, undefined-global
local addonName = ...
---@type HiddenLodgeAddon
local HiddenLodge = LibStub("AceAddon-3.0"):GetAddon(addonName)

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

    local preparednessColumnExists = false
    local greatVaultColumnExists = false
    for _, col in ipairs(voting.scrollCols or {}) do
        if col.colName == "preparednessTier" then
            col.DoCellUpdate = setCellPreparedness
            col.comparesort = preparednessSort
            preparednessColumnExists = true
        elseif col.colName == "greatVaultScore" then
            col.DoCellUpdate = setCellGreatVault
            col.comparesort = greatVaultSort
            greatVaultColumnExists = true
        end
    end

    if not preparednessColumnExists then
        tinsert(voting.scrollCols, {
            name = "HL",
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
