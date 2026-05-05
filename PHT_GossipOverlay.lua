-- ============================================================
-- PHT_GossipOverlay.lua
-- Decorates Astalor Bloodsworn's gossip menu (Prey: Preferential Killing)
-- with priority icons + a hover tooltip listing achievement progress.
-- ============================================================
-- GossipFrame.gossipOptions is a runtime field used by Plumber's pattern;
-- not declared in Blizzard's Lua type stubs so LS flags it. opt.icon also
-- accepts texture path strings at runtime even though stubs say integer.
---@diagnostic disable: undefined-field, assign-type-mismatch

local PHT = _G.PreyHuntTracker
PHT.GossipOverlay = PHT.GossipOverlay or {}
local GO = PHT.GossipOverlay

-- Visual mapping per classification tag. The gossip option icon slot is
-- rendered via SetTexture() and expects a texture path string -- atlas
-- names are silently dropped. Use stock client texture paths.
GO.ATLAS_BY_TAG = {
    finish     = "Interface\\COMMON\\FavoritesIcon",        -- guaranteed-finish kill
    complete   = "Interface\\Buttons\\UI-CheckBox-Check",   -- already earned for all feeding achievements
    contribute = "Interface\\COMMON\\Indicator-Yellow",     -- contributes but doesn't finish
}

GO.LABEL_BY_TAG = {
    finish     = "hunt this prey to finish an achievement",
    complete   = "no achievements left to earn from this prey",
    contribute = "hunt this prey to progress an achievement",
}

-- The "finish" star is the headline-priority icon; render it 30% larger
-- than the surrounding gossip glyphs so it pops in a long list.
GO.ICON_SCALE_BY_TAG = {
    finish     = 1.3,
    complete   = 1.0,
    contribute = 1.0,
}

GO.iconStash = {}                                -- [optionIndex] = { icon, optionRef }
GO.tooltipsHooked = setmetatable({}, { __mode = "k" })
GO.activeForAstalor = false                      -- DUI hook reads this to decide when to override
GO._duiHookInstalled = false
GO._blizzHookInstalled = false
GO._selectHookInstalled = false
GO.selectedTarget = nil                          -- last clicked NPC name across gossip steps
GO.cachedOptions = nil                           -- snapshot of current step's options for capture lookup

GO.DIFFICULTY_NAMES = { Normal = true, Hard = true, Nightmare = true }

-- Forward declarations so methods declared earlier in the file can
-- reference these file-local helpers that are defined later.
local BuildTooltipText
local BuildLegendLines
local BuildDifficultyTooltipText
local BuildDifficultyOverallTooltipText
local ClassifyDifficulty
local ClassifyDifficultyOverall
local AchievementMatchesDifficulty

function GO:GetTargetNpcID()
    if PHT.GetUnitNpcID then return PHT.GetUnitNpcID("npc") end
    return nil
end

-- DialogueUI replaces Blizzard's GossipFrame entirely. Detect the mixin
-- and one-time-hook SetGossip so we can override the icon AFTER DUI sets it.
function GO:InstallDUIHookIfPresent()
    if self._duiHookInstalled then return end
    if not _G.DUIDialogOptionButtonMixin or not _G.DUIDialogOptionButtonMixin.SetGossip then return end
    self._duiHookInstalled = true
    hooksecurefunc(_G.DUIDialogOptionButtonMixin, "SetGossip", function(button, data)
        if not GO.activeForAstalor then return end
        if not data or not data.name or not button.Icon then return end
        local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(data.name) or data.name
        local tag, kind = GO:ResolveTag(clean)
        if tag ~= "none" then
            GO:ApplyIcon(button.Icon, tag)
            GO:WireDUITooltip(button, clean, kind)
        end
    end)
end

-- Pick the right classifier for an option. NPC-target rows go through
-- ClassifyName; difficulty rows (Normal/Hard/Nightmare) only classify
-- when we know which target the player picked on the previous step.
-- Returns: tag ("finish"/"complete"/"contribute"/"none"), kind ("target"/"difficulty")
function GO:ResolveTag(cleanName)
    if not PHT.Achievements then return "none", "target" end
    if self.DIFFICULTY_NAMES[cleanName] then
        if self.selectedTarget then
            return ClassifyDifficulty(self.selectedTarget, cleanName), "difficulty"
        end
        -- No target yet (Random Hunt flow): classify the difficulty by
        -- whether ANY Prey: achievement at that difficulty has remaining
        -- progress, so the player still gets a useful icon + tooltip.
        return ClassifyDifficultyOverall(cleanName), "difficulty-any"
    end
    return PHT.Achievements:ClassifyName(cleanName), "target"
end

-- Apply tag icon to a Texture region, scaling by ICON_SCALE_BY_TAG. Records
-- baseline size on first call so re-application is idempotent.
function GO:ApplyIcon(iconTex, tag)
    if not iconTex or not tag then return end
    iconTex:SetTexture(self.ATLAS_BY_TAG[tag])
    -- Capture the canonical size on first non-zero observation; a frame's
    -- texture region can have GetWidth()==0 before layout completes, so
    -- sampling once-and-cache would freeze us at zero.
    local w, h = iconTex:GetWidth(), iconTex:GetHeight()
    if (not iconTex.PHT_baseW or iconTex.PHT_baseW <= 0) and w > 0 then
        iconTex.PHT_baseW, iconTex.PHT_baseH = w, h
    end
    local base = iconTex.PHT_baseW or 16
    local baseH = iconTex.PHT_baseH or base
    local scale = self.ICON_SCALE_BY_TAG[tag] or 1.0
    iconTex:SetSize(base * scale, baseH * scale)
end

function GO:OnGossipShow()
    -- Hide any stale tooltip from a row destroyed by the gossip transition;
    -- without this our previous-step tooltip lingers over the new dialog.
    if GameTooltip then GameTooltip:Hide() end
    -- Only re-evaluate the NPC on the FIRST step of a session. Multi-step
    -- gossip transitions can briefly clear the "npc" unit token; if we
    -- re-tested every step we'd incorrectly mark the session inactive
    -- mid-flow. Cleanup() resets the flag on GOSSIP_CLOSED.
    if not self.activeForAstalor then
        self.activeForAstalor = (self:GetTargetNpcID() == PHT.ASTALOR_NPC_ID)
    end
    if not self.activeForAstalor then return end
    if PHT.Achievements then PHT.Achievements:EnsureBuilt() end
    self:CacheOptions()
    -- Hook is installed at module load (below); fallback re-attempt here in
    -- case DialogueUI loaded between then and now.
    self:InstallDUIHookIfPresent()
    self:InstallBlizzardHookIfPresent()
    self:Decorate()              -- Blizzard GossipFrame path (no-op if hidden)
    self:RewireBlizzardVisible() -- Apply icon + tooltip to rows already bound
    self:RepaintDUIVisible()     -- For rows DUI rendered before our hook was active
end

-- Quest accept hook: when a "Prey: <Target> (<Difficulty>)" quest enters
-- the log, classify and announce in chat. Lets random-hunt players see
-- whether the rolled target is a finisher / contributor / cosmetic kill,
-- since the gossip closes immediately after picking difficulty.
function GO:OnQuestAccepted(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetTitleForQuestID then return end
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if not title then return end
    local target, difficulty = title:match("^Prey:%s*(.-)%s*%((Normal)%)$")
    if not target then target, difficulty = title:match("^Prey:%s*(.-)%s*%((Hard)%)$") end
    if not target then target, difficulty = title:match("^Prey:%s*(.-)%s*%((Nightmare)%)$") end
    if not target or not difficulty then return end

    if PHT.Achievements then PHT.Achievements:EnsureBuilt() end
    local tag = ClassifyDifficulty(target, difficulty)
    if tag == "none" then
        print(string.format("|cFF00D9D9[Prey Hunt Tracker]|r Hunt assigned: |cFFFFFFFF%s|r (%s) -- not in any Prey achievement",
            target, difficulty))
        return
    end

    local prefix = self.ATLAS_BY_TAG[tag] and string.format("|T%s:14|t ", self.ATLAS_BY_TAG[tag]) or ""
    if tag == "finish" then
        print(string.format("|cFF00D9D9[Prey Hunt Tracker]|r %s|cFFFFD933Hunt assigned:|r |cFFFFFFFF%s|r (%s) -- |cFFFFD933will FINISH an achievement!|r",
            prefix, target, difficulty))
    elseif tag == "contribute" then
        print(string.format("|cFF00D9D9[Prey Hunt Tracker]|r %s|cFFA0C8FFHunt assigned:|r |cFFFFFFFF%s|r (%s) -- progresses an achievement",
            prefix, target, difficulty))
    elseif tag == "complete" then
        print(string.format("|cFF00D9D9[Prey Hunt Tracker]|r %s|cFF888888Hunt assigned:|r |cFFFFFFFF%s|r (%s) -- already earned at this difficulty",
            prefix, target, difficulty))
    end
end

function GO:Cleanup()
    self.activeForAstalor = false
    self.selectedTarget = nil
    self.cachedOptions = nil
    -- Reset the hooked-button registry. Pooled gossip buttons survive
    -- between sessions; without this they keep stale OnEnter closures
    -- that show the previous step's tooltip on a recycled row.
    self.tooltipsHooked = setmetatable({}, { __mode = "k" })
    self:RestoreIcons()
    if GameTooltip then GameTooltip:Hide() end
end

-- Snapshot the current step's options at GOSSIP_SHOW time. We need this
-- because by the time SelectOption hooks fire, the live options table
-- has often been cleared by the server-side action.
function GO:CacheOptions()
    local snap
    if C_GossipInfo and C_GossipInfo.GetOptions then
        snap = C_GossipInfo.GetOptions()
    end
    if (not snap or #snap == 0) and GossipFrame and GossipFrame.gossipOptions then
        snap = GossipFrame.gossipOptions
    end
    if snap and #snap > 0 then
        self.cachedOptions = snap
    end
end

-- Hook C_GossipInfo.SelectOption / SelectOptionByIndex so we know which
-- target the player picked on the previous step (used when classifying the
-- difficulty selector that follows).
function GO:InstallSelectionHook()
    if self._selectHookInstalled then return end
    if not C_GossipInfo or not C_GossipInfo.SelectOption then return end
    self._selectHookInstalled = true
    -- Blizzard's SelectOption takes a gossipOptionID (unique).
    -- DialogueUI's SelectOptionByIndex takes an orderIndex (1-based row).
    -- Try matching either field on the cached options.
    local function capture(idValue, byIndex)
        if not GO.activeForAstalor or not idValue then return end
        if GameTooltip then GameTooltip:Hide() end
        -- Prefer the snapshot taken at GOSSIP_SHOW; live tables get cleared
        -- by the server-side action before our hook runs.
        local options = GO.cachedOptions
        if not options or #options == 0 then
            options = (GossipFrame and GossipFrame.gossipOptions)
                  or (C_GossipInfo.GetOptions and C_GossipInfo.GetOptions())
        end
        if not options or #options == 0 then return end
        for i, opt in ipairs(options) do
            -- Match against the unique ID (Blizzard) or orderIndex (DUI),
            -- and as a final fallback the row's array position.
            local matchByID = (opt.gossipOptionID == idValue)
            local matchByOrder = (opt.orderIndex == idValue)
            local matchByPos = byIndex and (i == idValue)
            if (matchByID or matchByOrder or matchByPos) and opt.name then
                local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(opt.name) or opt.name
                -- Only treat this as a "target" pick if at least one feeding
                -- achievement is a "Prey: ..." kill achievement. Zone names
                -- (Eversong Woods etc.) feed objective-style achievements
                -- only and must not overwrite the target capture.
                local refs = PHT.Achievements and PHT.Achievements.byName[clean]
                local isPreyTarget = false
                if refs then
                    for _, ref in ipairs(refs) do
                        local entry = PHT.Achievements.byID[ref.achID]
                        if entry and entry.name and entry.name:find("^Prey:") then
                            isPreyTarget = true
                            break
                        end
                    end
                end
                if isPreyTarget then
                    GO.selectedTarget = clean
                end
                return
            end
        end
    end
    hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID) capture(optionID, false) end)
    if C_GossipInfo.SelectOptionByIndex then
        hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(optionID) capture(optionID, true) end)
    end
end

GO:InstallSelectionHook()

-- Walk DUI's option buttons and apply our icon override. Used after first
-- GOSSIP_SHOW: even with the hook installed at module load, DUI may render
-- some buttons before our activeForAstalor flag flips to true. This catches
-- those by reading each button's gossipOptionID + name and re-classifying.
function GO:RepaintDUIVisible()
    if not _G.DUIDialogOptionButtonMixin then return end
    local dui = _G.DUIDialogFrame or _G.DialogueUI
    if not dui then return end
    local function visit(frame, depth)
        if depth > 5 then return end
        if frame.gossipOptionID and frame.Icon and frame.Name then
            local label = frame.Name:GetText()
            if label and label ~= "" then
                local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(label) or label
                local tag, kind = GO:ResolveTag(clean)
                if tag ~= "none" then
                    GO:ApplyIcon(frame.Icon, tag)
                    GO:WireDUITooltip(frame, clean, kind)
                end
            end
        end
        for i = 1, frame:GetNumChildren() do
            local c = select(i, frame:GetChildren())
            if c then visit(c, depth + 1) end
        end
    end
    visit(dui, 0)
end

-- Install the DUI hook at module load if DialogueUI is already loaded. This
-- ensures our hook is in place before DUI's first SetGossip call. If DUI
-- loads later, OnGossipShow re-attempts; the hook is idempotent.
GO:InstallDUIHookIfPresent()

-- Hook Blizzard's GossipOptionButtonMixin:Setup so we win the
-- icon-and-size race against Blizzard's per-row binder. Setup() is the
-- per-row initializer called when an option row binds to an option;
-- hooksecurefunc fires AFTER Blizzard's Setup, so our SetTexture + SetSize
-- have the final say.
function GO:InstallBlizzardHookIfPresent()
    if self._blizzHookInstalled then return end
    if not _G.GossipOptionButtonMixin or not _G.GossipOptionButtonMixin.Setup then return end
    self._blizzHookInstalled = true
    hooksecurefunc(_G.GossipOptionButtonMixin, "Setup", function(button, optionInfo)
        if not GO.activeForAstalor then return end
        if not optionInfo or not optionInfo.name then return end
        local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(optionInfo.name) or optionInfo.name
        local tag, kind = GO:ResolveTag(clean)
        if tag == "none" then return end
        if button.Icon then GO:ApplyIcon(button.Icon, tag) end
        GO:WireBlizzTooltip(button, clean, kind)
    end)
end

-- Per-row tooltip hook for Blizzard's gossip rows. Idempotent; tooltipsHooked
-- is a weak-keyed table so released/recycled buttons drop out naturally.
function GO:WireBlizzTooltip(button, name, kind)
    if not button or self.tooltipsHooked[button] then return end
    self.tooltipsHooked[button] = true
    button:HookScript("OnEnter", function(f)
        local lines
        if kind == "difficulty" then
            lines = BuildDifficultyTooltipText(GO.selectedTarget, name)
        elseif kind == "difficulty-any" then
            lines = BuildDifficultyOverallTooltipText(name)
        else
            lines = BuildTooltipText(name)
        end
        if not lines then return end
        if not GameTooltip:IsShown() then
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        end
        GameTooltip:AddLine(" ")
        for _, line in ipairs(lines) do
            GameTooltip:AddLine(line, 1, 1, 1, false)
        end
        GameTooltip:Show()
    end)
end

GO:InstallBlizzardHookIfPresent()

-- ----- decoration (icon mutation, Plumber pattern) -----
function GO:Decorate()
    local options = GossipFrame and GossipFrame.gossipOptions
    if not options then return end

    -- Stash originals so Cleanup can restore.
    self.iconStash = {}
    for i, opt in ipairs(options) do
        self.iconStash[i] = { icon = opt.icon, optionRef = opt }
    end

    for _, opt in ipairs(options) do
        if opt and opt.name then
            local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(opt.name) or opt.name
            local tag = (PHT.Achievements and PHT.Achievements:ClassifyName(clean)) or "none"
            if tag ~= "none" then
                opt.icon = self.ATLAS_BY_TAG[tag]
            end
        end
    end

    if GossipFrame.gossipOptions and GossipFrame.Update then GossipFrame:Update() end
    self:ScaleBlizzardRowIcons()
end

-- Walk Blizzard's gossip ScrollBox after :Update() and scale the icon
-- texture on each row whose option name classifies as "finish" so the
-- gold star pops the same 30% as in DUI mode. Other tags keep base size.
function GO:ScaleBlizzardRowIcons()
    local panel = GossipFrame and GossipFrame.GreetingPanel
    local scrollBox = panel and panel.ScrollBox
    if not scrollBox or not scrollBox.EnumerateFrames then return end
    for _, button in scrollBox:EnumerateFrames() do
        if button and button:IsVisible() and button.Icon then
            local optName
            if button.GetElementData then
                local data = button:GetElementData()
                if data and data.name then optName = data.name end
            end
            if not optName and button.option and button.option.name then
                optName = button.option.name
            end
            if optName then
                local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(optName) or optName
                local tag = (PHT.Achievements and PHT.Achievements:ClassifyName(clean)) or "none"
                if tag ~= "none" then
                    self:ApplyIcon(button.Icon, tag)
                end
            end
        end
    end
end

function GO:RestoreIcons()
    if not self.iconStash or next(self.iconStash) == nil then
        self.iconStash = {}
        return
    end
    for _, stashed in pairs(self.iconStash) do
        if stashed.optionRef then
            stashed.optionRef.icon = stashed.icon
        end
    end
    self.iconStash = {}
    -- Only repaint if Blizzard's gossip frame still has options; under
    -- DialogueUI gossipOptions is nil and GossipFrame:Update crashes.
    if GossipFrame and GossipFrame.gossipOptions and GossipFrame.Update then
        GossipFrame:Update()
    end
end
AchievementMatchesDifficulty = function(achName, difficulty)
    if not achName or not difficulty then return false end
    if difficulty == "Normal" then
        return achName:find("Normal Mode") ~= nil
    elseif difficulty == "Hard" then
        return achName:find("Hard Mode") ~= nil or achName:find("%(Hard%)") ~= nil
    elseif difficulty == "Nightmare" then
        return achName:find("Nightmare Mode") ~= nil or achName:find("%(Nightmare%)") ~= nil
    end
    return false
end

ClassifyDifficulty = function(targetName, difficulty)
    if not targetName or not difficulty then return "none" end
    local A = PHT.Achievements
    if not A or not A.byName then return "none" end
    local refs = A.byName[targetName]
    if not refs then return "none" end

    local matched, hasUnfinished, hasFinish, allComplete = false, false, false, true
    for _, ref in ipairs(refs) do
        local entry = A.byID[ref.achID]
        if entry and entry.name and entry.name:find("^Prey:")
           and AchievementMatchesDifficulty(entry.name, difficulty) then
            matched = true
            if not entry.completed then
                allComplete = false
                local crit = entry.criteria[ref.criterionIndex]
                if crit and not crit.completed then
                    hasUnfinished = true
                    if entry.isOr then
                        hasFinish = true
                    elseif (entry.criteriaTotal - entry.criteriaCompletedCount) == 1 then
                        hasFinish = true
                    end
                end
            end
        end
    end

    if not matched then return "none" end
    if allComplete then return "complete" end
    if hasFinish then return "finish" end
    if hasUnfinished then return "contribute" end
    return "complete"
end

-- Random-hunt mode: no target chosen, classify the difficulty by
-- whether ANY Prey: <difficulty> achievement has remaining work, and
-- whether any of those is one criterion away from completion.
ClassifyDifficultyOverall = function(difficulty)
    if not difficulty then return "none" end
    local A = PHT.Achievements
    if not A or not A.byID then return "none" end

    local matched, hasUnfinished, hasFinish, allComplete = false, false, false, true
    for _, entry in pairs(A.byID) do
        if entry.name and entry.name:find("^Prey:")
           and AchievementMatchesDifficulty(entry.name, difficulty) then
            matched = true
            if not entry.completed then
                allComplete = false
                local remaining = (entry.criteriaTotal or 0) - (entry.criteriaCompletedCount or 0)
                if entry.isOr and remaining > 0 then
                    hasFinish = true
                    hasUnfinished = true
                elseif remaining == 1 then
                    hasFinish = true
                    hasUnfinished = true
                elseif remaining > 0 then
                    hasUnfinished = true
                end
            end
        end
    end

    if not matched then return "none" end
    if allComplete then return "complete" end
    if hasFinish then return "finish" end
    if hasUnfinished then return "contribute" end
    return "complete"
end

BuildDifficultyOverallTooltipText = function(difficulty)
    local A = PHT.Achievements
    if not A or not A.byID then return nil end

    local lines = {
        "|cFFFFD900" .. difficulty .. "|r",
        "|cFFAAAAAArandom hunt -- target unknown|r",
        " ",
    }
    local oneAway, multiAway, done = {}, {}, {}
    for _, entry in pairs(A.byID) do
        if entry.name and entry.name:find("^Prey:")
           and AchievementMatchesDifficulty(entry.name, difficulty) then
            local remaining = (entry.criteriaTotal or 0) - (entry.criteriaCompletedCount or 0)
            if entry.completed then
                table.insert(done, entry)
            elseif entry.isOr or remaining == 1 then
                table.insert(oneAway, entry)
            elseif remaining > 0 then
                table.insert(multiAway, entry)
            else
                table.insert(done, entry)
            end
        end
    end

    if #oneAway == 0 and #multiAway == 0 and #done == 0 then
        table.insert(lines, "|cFFAAAAAA(no Prey achievements at this difficulty)|r")
    end
    if #oneAway > 0 then
        table.insert(lines, "|cFFFFD933One kill from finishing:|r")
        for _, entry in ipairs(oneAway) do
            table.insert(lines, string.format("  |cFFFFFFFF%s|r |cFF888888(%d/%d)|r",
                entry.name, entry.criteriaCompletedCount, entry.criteriaTotal))
        end
    end
    if #multiAway > 0 then
        if #oneAway > 0 then table.insert(lines, " ") end
        table.insert(lines, "|cFFA0C8FFStill in progress:|r")
        for _, entry in ipairs(multiAway) do
            table.insert(lines, string.format("  |cFFFFFFFF%s|r |cFF888888(%d/%d)|r",
                entry.name, entry.criteriaCompletedCount, entry.criteriaTotal))
        end
    end
    if #done > 0 then
        if #oneAway > 0 or #multiAway > 0 then table.insert(lines, " ") end
        table.insert(lines, "|cFF888888Already earned:|r")
        for _, entry in ipairs(done) do
            table.insert(lines, string.format("  |cFF888888%s|r", entry.name))
        end
    end

    table.insert(lines, " ")
    for _, l in ipairs(BuildLegendLines()) do
        table.insert(lines, l)
    end
    return lines
end

BuildDifficultyTooltipText = function(targetName, difficulty)
    if not targetName then
        return {
            "|cFFFFD900" .. difficulty .. "|r",
            " ",
            "|cFFAAAAAA(pick a target on the previous step to see which|r",
            "|cFFAAAAAA achievements this difficulty progresses)|r",
        }
    end
    local A = PHT.Achievements
    local refs = A and A.byName[targetName]
    if not refs then return nil end

    local lines = {
        "|cFFFFD900" .. difficulty .. "|r",
        "|cFFAAAAAAfor target:|r |cFFFFFFFF" .. targetName .. "|r",
        " ",
    }
    local willProgress = {}
    local credited = {}
    for _, ref in ipairs(refs) do
        local entry = A.byID[ref.achID]
        if entry and entry.name and entry.name:find("^Prey:")
           and AchievementMatchesDifficulty(entry.name, difficulty) then
            local crit = entry.criteria[ref.criterionIndex]
            if crit and crit.completed then
                table.insert(credited, entry)
            else
                table.insert(willProgress, entry)
            end
        end
    end

    if #willProgress == 0 and #credited == 0 then
        table.insert(lines, "|cFFAAAAAA(no Prey achievements at this difficulty use this target)|r")
    end
    if #willProgress > 0 then
        table.insert(lines, "|cFFFFD933Will progress:|r")
        for _, entry in ipairs(willProgress) do
            local prog = string.format("(%d/%d)", entry.criteriaCompletedCount, entry.criteriaTotal)
            table.insert(lines, string.format("  |cFFFFFFFF%s|r %s", entry.name, prog))
        end
    end
    if #credited > 0 then
        if #willProgress > 0 then table.insert(lines, " ") end
        table.insert(lines, "|cFF888888Already credited:|r")
        for _, entry in ipairs(credited) do
            local prog = string.format("(%d/%d)", entry.criteriaCompletedCount, entry.criteriaTotal)
            table.insert(lines, string.format("  |cFF888888%s|r %s", entry.name, prog))
        end
    end

    table.insert(lines, " ")
    for _, l in ipairs(BuildLegendLines()) do
        table.insert(lines, l)
    end
    return lines
end

BuildLegendLines = function()
    local function iconLine(tag)
        local size = math.floor(14 * (GO.ICON_SCALE_BY_TAG[tag] or 1.0))
        return string.format("|T%s:%d|t |cFFAAAAAA%s|r",
            GO.ATLAS_BY_TAG[tag], size, GO.LABEL_BY_TAG[tag])
    end
    return {
        "|cFFA0C8FFLegend:|r",
        "  " .. iconLine("finish"),
        "  " .. iconLine("contribute"),
        "  " .. iconLine("complete"),
    }
end

BuildTooltipText = function(name)
    local refs = PHT.Achievements and PHT.Achievements:LookupName(name)
    if not refs or #refs == 0 then return nil end

    -- Split feeds into "killing this will progress" vs "already credited"
    -- (criterion already complete in that achievement). Within "will
    -- progress", further split into achievement-still-active vs cosmetic.
    local willProgress = {}     -- crit not yet done; kill helps
    local credited = {}         -- crit already done

    for _, ref in ipairs(refs) do
        local entry = PHT.Achievements.byID[ref.achID]
        if entry then
            local crit = entry.criteria[ref.criterionIndex]
            if crit and crit.completed then
                table.insert(credited, entry)
            else
                table.insert(willProgress, entry)
            end
        end
    end

    local lines = { "|cFFFFD900" .. name .. "|r", " " }

    if #willProgress > 0 then
        table.insert(lines, "|cFFFFD933Will progress:|r")
        for _, entry in ipairs(willProgress) do
            local color = entry.completed and "|cFF888888" or "|cFFFFFFFF"
            local prog = string.format("(%d/%d)", entry.criteriaCompletedCount, entry.criteriaTotal)
            table.insert(lines, string.format("  %s%s|r %s", color, entry.name, prog))
        end
    end

    if #credited > 0 then
        if #willProgress > 0 then table.insert(lines, " ") end
        table.insert(lines, "|cFF888888Already credited:|r")
        for _, entry in ipairs(credited) do
            local prog = string.format("(%d/%d)", entry.criteriaCompletedCount, entry.criteriaTotal)
            table.insert(lines, string.format("  |cFF888888%s|r %s", entry.name, prog))
        end
    end

    -- Append the legend
    table.insert(lines, " ")
    for _, l in ipairs(BuildLegendLines()) do
        table.insert(lines, l)
    end
    return lines
end

-- DUI option buttons own their tooltip handler. We attach a separate
-- GameTooltip beside DUI's TooltipFrame so the player gets our feeds list
-- + legend without colliding with DUI's existing tooltip system.
function GO:WireDUITooltip(button, name, kind)
    if not button or self.tooltipsHooked[button] then return end
    self.tooltipsHooked[button] = true
    button:HookScript("OnEnter", function(f)
        local lines
        if kind == "difficulty" then
            lines = BuildDifficultyTooltipText(GO.selectedTarget, name)
        elseif kind == "difficulty-any" then
            lines = BuildDifficultyOverallTooltipText(name)
        else
            lines = BuildTooltipText(name)
        end
        if not lines then return end
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        for _, line in ipairs(lines) do
            GameTooltip:AddLine(line, 1, 1, 1, false)
        end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Walk currently-visible Blizzard gossip option rows and apply the same
-- logic Setup-hook applies. Catches rows that were bound before our hook
-- installed (e.g. on the very first gossip after /reload).
function GO:RewireBlizzardVisible()
    local panel = GossipFrame and GossipFrame.GreetingPanel
    local scrollBox = panel and panel.ScrollBox
    if not scrollBox or not scrollBox.EnumerateFrames then return end
    for _, button in scrollBox:EnumerateFrames() do
        if button and button:IsVisible() then
            local optionInfo
            if button.GetElementData then
                local data = button:GetElementData()
                if data and data.info then optionInfo = data.info end
            end
            if optionInfo and optionInfo.name then
                local clean = PHT.Achievements and PHT.Achievements.StripGossipPrefix(optionInfo.name) or optionInfo.name
                local tag, kind = GO:ResolveTag(clean)
                if tag ~= "none" then
                    if button.Icon then GO:ApplyIcon(button.Icon, tag) end
                    GO:WireBlizzTooltip(button, clean, kind)
                end
            end
        end
    end
end
