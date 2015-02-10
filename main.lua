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
--local DEBUG = true

local ignored_events = {}

-- functions --
local function d_print(m)
    if DEBUG then print('Premade|cff9966ffNotifier|r: '..m) end
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

-- ignore functions
function addon:IsIgnored(resultID)
    local _,_,name,_,_,_,_,_,_,_,_,author = C_LFGList.GetSearchResultInfo(resultID)
    if not name or not author then return end

    if ignored_events[author] and ignored_events[author] == name then
        return true
    end
end
function addon:ToggleIgnore(resultID,menu)
    local _,_,name,_,_,_,_,_,_,_,_,author = C_LFGList.GetSearchResultInfo(resultID)
    if not name or not author then return end

    -- you can only list one event at a time, so we use player names as the key
    if addon:IsIgnored(resultID) then
        ignored_events[author] = nil
    else
        ignored_events[author] = name
    end

    -- force the menu to update if we right click on this entry again
    menu.pn_modified = true
end

function addon:StartNewSearch(req_members, active_panel)
    -- grab category & filter at time of search
    addon.categoryID = SearchPanel.categoryID
    addon.searchText = SearchPanel.SearchBox:GetText()
    addon.filters = SearchPanel.filters
    addon.preferredFilters = SearchPanel.preferredFilters
    addon.active_panel = active_panel
    addon.req_members = req_members

    addon.searching = true
    addon.interrupted = nil

    self:UI_SearchStarted()
    self:DelayedRefresh()
end

function addon:DoSearch()
    -- actually request the search from C
    search_again_at = nil
    addon.interrupted = nil

    if  SearchPanel:IsVisible() and (
            SearchPanel.categoryID ~= self.categoryID or
            SearchPanel.SearchBox:GetText() ~= self.searchText or
            SearchPanel.filters ~= self.filters or
            SearchPanel.preferredFilters ~= self.preferredFilters
        )
    then
        -- don't force a search now if the UI is in use (presumably)
        d_print('mismatch in data set, assuming ui in use')

        addon.interrupted = true
        self:UI_SearchInterrupted()

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

    -- begin/resume animation
    self:UI_SearchStarted()

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
    addon.searching = nil
    addon.interrupted = nil

    self:StopWaitingForResults()
    self:UI_SearchStopped()
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

    -- perform UI modifications
    self:UI_Init()
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

            if name and author then
                if  -- always ignore certain results-
                    (addon.req_members and members < addon.req_members) or
                    self:IsIgnored(id) or
                    player_ilvl < ilvl or
                    members == 40
                then
                    no_results = no_results - 1
                else
                    select_result = id
                    d_print('Result '..id..': '..name..' by '..author..' ['..members..']')
                    break
                end
            end
        end

        if select_result and no_results >= 1 then
            addon:StopSearch()

            -- open frame to panel which was active at time of search
            if self.active_panel == 'LFGListPVEStub' then
                PVEFrame_TabOnClick(PVEFrameTab1) -- pve
                GroupFinderFrameGroupButton4:Click()
            else
                PVEFrame_TabOnClick(PVEFrameTab2) -- pvp
                PVPQueueFrameCategoryButton4:Click()
            end

            -- jump to the search panel (which was updated by the search itself)
            LFGListFrame_SetActivePanel(LFGListFrame,SearchPanel)

            -- select the matched result
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
