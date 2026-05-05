-- ============================================================
-- PHT_Panel.lua
-- Main window. Will become tabbed (Status | Targets) in subsequent tasks.
-- ============================================================

local PHT = _G.PreyHuntTracker

local PANEL_WIDTH = 320
local PANEL_HEIGHT = 520
local TITLE_HEIGHT = 28
local PADDING = 10

function PHT.CreatePanel()
    if PHT.panel then return PHT.panel end

    local f = CreateFrame("Frame", "PreyHuntTrackerPanel", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 300, 100)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.1, 0.92)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -8)
    title:SetText("Prey Hunt Tracker")
    title:SetTextColor(0, 0.85, 0.85)

    -- State indicator dot (next to title)
    local dot = f:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
    dot:SetSize(12, 12)
    dot:SetPoint("LEFT", title, "RIGHT", 8, 0)
    dot:SetVertexColor(0.5, 0.5, 0.5, 1)
    f.stateIndicator = dot

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    -- Tab strip
    local TAB_STRIP_HEIGHT = 24
    local tabStrip = CreateFrame("Frame", nil, f)
    tabStrip:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -(TITLE_HEIGHT + 4))
    tabStrip:SetPoint("RIGHT", f, "RIGHT", -PADDING, 0)
    tabStrip:SetHeight(TAB_STRIP_HEIGHT)
    f.tabStrip = tabStrip

    local function MakeTab(label, anchor)
        local b = CreateFrame("Button", nil, tabStrip, "UIPanelButtonTemplate")
        b:SetSize(80, TAB_STRIP_HEIGHT)
        b:SetText(label)
        if anchor then
            b:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
        else
            b:SetPoint("LEFT", tabStrip, "LEFT", 0, 0)
        end
        return b
    end

    f.tabStatus = MakeTab("Status")
    f.tabTargets = MakeTab("Targets", f.tabStatus)

    -- Content area below the tab strip
    local contentTop = -(TITLE_HEIGHT + 4 + TAB_STRIP_HEIGHT + 4)

    -- Status content (FontString directly; no scroll)
    local statusContent = CreateFrame("Frame", nil, f)
    statusContent:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, contentTop)
    statusContent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, PADDING)

    local text = statusContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", statusContent, "TOPLEFT", 0, 0)
    text:SetPoint("RIGHT", statusContent, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(2)

    statusContent.text = text
    f.statusContent = statusContent
    f.contentText = text         -- backwards compat for RefreshDisplay
    f.contentFrame = statusContent

    -- Targets content
    local targetsContent = CreateFrame("Frame", nil, f)
    targetsContent:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, contentTop)
    targetsContent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, PADDING)
    targetsContent:Hide()
    f.targetsContent = targetsContent

    -- View toggle (By Achievement / By Target)
    local TOGGLE_HEIGHT = 22
    local toggleStrip = CreateFrame("Frame", nil, targetsContent)
    toggleStrip:SetPoint("TOPLEFT", targetsContent, "TOPLEFT", 0, 0)
    toggleStrip:SetPoint("RIGHT", targetsContent, "RIGHT", 0, 0)
    toggleStrip:SetHeight(TOGGLE_HEIGHT)

    local btnByAch = CreateFrame("Button", nil, toggleStrip, "UIPanelButtonTemplate")
    btnByAch:SetSize(110, TOGGLE_HEIGHT)
    btnByAch:SetText("By Achievement")
    btnByAch:SetPoint("LEFT", toggleStrip, "LEFT", 0, 0)

    local btnByTarget = CreateFrame("Button", nil, toggleStrip, "UIPanelButtonTemplate")
    btnByTarget:SetSize(80, TOGGLE_HEIGHT)
    btnByTarget:SetText("By Target")
    btnByTarget:SetPoint("LEFT", btnByAch, "RIGHT", 4, 0)

    local progressLabel = toggleStrip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressLabel:SetPoint("RIGHT", toggleStrip, "RIGHT", -4, 0)
    progressLabel:SetText("Earned: 0 / 0")
    targetsContent.progressLabel = progressLabel

    -- ScrollBox + ScrollBar
    local scrollBox = CreateFrame("Frame", nil, targetsContent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", toggleStrip, "BOTTOMLEFT", 0, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", targetsContent, "BOTTOMRIGHT", -16, 0)

    local scrollBar = CreateFrame("EventFrame", nil, targetsContent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, data)
        if data.kind == "achievement_header" then return 36 end
        if data.kind == "achievement_reward"  then return 16 end
        if data.kind == "criterion_pill"      then return 20 end
        if data.kind == "target_row"          then return 24 end
        return 20
    end)
    view:SetElementInitializer("Frame", function(frame, data)
        PHT.Panel:_InitElement(frame, data)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    targetsContent.scrollBox = scrollBox
    targetsContent.scrollBar = scrollBar
    targetsContent.view = view
    targetsContent.dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(targetsContent.dataProvider)

    -- View state
    targetsContent.viewMode = "achievement"        -- "achievement" | "target"
    targetsContent.expanded = {}                   -- [achID] = true if expanded
    btnByAch:SetScript("OnClick", function()
        targetsContent.viewMode = "achievement"
        PHT.Panel:RefreshTargets()
    end)
    btnByTarget:SetScript("OnClick", function()
        targetsContent.viewMode = "target"
        PHT.Panel:RefreshTargets()
    end)

    -- Tab switching
    local function SetTab(which)
        if which == "status" then
            statusContent:Show(); targetsContent:Hide()
            f.tabStatus:Disable(); f.tabTargets:Enable()
        else
            statusContent:Hide(); targetsContent:Show()
            f.tabStatus:Enable(); f.tabTargets:Disable()
            if PHT.Panel and PHT.Panel.RefreshTargets then PHT.Panel:RefreshTargets() end
        end
        f.activeTab = which
    end
    f.SetTab = SetTab
    f.tabStatus:SetScript("OnClick", function() SetTab("status") end)
    f.tabTargets:SetScript("OnClick", function() SetTab("targets") end)
    SetTab("status")

    -- OnShow -> trigger achievement build for Targets tab readiness
    f:SetScript("OnShow", function()
        if PHT.Achievements then PHT.Achievements:EnsureBuilt() end
    end)

    f:Hide()
    PHT.panel = f
    return f
end

local STATE_HEX = {
    [0] = "FF888888",
    [1] = "FF6FA8FF",
    [2] = "FFFFD933",
    [3] = "FFFF3333",
}

function PHT.RefreshDisplay()
    local panel = PHT.panel
    if not panel or not panel:IsShown() then return end

    local data = PHT.lastData
    local lines = {}

    local function Section(text)
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = "|cFF00D9D9" .. text .. "|r"
    end
    local function Row(label, value)
        lines[#lines + 1] = "  |cFFAABBCC" .. label .. "|r  " .. (value or "")
    end
    local function Note(text)
        lines[#lines + 1] = "  " .. text
    end

    -- Hunt
    Section("HUNT")
    if data.widgetID and data.widgetInfo then
        local info = data.widgetInfo
        local shown = info.shownState or 0
        if shown == 0 then
            Row("State", "|cFF888888Awaiting hunt start|r")
        else
            local st = info.progressState or 0
            local stateLabel = PHT.STATE_LABELS[st] or "Unknown"
            Row("State", string.format("|c%s%s|r", STATE_HEX[st] or STATE_HEX[0], stateLabel))
        end
    else
        Row("State", "|cFF888888Not at hunt|r")
    end
    if data.hunts then
        local h = data.hunts
        local color = h.barValue > 0 and "FF55FF55" or "FFFF8888"
        Row("Hunts", string.format("|c%s%d / %d|r", color, h.barValue, h.barMax))
    else
        Row("Hunts", "|cFF888888-|r")
    end
    if data.navDistance and data.navDistance > 0 then
        Row("Distance", string.format("|cFFFFD900%.0f yd|r", data.navDistance))
    end

    -- Preyseeker
    local cur = data.currency or {}
    if cur.faction or cur.remnant then
        Section("PREYSEEKER")
        if cur.faction then
            local f = cur.faction
            Row("Renown", string.format("|cFFFFD900%d|r  |cFF888888(%d%% to next)|r",
                f.renownLevel, f.tierPct))
        end
        if cur.remnant then
            Row("Anguish", string.format("|cFFFF8888%s|r", tostring(cur.remnant.quantity)))
        end
    end

    -- Achievements
    if PHT.Achievements and PHT.Achievements.built then
        local A = PHT.Achievements
        local earned, total = A:CountEarned()
        local pct = total > 0 and math.floor(earned / total * 100) or 0
        local pointsEarned, pointsTotal = 0, 0
        for _, e in pairs(A.byID) do
            if not e.hidden or e.completed then
                pointsTotal = pointsTotal + (e.points or 0)
                if e.completed then pointsEarned = pointsEarned + (e.points or 0) end
            end
        end
        local remainingKills = 0
        local finishOpportunities = 0
        for name, refs in pairs(A.byName) do
            -- only count names that feed at least one "Prey: ..." kill achievement
            local hasPreyTarget = false
            for _, ref in ipairs(refs) do
                local feeding = A.byID[ref.achID]
                if feeding and feeding.name and feeding.name:find("^Prey:") then
                    hasPreyTarget = true
                    break
                end
            end
            if hasPreyTarget then
                local tag = A:ClassifyName(name)
                if tag == "contribute" or tag == "finish" then
                    remainingKills = remainingKills + 1
                end
                if tag == "finish" then
                    finishOpportunities = finishOpportunities + 1
                end
            end
        end

        Section("ACHIEVEMENTS")
        Row("Earned", string.format("|cFFFFD900%d / %d|r  |cFF888888(%d%%)|r",
            earned, total, pct))
        Row("Points", string.format("|cFFFFD900%d|r  |cFF888888of %d|r",
            pointsEarned, pointsTotal))
        Row("Targets left", string.format("|cFFFFD900%d|r  |cFF888888NPCs to kill|r",
            remainingKills))
        if finishOpportunities > 0 then
            Row("Finishers", string.format("|cFFFFD933%d|r  |cFF888888kills that complete an achievement|r",
                finishOpportunities))
        end
    end

    -- Quest
    Section("QUEST")
    if data.questID and data.questID > 0 then
        Row("Title", data.questTitle or "(unknown)")
        if data.questObjectives then
            for _, obj in ipairs(data.questObjectives) do
                local status = obj.finished and "|cFF55FF55done|r" or
                    string.format("|cFFFFD900%d/%d|r", obj.numFulfilled or 0, obj.numRequired or 0)
                Note(string.format("%s  %s", status, obj.text or ""))
            end
        end
    else
        Note("|cFF888888None active|r")
    end

    -- Torment
    Section("TORMENT")
    if data.torment then
        local t = data.torment
        local diffLabel = t.isNightmare and "|cFFFF4444Nightmare|r" or "|cFFFF8800Hard|r"
        Row("Mode", diffLabel)
        Row("Stacks", string.format("|cFFFF4444+%d%%|r  |cFF888888(%d x %d%%)|r",
            t.totalPct, t.stacks, t.pctPerStack))
        if t.expires and t.expires > 0 then
            local remaining = t.expires - GetTime()
            if remaining > 0 then
                Row("Expires", string.format("|cFFFFD900%.0fs|r", remaining))
            end
        end
    else
        Note("|cFF55FF55Inactive|r")
    end

    -- Update header state indicator (gray when widget is in awaiting state)
    local st = data.progressState or 0
    if data.widgetInfo and (data.widgetInfo.shownState or 0) == 0 then
        st = 0
    end
    local HEADER_TEX = {
        [0] = "Interface\\COMMON\\Indicator-Gray",
        [1] = "Interface\\COMMON\\Indicator-Gray",
        [2] = "Interface\\COMMON\\Indicator-Yellow",
        [3] = "Interface\\COMMON\\Indicator-Red",
    }
    panel.stateIndicator:SetTexture(HEADER_TEX[st] or HEADER_TEX[0])
    if st == 1 then
        panel.stateIndicator:SetVertexColor(0.4, 0.7, 1.0, 1)
    else
        panel.stateIndicator:SetVertexColor(1, 1, 1, 1)
    end

    local output = table.concat(lines, "\n")
    panel.contentText:SetText(output)
    panel.contentFrame:SetHeight(panel.contentText:GetStringHeight() + 20)
end

-- ============================================================
-- PHT.Panel namespace (entry points for other modules)
-- ============================================================

local COLOR_GOLD   = { 1.0, 0.82, 0.0 }
local COLOR_GREY   = { 0.55, 0.55, 0.55 }
local COLOR_GREEN  = { 0.4, 1.0, 0.4 }
local COLOR_CYAN   = { 0.3, 0.85, 1.0 }
local COLOR_DIM    = { 0.4, 0.4, 0.4 }

local function MakeFontString(parent, layer, template, color)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontNormal")
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

PHT.Panel = PHT.Panel or {}

function PHT.Panel:Show()
    PHT.CreatePanel():Show()
end

function PHT.Panel:IsShown()
    return PHT.panel and PHT.panel:IsShown()
end

function PHT.Panel:_InitElement(frame, data)
    -- Clean any prior content (frames are recycled)
    if frame.PHT_initialized then
        for _, region in ipairs(frame.PHT_regions or {}) do region:Hide() end
    end
    frame.PHT_regions = {}
    frame.PHT_initialized = true

    -- Wipe handlers from any prior bind. Frames are recycled across kinds
    -- (a target_row's OnEnter survives when the frame is later rebound as
    -- an achievement_header), so kind-specific init starts from a clean slate.
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
    frame:SetScript("OnMouseUp", nil)
    frame:EnableMouse(false)

    if data.kind == "achievement_header" then
        self:_InitAchHeader(frame, data)
    elseif data.kind == "achievement_reward" then
        self:_InitAchReward(frame, data)
    elseif data.kind == "criterion_pill" then
        self:_InitCriterionPill(frame, data)
    elseif data.kind == "target_row" then
        self:_InitTargetRow(frame, data)
    end
end

-- Per-kind initializers -- _InitTargetRow body arrives in Task 12.
function PHT.Panel:_InitAchHeader(frame, data)
    frame:SetHeight(36)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", frame, "LEFT", 4, 0)
    if data.icon then icon:SetTexture(data.icon) end
    table.insert(frame.PHT_regions, icon)

    local nameFS = MakeFontString(frame, "OVERLAY", "GameFontNormal",
                                  data.completed and COLOR_DIM or COLOR_GOLD)
    nameFS:SetPoint("LEFT", icon, "RIGHT", 6, 6)
    nameFS:SetText(data.name .. (data.isOr and "  |cFFA0A0FF[OR]|r" or ""))
    table.insert(frame.PHT_regions, nameFS)

    local progFS = MakeFontString(frame, "OVERLAY", "GameFontHighlightSmall", COLOR_GREY)
    progFS:SetPoint("LEFT", nameFS, "LEFT", 0, -14)
    if data.reqQuantity and data.reqQuantity > 1 then
        progFS:SetText(string.format("%d / %d", data.quantity or 0, data.reqQuantity))
    else
        progFS:SetText(string.format("%d / %d", data.criteriaDone, data.criteriaTotal))
    end
    table.insert(frame.PHT_regions, progFS)

    -- Expand chevron
    local chev = MakeFontString(frame, "OVERLAY", "GameFontNormalLarge", COLOR_GREY)
    chev:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    chev:SetText(data.expanded and "-" or "+")
    table.insert(frame.PHT_regions, chev)

    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        local panel = PHT.panel
        if not panel then return end
        local tc = panel.targetsContent
        tc.expanded[data.achID] = not tc.expanded[data.achID]
        PHT.Panel:RefreshTargets()
    end)
end

function PHT.Panel:_InitAchReward(frame, data)
    frame:SetHeight(16)
    local fs = MakeFontString(frame, "OVERLAY", "GameFontHighlightSmall", { 0.85, 0.7, 1.0 })
    fs:SetPoint("LEFT", frame, "LEFT", 40, 0)
    fs:SetText("|cFFD0A0FF" .. data.rewardText .. "|r")
    table.insert(frame.PHT_regions, fs)
end

function PHT.Panel:_InitCriterionPill(frame, data)
    frame:SetHeight(20)

    local glyph = MakeFontString(frame, "OVERLAY", "GameFontNormal",
        data.completed and COLOR_GREEN or (data.isLastNeeded and COLOR_GOLD) or COLOR_CYAN)
    glyph:SetPoint("LEFT", frame, "LEFT", 40, 0)
    glyph:SetText(data.completed and "[v]" or (data.isLastNeeded and "[!]" or "[ ]"))
    table.insert(frame.PHT_regions, glyph)

    local nameFS = MakeFontString(frame, "OVERLAY", "GameFontHighlight",
                                  data.completed and COLOR_GREY or { 1, 1, 1 })
    nameFS:SetPoint("LEFT", glyph, "RIGHT", 6, 0)
    nameFS:SetText(data.name)
    table.insert(frame.PHT_regions, nameFS)

    -- Counter for objective-style criteria (Cook 100 things, catch 100 fish, etc.)
    if data.reqQuantity and data.reqQuantity > 1 then
        local countFS = MakeFontString(frame, "OVERLAY", "GameFontHighlightSmall",
                                       data.completed and COLOR_GREY or COLOR_GOLD)
        countFS:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        countFS:SetText(string.format("%d / %d", data.quantity or 0, data.reqQuantity))
        table.insert(frame.PHT_regions, countFS)
    end
end

function PHT.Panel:_InitTargetRow(frame, data)
    frame:SetHeight(24)

    local nameFS = MakeFontString(frame, "OVERLAY", "GameFontNormal",
                                  data.neededCount > 0 and { 1, 1, 1 } or COLOR_DIM)
    nameFS:SetPoint("LEFT", frame, "LEFT", 8, 0)
    nameFS:SetText(data.name)
    table.insert(frame.PHT_regions, nameFS)

    local countFS = MakeFontString(frame, "OVERLAY", "GameFontHighlightSmall",
                                   data.neededCount > 0 and COLOR_GOLD or COLOR_GREEN)
    countFS:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    if data.neededCount > 0 then
        countFS:SetText(string.format("Needed by %d", data.neededCount))
    else
        countFS:SetText("All earned")
    end
    table.insert(frame.PHT_regions, countFS)

    -- Tooltip on hover
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:AddLine(data.name, 1, 1, 1)
        GameTooltip:AddLine("Counts toward:", 0.7, 0.85, 1)
        for _, ach in ipairs(data.achievements) do
            local color = ach.completed and { 0.55, 0.55, 0.55 } or { 1, 1, 1 }
            GameTooltip:AddLine(
                string.format("  %s %s",
                    ach.completed and "|cFF55FF55+|r" or "|cFFFFFFFF-|r",
                    ach.name),
                color[1], color[2], color[3])
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function PHT.Panel:RefreshTargets()
    local panel = PHT.panel
    if not panel or not panel.targetsContent then return end
    local tc = panel.targetsContent
    if PHT.Achievements then PHT.Achievements:EnsureBuilt() end

    local earned, total = 0, 0
    if PHT.Achievements then earned, total = PHT.Achievements:CountEarned() end
    tc.progressLabel:SetText(string.format("Earned: %d / %d", earned, total))

    tc.dataProvider:Flush()

    if not PHT.Achievements or not PHT.Achievements.built then
        return
    end

    if tc.viewMode == "achievement" then
        self:_PopulateByAchievement(tc)
    else
        self:_PopulateByTarget(tc)
    end
end

function PHT.Panel:_PopulateByAchievement(tc)
    local entries = {}
    for _, e in pairs(PHT.Achievements.byID) do
        if not e.hidden or e.completed then
            table.insert(entries, e)
        end
    end
    table.sort(entries, function(a, b)
        if a.completed ~= b.completed then return not a.completed end
        return (a.name or "") < (b.name or "")
    end)

    for _, entry in ipairs(entries) do
        local expanded = tc.expanded[entry.id]
        if expanded == nil then
            -- Default: unearned expanded, earned collapsed
            expanded = not entry.completed
        end

        -- Single-criterion progress achievements (Cook 100, Catch 100, Kill 50)
        -- collapse the criterion's quantity/reqQuantity into the header itself
        -- so the header shows e.g. "0 / 100" instead of the meaningless "0 / 1".
        local singleCrit = entry.criteria and entry.criteria[1]
        local headerQuantity, headerReqQuantity
        local skipCriterionPill = false
        if entry.criteriaTotal == 1 and singleCrit and (singleCrit.reqQuantity or 0) > 1 then
            headerQuantity = singleCrit.quantity or 0
            headerReqQuantity = singleCrit.reqQuantity
            skipCriterionPill = true   -- header already conveys it
        end

        tc.dataProvider:Insert({
            kind = "achievement_header",
            achID = entry.id,
            name = entry.name,
            icon = entry.icon,
            completed = entry.completed,
            isOr = entry.isOr,
            criteriaDone = entry.criteriaCompletedCount,
            criteriaTotal = entry.criteriaTotal,
            quantity = headerQuantity,
            reqQuantity = headerReqQuantity,
            description = entry.description,
            expanded = expanded,
        })

        if expanded then
            if entry.rewardText and entry.rewardText ~= "" then
                tc.dataProvider:Insert({
                    kind = "achievement_reward",
                    rewardText = entry.rewardText,
                })
            end

            -- Show description as a fallback row for single-crit achievements
            -- where the criterion text would be empty/redundant.
            if skipCriterionPill and entry.description and entry.description ~= "" then
                tc.dataProvider:Insert({
                    kind = "achievement_reward",       -- reuse 16px row template
                    rewardText = entry.description,
                })
            end

            if not skipCriterionPill then
                local unfinishedCount = entry.criteriaTotal - entry.criteriaCompletedCount
                for _, crit in ipairs(entry.criteria) do
                    local isLastNeeded = false
                    if not crit.completed and not entry.completed then
                        if entry.isOr then
                            isLastNeeded = true
                        elseif unfinishedCount == 1 then
                            isLastNeeded = true
                        end
                    end
                    tc.dataProvider:Insert({
                        kind = "criterion_pill",
                        name = (crit.name and crit.name ~= "") and crit.name or entry.description or "(criterion)",
                        completed = crit.completed,
                        isLastNeeded = isLastNeeded,
                        quantity = crit.quantity,
                        reqQuantity = crit.reqQuantity,
                    })
                end
            end
        end
    end
end

local function IsPreyTargetAchievement(entry)
    -- "Prey: ..." titled achievements are the named-NPC kill ones.
    -- Objective-style achievements (Kitchen Nightmare, Look I'm Just
    -- Trying To Fish Here, I'm Good At What I Do, Midnight Hunter, etc.)
    -- are excluded from the By Target view.
    return entry and entry.name and entry.name:find("^Prey:") ~= nil
end

function PHT.Panel:_PopulateByTarget(tc)
    local rows = {}
    for name, refs in pairs(PHT.Achievements.byName) do
        local achievements = {}
        local neededCount = 0
        for _, ref in ipairs(refs) do
            local entry = PHT.Achievements.byID[ref.achID]
            if IsPreyTargetAchievement(entry) then
                table.insert(achievements, {
                    achID = entry.id,
                    name = entry.name,
                    completed = entry.completed,
                })
                if not entry.completed then
                    local crit = entry.criteria[ref.criterionIndex]
                    if crit and not crit.completed then
                        neededCount = neededCount + 1
                    end
                end
            end
        end
        if #achievements > 0 then
            table.sort(achievements, function(a, b) return a.name < b.name end)
            table.insert(rows, {
                name = name,
                neededCount = neededCount,
                achievements = achievements,
            })
        end
    end
    table.sort(rows, function(a, b)
        if a.neededCount ~= b.neededCount then return a.neededCount > b.neededCount end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do
        tc.dataProvider:Insert({
            kind = "target_row",
            name = row.name,
            neededCount = row.neededCount,
            achievements = row.achievements,
        })
    end
end
