--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local folder,ns = ...
local addon = CreateFrame('frame','PremadeNotifierFrame')
local elap = 0
local _

local SearchPanel
local waiting_for_results
local search_again_at

local CONTINUOUS_SEARCH_INTERVAL = 10
local UPDATE_INTERVAL = .1
local DEBUG = true

-- functions --
local function d_print(m)
    if DEBUG then print('Premade|cff9966ffNotifier|r: '..m) end
end

local function GetGroupTable(i)
    return _G['LFGListSearchPanelScrollFrameButton'..i]
end

-- Prevent manually browsing the UI from interfering with an active search
local DisableDefaultButtons,EnableDefaultButtons
do
    local do_disable

    DisableDefaultButtons = function()
        do_disable = true
        LFGListFrame.CategorySelection.FindGroupButton:Disable()
        SearchPanel.RefreshButton:Disable()
    end

    EnableDefaultButtons = function()
        do_disable = nil
        LFGListFrame.CategorySelection.FindGroupButton:Enable()
        SearchPanel.RefreshButton:Enable()
    end

    local DefaultPanelOnShow = function()
        if do_disable then
            DisableDefaultButtons()
        end
    end

    hooksecurefunc('LFGListCategorySelection_UpdateNavButtons', DefaultPanelOnShow)
    LFGListFrame.CategorySelection:HookScript('OnShow', DefaultPanelOnShow)
    LFGListFrame.SearchPanel:HookScript('OnShow', DefaultPanelOnShow)
end

function addon:StartNewSearch()
    -- grab category & filter at time of search
    addon.categoryID = SearchPanel.categoryID
    addon.searchText = SearchPanel.SearchBox:GetText()
    addon.filters = SearchPanel.filters
    addon.preferredFilters = SearchPanel.preferredFilters

    self:DelayedRefresh()
end

function addon:DoSearch()
    -- actually request the search from C 
    search_again_at = nil

    if  SearchPanel:IsVisible() and (
            SearchPanel.categoryID ~= self.categoryID or
            SearchPanel.SearchBox:GetText() ~= self.searchText or
            SearchPanel.filters ~= self.filters or
            SearchPanel.preferredFilters ~= self.preferredFilters
        )
    then
        -- don't force a search now if the UI is in use (presumably)
        d_print('mismatch in data set, assuming ui in use')

        self:DelayedRefresh()
        return
    end

    -- disable buttons which can interfere at this point
    DisableDefaultButtons()

    C_LFGList.Search(self.categoryID, self.searchText, self.filters, self.preferredFilters)

    -- as forcing a search like this interferes with the UI anyway, also
    -- move back to the searched category
    LFGListSearchPanel_SetCategory(SearchPanel, self.categoryID, self.filters, self.preferredFilters)
    SearchPanel.SearchBox:SetText(self.searchText)

    self:RegisterEvent('LFG_LIST_SEARCH_FAILED')
    self:RegisterEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')

    waiting_for_results = true

    d_print('searching')
end

function addon:StopWaitingForResults()
    -- stop waiting for results and clean up events
    waiting_for_results = nil
    addon:UnregisterEvent('LFG_LIST_SEARCH_FAILED')
    addon:UnregisterEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')

    EnableDefaultButtons()

    d_print('no longer waiting for results')
end

function addon:StopSearch()
    -- stop search and clean up events, scripts
    search_again_at = nil
    self:StopWaitingForResults()
    self:SetScript('OnUpdate',nil)

    d_print('search stopped')
end

-- continuous search delay handler --
do 
    local function OnUpdate(self,elapsed)
        elap = elap + elapsed
        if elap >= UPDATE_INTERVAL then
            if not search_again_at then
                self:SetScript('OnUpdate',nil)
            elseif GetTime() > search_again_at then
                self:DoSearch()
            end

            elap = 0
        end
    end

    function addon:DelayedRefresh()
        -- insert a delayed refresh
        if waiting_for_results or search_again_at ~= nil then return end
        search_again_at = GetTime() + CONTINUOUS_SEARCH_INTERVAL
        self:SetScript('OnUpdate',OnUpdate)

        d_print('delayed refresh scheduled for '..search_again_at)
    end
end

-- event handlers --
function addon:ADDON_LOADED(loaded_name)
    if loaded_name ~= folder then return end
    SearchPanel = LFGListFrame.SearchPanel

    --self:RegisterEvent('LFG_LIST_AVAILABILITY_UPDATE')
    --self:RegisterEvent('LFG_LIST_SEARCH_RESULTS_UPDATED')
end

function addon:LFG_LIST_SEARCH_FAILED()
    -- silently fail and try again
    self:StopWaitingForResults()
    self:DelayedRefresh()
end
function addon:LFG_LIST_SEARCH_RESULTS_RECEIVED()
    self:StopWaitingForResults()
    local player_ilvl = GetAverageItemLevel()

    -- parse results
    local no_results,results = C_LFGList.GetSearchResults()
    local select_result
    if no_results > 0 then
        -- deep filter results
        for _,id in ipairs(results) do
            local _,_,name,_,_,ilvl,_,_,_,_,_,author,members = C_LFGList.GetSearchResultInfo(id)

            if player_ilvl < ilvl or members == 40 then
                no_results = no_results - 1
            else
                select_result = id
                d_print('Result '..id..': '..name..' by '..author..' ['..members..']')
                break
            end
        end

        if select_result and no_results >= 1 then
            addon:StopSearch()

            -- open the frame and select the first matched result
            PVEFrame_ShowFrame('GroupFinderFrame')
            GroupFinderFrameGroupButton4:Click()
            LFGListFrame_SetActivePanel(LFGListFrame,SearchPanel)
            LFGListSearchPanel_SelectResult(SearchPanel, select_result)

            return
        end
    end

    -- search again after a short delay
    self:DelayedRefresh()
end

addon:SetScript('OnEvent', function(self,event,...)
    self[event](self,...)
end)

addon:RegisterEvent('ADDON_LOADED')
