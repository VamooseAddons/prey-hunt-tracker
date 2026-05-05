-- ============================================================
-- PHT_Achievements.lua
-- Prey-category achievement index. Lazy-built from runtime APIs;
-- no SavedVariables for index data.
-- ============================================================

local PHT = _G.PreyHuntTracker
PHT.Achievements = PHT.Achievements or {}
local A = PHT.Achievements

A.built = false
A.byID = {}                            -- [achID] = entry
A.byName = {}                          -- [name] = { {achID, criterionIndex}, ... }
A.byCriteriaID = {}                    -- [criteriaID] = {achID, criterionIndex}

-- Flag bits (see Reference/_SIGNATURES.md GetAchievementInfo notes)
local ACH_FLAG_HIDE_INCOMPLETE = 0x800

-- ----- pure helpers (no globals, no side effects) -----

function A.StripGossipPrefix(text)
    if not text then return "" end
    local stripped = text:gsub("^%s*%d+%.%s*", "")
    return (stripped:gsub("^%s*(.-)%s*$", "%1"))
end

function A.DetectOrStyle(description)
    if not description then return false end
    local lower = description:lower()
    if lower:find("all of the following", 1, true) then return false end
    if lower:find(" or ", 1, true) then return true end
    return false
end

-- ----- category resolution -----

local function CategoryIsPreyByName(name)
    if not name then return false end
    return name == "Prey"          -- enUS exact match for v1; locales later
end

local function ResolvePreyCategoryID()
    if PHT_DB and PHT_DB.preyCategoryID then
        return PHT_DB.preyCategoryID
    end
    if not GetCategoryList or not GetCategoryInfo then return nil end
    local list = GetCategoryList() or {}
    for _, catID in ipairs(list) do
        local catName = GetCategoryInfo(catID)
        if CategoryIsPreyByName(catName) then
            if PHT_DB then PHT_DB.preyCategoryID = catID end
            return catID
        end
    end
    return nil
end

A.ResolvePreyCategoryID = ResolvePreyCategoryID    -- exposed for slash debugging

-- ----- scrape -----

local function ScrapeOne(catID, i)
    local id, name, points, completed, _, _, _,
          description, flags, icon, rewardText, isGuild, wasEarnedByMe,
          earnedBy, isStatistic = GetAchievementInfo(catID, i)
    if not id or isStatistic then return nil end

    local entry = {
        id = id, name = name, points = points or 0, icon = icon,
        description = description or "",
        rewardText = rewardText or "",
        completed = completed or false,
        wasEarnedByMe = wasEarnedByMe or false,
        hidden = bit.band(flags or 0, ACH_FLAG_HIDE_INCOMPLETE) ~= 0,
        isOr = A.DetectOrStyle(description),
        criteria = {},
        criteriaCompletedCount = 0,
        criteriaTotal = 0,
    }

    local numCriteria = (GetAchievementNumCriteria and GetAchievementNumCriteria(id)) or 0
    local actualCount = 0
    for n = 1, numCriteria do
        local ok, critName, critType, critDone, quantity, reqQuantity, _, _, assetID, _, criteriaID =
            pcall(GetAchievementCriteriaInfo, id, n)
        if ok and critName then
            local crit = {
                name = critName, type = critType, assetID = assetID,
                criteriaID = criteriaID, completed = critDone or false, index = n,
                quantity = quantity or 0, reqQuantity = reqQuantity or 0,
            }
            entry.criteria[n] = crit
            actualCount = actualCount + 1
            if critDone then entry.criteriaCompletedCount = entry.criteriaCompletedCount + 1 end

            local key = strtrim(critName)
            A.byName[key] = A.byName[key] or {}
            table.insert(A.byName[key], { achID = id, criterionIndex = n })

            if criteriaID then
                A.byCriteriaID[criteriaID] = { achID = id, criterionIndex = n }
            end
        end
    end
    -- Track count explicitly; #entry.criteria is undefined on holey tables
    -- if any pcall above failed for a missing criterion mid-range.
    entry.criteriaTotal = actualCount
    return entry
end

function A:Build()
    self.byID = {}
    self.byName = {}
    self.byCriteriaID = {}
    self.built = false

    local catID = ResolvePreyCategoryID()
    if not catID then
        if not self._warnedNoCategory then
            print("|cFF00D9D9[Prey Hunt Tracker]|r Prey achievement category not detected; report to Vamoose.")
            self._warnedNoCategory = true
        end
        return false
    end

    local count = GetCategoryNumAchievements(catID) or 0
    for i = 1, count do
        local entry = ScrapeOne(catID, i)
        if entry then self.byID[entry.id] = entry end
    end
    self.built = true
    return true
end

function A:EnsureBuilt()
    if self.built then return true end
    return self:Build()
end

-- ----- public helpers -----

function A:LookupName(rawName)
    local name = self.StripGossipPrefix(rawName)
    return self.byName[name]
end

function A:ClassifyName(rawName)
    local refs = self:LookupName(rawName)
    if not refs or #refs == 0 then return "none" end

    local hasUnfinished = false
    local hasGuaranteedFinish = false
    local allComplete = true

    for _, ref in ipairs(refs) do
        local entry = self.byID[ref.achID]
        if entry then
            if not entry.completed then
                allComplete = false
                local crit = entry.criteria[ref.criterionIndex]
                if crit and not crit.completed then
                    hasUnfinished = true
                    if entry.isOr then
                        -- any unfinished criterion in an unfinished OR achievement is a guaranteed finish
                        hasGuaranteedFinish = true
                    elseif (entry.criteriaTotal - entry.criteriaCompletedCount) == 1 then
                        -- AND-style: this is the last unfinished criterion
                        hasGuaranteedFinish = true
                    end
                end
            end
        end
    end

    if allComplete then return "complete" end
    if hasGuaranteedFinish then return "finish" end
    if hasUnfinished then return "contribute" end
    return "complete"   -- all feeding achievements done for *this* criterion
end

function A:CountEarned()
    local earned, total = 0, 0
    for _, entry in pairs(self.byID) do
        if not entry.hidden or entry.completed then
            total = total + 1
            if entry.completed then earned = earned + 1 end
        end
    end
    return earned, total
end

-- ----- refresh -----

function A:RefreshOne(achID)
    if not self.built then return end
    local existing = self.byID[achID]
    if not existing then return end                    -- not in our category; ignore

    local catID = (PHT_DB and PHT_DB.preyCategoryID) or ResolvePreyCategoryID()
    if not catID then return end
    -- Achievement isn't necessarily index-stable across calls, so re-scan by ID
    local count = GetCategoryNumAchievements(catID) or 0
    for i = 1, count do
        local id = GetAchievementInfo(catID, i)
        if id == achID then
            local fresh = ScrapeOne(catID, i)
            if fresh then self.byID[achID] = fresh end
            return
        end
    end
end

function A:RefreshFlags()
    if not self.built then return end
    for achID, entry in pairs(self.byID) do
        local _, _, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe, _, _ = GetAchievementInfo(achID)
        entry.completed = completed or false
        entry.wasEarnedByMe = wasEarnedByMe or false
        local doneCount = 0
        for i, crit in ipairs(entry.criteria) do
            local ok, _, _, critDone, quantity, reqQuantity = pcall(GetAchievementCriteriaInfo, achID, i)
            if ok then
                crit.completed = critDone or false
                crit.quantity = quantity or 0
                crit.reqQuantity = reqQuantity or 0
                if critDone then doneCount = doneCount + 1 end
            elseif crit.completed then
                doneCount = doneCount + 1
            end
        end
        entry.criteriaCompletedCount = doneCount
    end
end

function A:RefreshCriterion(criteriaID)
    if not self.built then return end
    local ref = self.byCriteriaID[criteriaID]
    if not ref then return end
    local entry = self.byID[ref.achID]
    if not entry then return end
    local ok, _, _, critDone = pcall(GetAchievementCriteriaInfo, entry.id, ref.criterionIndex)
    if not ok then return end
    local prev = entry.criteria[ref.criterionIndex].completed
    entry.criteria[ref.criterionIndex].completed = critDone or false
    if critDone and not prev then
        entry.criteriaCompletedCount = entry.criteriaCompletedCount + 1
    elseif (not critDone) and prev then
        entry.criteriaCompletedCount = entry.criteriaCompletedCount - 1
    end
end
