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

local CONTINUOUS_SEARCH_INTERVAL = 3
local UPDATE_INTERVAL = .1
--local DEBUG = true

local ignored_events = {}

addon.filter = {}

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

function addon:StartNewSearch()
    if self.searching then
        self:StopSearch()
    end

    self.searching = true
    self.interrupted = nil

    self:UI_SearchStarted()
    self:DoSearch()
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

    -- LFGList.lua, LFGListSearchPanel_DoSearch
    local languages = C_LFGList.GetLanguageSearchFilter()
    C_LFGList.Search(self.categoryID, self.searchText, self.filters, self.preferredFilters, languages)

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

    -- reset filter
    addon.filter = {}

    self:StopWaitingForResults()
    self:UI_SearchStopped()
    self:SetScript('OnUpdate',nil)

    d_print('search stopped')
end

-- continuous search delay handler --
do
    local GetTime = GetTime
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

    if not PremadeNotifierSaved or type(PremadeNotifierSaved) ~= 'table' then
        PremadeNotifierSaved = {}
    end

    SearchPanel = LFGListFrame.SearchPanel
    addon.SearchPanel = SearchPanel

    -- perform UI modifications
    self:UI_Init()
end

function addon:LFG_LIST_SEARCH_FAILED()
    -- silently fail and try again
    d_print('SEARCH_FAILED')
    self:StopWaitingForResults()
    self:DelayedRefresh()
end


local function Result_MatchesFilter(members)
    if addon.filter.max_members and members > addon.filter.max_members then
        return
    end

    if addon.filter.min_members and members < addon.filter.min_members then
        return
    end

    return true
end

local function Result_IsViable(id, ilvl)
    if
        not addon:IsIgnored(id) and
        GetAverageItemLevel() >= ilvl
    then
        return true
    end
end


function addon:LFG_LIST_SEARCH_RESULTS_RECEIVED()
    d_print('RESULTS_RECEIVED')
    self:StopWaitingForResults()

    -- parse results
    local no_results,results = C_LFGList.GetSearchResults()
    local select_result
    if no_results > 0 then
        -- deep-filter results
        local GSRI = C_LFGList.GetSearchResultInfo
        for _,id in ipairs(results) do
            local _,_,name,_,_,ilvl,_,_,_,_,_,author,members = GSRI(id)

            if name and author then
                if
                    Result_IsViable(id, ilvl) and
                    Result_MatchesFilter(members)
                then
                    select_result = id
                    d_print('Result '..id..': '..name..' by '..author..' ['..members..']')
                    break
                else
                    no_results = no_results - 1
                end
            end
        end

        if select_result and no_results >= 1 then
            addon:StopSearch()
            addon:UI_OpenLFGListToResult(select_result)
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
