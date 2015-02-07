local folder,ns = ...
local addon = CreateFrame('frame','PremadeNotifierFrame')
local elap = 0

local waiting_for_results
local continuous_searching = true
local search_again_at

local CONTINUOUS_SEARCH_INTERVAL = 10
local UPDATE_INTERVAL = .1

-- functions --
local function GetGroupTable(i)
    return _G['LFGListSearchPanelScrollFrameButton'..i]
end

function addon:RefreshSearch()
    LFGListFrame.SearchPanel.RefreshButton:Click(); 

    self:RegisterEvent('LFG_LIST_SEARCH_FAILED')
    self:RegisterEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')

    waiting_for_results = true
    search_again_at = nil
end

function addon:SetContinuous()
    continuous_searching = true
end

-- continuous search delay handler --
local function OnUpdate(self,elapsed)
    elap = elap + elapsed
    if elap >= UPDATE_INTERVAL then
        if not search_again_at then
            self:SetScript('OnUpdate',nil)
        elseif GetTime() > search_again_at then
            self:RefreshSearch()
        end

        elap = 0
    end
end

function addon:DelayedRefresh()
    -- insert a delayed refresh
    if waiting_for_results or search_again_at ~= nil then return end
    search_again_at = GetTime() + CONTINUOUS_SEARCH_INTERVAL
    self:SetScript('OnUpdate',OnUpdate)
end

-- event handlers --
function addon:ADDON_LOADED(loaded_name)
    if loaded_name ~= folder then return end

    --self:RegisterEvent('LFG_LIST_AVAILABILITY_UPDATE')
    --self:RegisterEvent('LFG_LIST_SEARCH_RESULTS_UPDATED')
end

function addon:LFG_LIST_SEARCH_FAILED()
    -- silently fail and try again
    self:DelayedRefresh()
end
function addon:LFG_LIST_SEARCH_RESULTS_RECEIVED()
    -- stop waiting for results
    waiting_for_results = nil
    addon:UnregisterEvent('LFG_LIST_SEARCH_FAILED')
    addon:UnregisterEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')

    -- alert for any results
    if GetGroupTable(1) and GetGroupTable(1):IsShown() then
        message("A result! Dope!")
        continuous_searching = nil
    end

    if continuous_searching then
        -- and search again after a short delay
        self:DelayedRefresh()
    end
end

addon:SetScript('OnEvent', function(self,event,...)
    self[event](self,...)
end)

addon:RegisterEvent('ADDON_LOADED')
