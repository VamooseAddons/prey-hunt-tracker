PreyHuntTracker = PreyHuntTracker or {}
local PHT = PreyHuntTracker

local ADDON_TAG = "|cFF00D9D9[Prey Hunt Tracker]|r"
PHT.lastData = {}

-- ============================================================
-- Constants
-- ============================================================

local TORMENT_SPELL_ID = 1245570       -- Hard: 2% per stack, max 10
local TORMENT_NIGHTMARE_ID = 1245521   -- Nightmare: 4% per stack

local CURRENCY_REMNANT = 3392          -- Remnant of Anguish (vendor currency)
local CURRENCY_PREYSEEKER = 3387       -- Preyseeker's Journey (rep progress)
local FACTION_PREYSEEKER = 2764        -- Prey: Season 1

local WEEKLY_FULL_REWARD = 1000        -- Preyseeker's Journey per efficient hunt
local WEEKLY_EFFICIENT_CAP = 4         -- First 4 hunts give full reward
local ASTALOR_NPC_ID = 246231          -- Astalor Bloodsworn (Silvermoon, Prey HQ)

-- ============================================================
-- Unit GUID helpers
-- ============================================================

function PHT.GetUnitNpcID(unit)
    local guid = UnitGUID(unit)
    if not guid then return nil end
    -- pcall around string.split: PLAYER_TARGET_CHANGED can fire from a
    -- tainted execution path (TargetNearestEnemy secure action) where
    -- the returned GUID is a "secret string" and string operations on
    -- it raise an error.
    local ok, _, _, _, _, _, npcIDStr = pcall(string.split, "-", guid)
    if not ok then return nil end
    return tonumber(npcIDStr)
end

PHT.ASTALOR_NPC_ID = ASTALOR_NPC_ID    -- exposed so other modules can read it

-- ============================================================
-- Widget Discovery
-- ============================================================

local function IsPreyHuntWidget(widgetInfo)
    return widgetInfo and widgetInfo.widgetType == Enum.UIWidgetVisualizationType.PreyHuntProgress
end

local WIDGET_SET_ACCESSORS = {
    "GetTopCenterWidgetSetID",
    "GetObjectiveTrackerWidgetSetID",
    "GetPowerBarWidgetSetID",
    "GetBelowMinimapWidgetSetID",
}

function PHT.ScanForPreyWidget()
    if PHT.trackedWidgetID then
        local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(PHT.trackedWidgetID)
        if info then return PHT.trackedWidgetID end
        PHT.trackedWidgetID = nil
    end

    for _, funcName in ipairs(WIDGET_SET_ACCESSORS) do
        local fn = C_UIWidgetManager[funcName]
        if fn then
            local setID = fn()
            if setID then
                local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
                if widgets then
                    for _, w in ipairs(widgets) do
                        if w.widgetType == Enum.UIWidgetVisualizationType.PreyHuntProgress then
                            PHT.trackedWidgetID = w.widgetID
                            return w.widgetID
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Hunts Available Widget Discovery
-- ============================================================

PHT.huntsWidgetID = nil

function PHT.ScanForHuntsWidget()
    -- Check cached widget first
    if PHT.huntsWidgetID then
        local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(PHT.huntsWidgetID)
        if info then return PHT.huntsWidgetID end
        PHT.huntsWidgetID = nil
    end

    for _, funcName in ipairs(WIDGET_SET_ACCESSORS) do
        local fn = C_UIWidgetManager[funcName]
        if fn then
            local setID = fn()
            if setID then
                local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
                if widgets then
                    for _, w in ipairs(widgets) do
                        if w.widgetType == Enum.UIWidgetVisualizationType.StatusBar then
                            local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(w.widgetID)
                            if info and info.text and info.text:find("Hunt") then
                                PHT.huntsWidgetID = w.widgetID
                                return w.widgetID
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function PHT.GetHuntsAvailable()
    local widgetID = PHT.ScanForHuntsWidget()
    if not widgetID then return nil end
    local info = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(widgetID)
    if not info then return nil end
    return {
        widgetID = widgetID,
        text = info.text,
        barValue = info.barValue,
        barMin = info.barMin,
        barMax = info.barMax,
        tooltip = info.tooltip,
        overrideBarText = info.overrideBarText,
    }
end

-- ============================================================
-- Torment Debuff
-- ============================================================

function PHT.GetTormentInfo()
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end
    -- Check Hard first, then Nightmare
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(TORMENT_SPELL_ID)
    local pctPerStack = 2
    if not aura then
        aura = C_UnitAuras.GetPlayerAuraBySpellID(TORMENT_NIGHTMARE_ID)
        pctPerStack = 4
    end
    if aura then
        local stacks = aura.applications or 0
        return {
            stacks = stacks,
            pctPerStack = pctPerStack,
            totalPct = stacks * pctPerStack,
            duration = aura.duration or 0,
            expires = aura.expirationTime or 0,
            spellID = aura.spellId,
            name = aura.name,
            isNightmare = (pctPerStack == 4),
        }
    end
    return nil
end

-- ============================================================
-- Currency & Reputation
-- ============================================================

function PHT.GetCurrencyData()
    local data = {}

    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        -- Remnant of Anguish
        local remnant = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_REMNANT)
        if remnant then
            data.remnant = {
                quantity = remnant.quantity or 0,
                maxQuantity = remnant.maxQuantity or 0,
                name = remnant.name,
                iconFileID = remnant.iconFileID,
            }
        end

        -- Preyseeker's Journey (rep currency)
        local preyseeker = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_PREYSEEKER)
        if preyseeker then
            data.preyseeker = {
                quantity = preyseeker.quantity or 0,
                maxQuantity = preyseeker.maxQuantity or 0,
                totalEarned = preyseeker.totalEarned or 0,
                name = preyseeker.name,
                iconFileID = preyseeker.iconFileID,
            }
        end
    end

    -- Preyseeker's Journey is a Major Faction (Renown)
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local majorData = C_MajorFactions.GetMajorFactionData(FACTION_PREYSEEKER)
        if majorData then
            local earned = majorData.renownReputationEarned or 0
            local threshold = majorData.renownLevelThreshold or 1
            data.faction = {
                name = majorData.name,
                renownLevel = majorData.renownLevel or 0,
                tierProgress = earned,
                tierMax = threshold,
                tierPct = threshold > 0 and math.floor(earned / threshold * 100) or 100,
            }
        end
    end

    return data
end

-- ============================================================
-- State Definitions
-- ============================================================

local STATE_LABELS = {
    [0] = "Hidden",
    [1] = "Cold",
    [2] = "Warm",
    [3] = "Hot",
}

local STATE_COLORS = {
    [0] = { 0.5, 0.5, 0.5 },
    [1] = { 0.3, 0.5, 1.0 },
    [2] = { 1.0, 0.85, 0.2 },
    [3] = { 1.0, 0.15, 0.15 },
}

PHT.STATE_LABELS = STATE_LABELS
PHT.STATE_COLORS = STATE_COLORS

-- ============================================================
-- Widget Overlay (anchored under Blizzard widget)
-- ============================================================

PHT.overlayEnabled = true

function PHT.FindBlizzardWidgetFrame(widgetID)
    if not widgetID then return nil end
    local containers = {}
    if UIWidgetTopCenterContainerFrame then containers[#containers+1] = UIWidgetTopCenterContainerFrame end
    if UIWidgetBelowMinimapContainerFrame then containers[#containers+1] = UIWidgetBelowMinimapContainerFrame end
    if UIWidgetObjectiveTrackerContainerFrame then containers[#containers+1] = UIWidgetObjectiveTrackerContainerFrame end
    if UIWidgetPowerBarContainerFrame then containers[#containers+1] = UIWidgetPowerBarContainerFrame end

    for _, container in ipairs(containers) do
        if container.widgetFrames then
            local frame = container.widgetFrames[widgetID]
            if frame then return frame end
        end
        for i = 1, container:GetNumChildren() do
            local child = select(i, container:GetChildren())
            if child and child.widgetID == widgetID then return child end
        end
    end
    return nil
end

local DOT_SIZE = 10
local DOT_SPACING = 6
local DOT_ACTIVE_SIZE = 14
local NUM_STATES = 4 -- 0 through 3

function PHT.CreateWidgetOverlay()
    if PHT.widgetOverlay then return PHT.widgetOverlay end

    local f = CreateFrame("Frame", "PreyHuntTrackerOverlay", UIParent)
    local totalWidth = NUM_STATES * DOT_SIZE + (NUM_STATES - 1) * DOT_SPACING
    f:SetSize(totalWidth + 20, 52)

    -- Dot strip
    f.dots = {}
    local dotRow = CreateFrame("Frame", nil, f)
    dotRow:SetSize(totalWidth, DOT_ACTIVE_SIZE)
    dotRow:SetPoint("TOP", f, "TOP", 0, 0)
    f.dotRow = dotRow

    for i = 0, NUM_STATES - 1 do
        local dot = dotRow:CreateTexture(nil, "ARTWORK")
        dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        if i == 0 then
            dot:SetPoint("LEFT", dotRow, "LEFT", 0, 0)
        else
            dot:SetPoint("LEFT", f.dots[i - 1], "RIGHT", DOT_SPACING, 0)
        end
        f.dots[i] = dot
    end

    -- State label below dots
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", dotRow, "BOTTOM", 0, -3)
    label:SetJustifyH("CENTER")
    f.stateLabel = label

    -- Torment label below state
    local tormentLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tormentLabel:SetPoint("TOP", label, "BOTTOM", 0, -2)
    tormentLabel:SetJustifyH("CENTER")
    f.tormentLabel = tormentLabel

    f:Hide()
    PHT.widgetOverlay = f
    return f
end

function PHT.UpdateWidgetOverlay()
    local data = PHT.lastData
    local blizzFrame = PHT.overlayEnabled and data.widgetID and PHT.FindBlizzardWidgetFrame(data.widgetID)
    if not blizzFrame or not blizzFrame:IsShown() then
        if PHT.widgetOverlay then PHT.widgetOverlay:Hide() end
        return
    end

    local overlay = PHT.CreateWidgetOverlay()
    overlay:SetParent(blizzFrame)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOP", blizzFrame, "BOTTOM", 0, -4)

    local state = data.progressState or 0
    if data.widgetInfo and (data.widgetInfo.shownState or 0) == 0 then
        state = 0   -- widget is awaiting hunt start; treat as Hidden visually
    end

    -- Update dots: Gray=hidden, Gray+blue tint=cold, Yellow=warm, Red=hot
    local DOT_TEXTURES = {
        [0] = "Interface\\COMMON\\Indicator-Gray",
        [1] = "Interface\\COMMON\\Indicator-Gray",
        [2] = "Interface\\COMMON\\Indicator-Yellow",
        [3] = "Interface\\COMMON\\Indicator-Red",
    }
    for i = 0, NUM_STATES - 1 do
        local dot = overlay.dots[i]
        if i <= state then
            dot:SetTexture(DOT_TEXTURES[i])
            if i == 1 then
                dot:SetVertexColor(0.4, 0.7, 1.0, 1) -- bright blue on gray
            else
                dot:SetVertexColor(1, 1, 1, 1)
            end
            dot:SetSize(i == state and DOT_ACTIVE_SIZE or DOT_SIZE, i == state and DOT_ACTIVE_SIZE or DOT_SIZE)
        else
            dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
            dot:SetVertexColor(0.4, 0.4, 0.4, 0.4)
            dot:SetSize(DOT_SIZE, DOT_SIZE)
        end
    end

    -- State label
    local c = STATE_COLORS[state] or STATE_COLORS[0]
    local stateText = STATE_LABELS[state] or "?"
    overlay.stateLabel:SetText(stateText)
    overlay.stateLabel:SetTextColor(c[1], c[2], c[3])

    -- Torment debuff
    local torment = data.torment
    if torment then
        local suffix = torment.isNightmare and " (NM)" or ""
        overlay.tormentLabel:SetText(string.format("Torment +%d%%%s", torment.totalPct, suffix))
        overlay.tormentLabel:SetTextColor(1.0, 0.3, 0.3)
        overlay.tormentLabel:Show()
    else
        overlay.tormentLabel:Hide()
    end

    overlay:Show()
end

-- ============================================================
-- Data Collection
-- ============================================================

function PHT.CollectData()
    local data = {}
    local widgetID = PHT.ScanForPreyWidget()

    data.widgetID = widgetID
    data.timestamp = date("%H:%M:%S")

    -- Widget info
    if widgetID then
        local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widgetID)
        if info then
            data.widgetInfo = info
            data.progressState = info.progressState
        end
    end

    -- Torment debuff
    data.torment = PHT.GetTormentInfo()

    -- Quest info
    if C_QuestLog.GetActivePreyQuest then
        data.questID = C_QuestLog.GetActivePreyQuest()
        if data.questID and data.questID > 0 then
            data.questTitle = C_QuestLog.GetTitleForQuestID(data.questID)
            data.questObjectives = C_QuestLog.GetQuestObjectives(data.questID)
        end
    end

    -- Navigation distance
    data.navDistance = C_Navigation.GetDistance()

    -- Hunts available widget
    data.hunts = PHT.GetHuntsAvailable()

    -- Currency & reputation
    data.currency = PHT.GetCurrencyData()

    PHT.lastData = data
    PHT.UpdateWidgetOverlay()
    return data
end

-- (Panel UI lives in PHT_Panel.lua)

-- ============================================================
-- Toggle / Slash Commands
-- ============================================================

function PHT.Toggle()
    local panel = PHT.CreatePanel()
    if panel:IsShown() then
        panel:Hide()
    else
        PHT.CollectData()
        panel:Show()
        PHT.RefreshDisplay()
    end
end

SLASH_PREYHUNTTRACKER1 = "/pht"
SlashCmdList["PREYHUNTTRACKER"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if msg == "scan" then
        PHT.trackedWidgetID = nil
        local id = PHT.ScanForPreyWidget()
        if id then
            print(ADDON_TAG .. " Rescan found widget ID: " .. id)
        else
            print(ADDON_TAG .. " Rescan found no prey hunt widgets.")
        end
        PHT.RefreshDisplay()
    elseif msg == "overlay" then
        PHT.overlayEnabled = not PHT.overlayEnabled
        print(ADDON_TAG .. " Overlay: " .. (PHT.overlayEnabled and "|cFF55FF55ON|r" or "|cFFFF5555OFF|r"))
        if PHT.overlayEnabled then
            PHT.CollectData()
        elseif PHT.widgetOverlay then
            PHT.widgetOverlay:Hide()
        end
    elseif msg == "state" or msg == "widget" then
        local widgetID = PHT.ScanForPreyWidget()
        if not widgetID then
            print(ADDON_TAG .. " No prey-progress widget visible right now.")
            return
        end
        local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widgetID)
        print(ADDON_TAG .. " widgetID=" .. tostring(widgetID))
        if not info then
            print("  (no info returned)")
            return
        end
        for k, v in pairs(info) do
            local val
            if type(v) == "table" then
                val = "{"
                for kk, vv in pairs(v) do
                    val = val .. tostring(kk) .. "=" .. tostring(vv) .. ","
                end
                val = val .. "}"
            else
                val = tostring(v)
            end
            print(string.format("  |cFFAABBCC%s|r = %s", tostring(k), val))
        end
    else
        PHT.Toggle()
    end
end

-- ============================================================
-- Addon Compartment
-- ============================================================

function PreyHuntTracker_OnAddonCompartmentClick()
    PHT.Toggle()
end

function PreyHuntTracker_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Prey Hunt Tracker", 0, 0.85, 0.85)
    GameTooltip:AddLine("Click to toggle panel", 1, 1, 1)
    GameTooltip:Show()
end

function PreyHuntTracker_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- ============================================================
-- Event Handling
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
eventFrame:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
eventFrame:RegisterEvent("CRITERIA_UPDATE")
eventFrame:RegisterEvent("CRITERIA_COMPLETE")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("QUEST_ACCEPTED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "PreyHuntTracker" then
            PHT_DB = PHT_DB or {}
            PHT_DB.preyCategoryID = PHT_DB.preyCategoryID or nil
        end
        return
    end

    if event == "ACHIEVEMENT_EARNED" then
        local achID = ...
        if PHT.Achievements then PHT.Achievements:RefreshOne(achID) end
        if PHT.Panel and PHT.Panel:IsShown() then PHT.Panel:RefreshTargets() end
        if GossipFrame and GossipFrame:IsShown() and PHT.GossipOverlay then
            PHT.GossipOverlay:Decorate()
        end
        return
    end

    if event == "CRITERIA_UPDATE" then
        if PHT.Achievements then PHT.Achievements:RefreshFlags() end
        if PHT.Panel and PHT.Panel:IsShown() then PHT.Panel:RefreshTargets() end
        if GossipFrame and GossipFrame:IsShown() and PHT.GossipOverlay then
            PHT.GossipOverlay:Decorate()
        end
        return
    end

    if event == "CRITERIA_COMPLETE" then
        local criteriaID = ...
        if PHT.Achievements then PHT.Achievements:RefreshCriterion(criteriaID) end
        if PHT.Panel and PHT.Panel:IsShown() then PHT.Panel:RefreshTargets() end
        if GossipFrame and GossipFrame:IsShown() and PHT.GossipOverlay then
            PHT.GossipOverlay:Decorate()
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        if PHT.GetUnitNpcID("target") == ASTALOR_NPC_ID then
            if PHT.Achievements then PHT.Achievements:EnsureBuilt() end
        end
        return
    end

    if event == "GOSSIP_SHOW" then
        if PHT.GossipOverlay then PHT.GossipOverlay:OnGossipShow() end
        return
    end

    if event == "GOSSIP_CLOSED" then
        if PHT.GossipOverlay then PHT.GossipOverlay:Cleanup() end
        return
    end

    if event == "QUEST_ACCEPTED" then
        local questID = ...
        if PHT.GossipOverlay then PHT.GossipOverlay:OnQuestAccepted(questID) end
        return
    end

    -- Existing widget / aura / currency handling
    if event == "UPDATE_UI_WIDGET" then
        local widgetInfo = ...
        if IsPreyHuntWidget(widgetInfo) then
            PHT.trackedWidgetID = widgetInfo.widgetID
        elseif not (PHT.trackedWidgetID and widgetInfo and widgetInfo.widgetID == PHT.trackedWidgetID) then
            return
        end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit ~= "player" then return end
    end
    PHT.CollectData()
    PHT.RefreshDisplay()
end)
