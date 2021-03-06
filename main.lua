--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local folder,ns = ...
local addon = CreateFrame('frame','PremadeNotifierFrame')
local elap = 0
local _
local OnUpdate
local GetTime = GetTime

local SearchPanel
local waiting_for_results
local search_again_at
local prase_results

local CONTINUOUS_SEARCH_INTERVAL = 3
local UPDATE_INTERVAL = .1
local PARSE_RESULTS_DELAY = .5
local MAX_WAIT_TIME = 10
local DEBUG
--@debug@
--DEBUG = true
--@end-debug@

addon.ignored_events = {}
addon.filter = {}

-- local functions #############################################################
local function d_print(m)
    if DEBUG then print(GetTime()..' Premade|cff9966ffNotifier|r: '..m) end
end

local ParseResults
do
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
    function ParseResults()
        parse_results = nil

        d_print('parsing search results')

        local no_results,results = C_LFGList.GetSearchResults()
        if no_results > 0 then
            local viable_results = {}

            -- deep-filter results
            local GSRI = C_LFGList.GetSearchResultInfo
            for _,id in ipairs(results) do
                local _,_,name,_,_,ilvl,_,_,_,_,_,_,author,members = GSRI(id)

                if name and author then
                    d_print(name..' by '..author..' ('..members..' members)')

                    if  Result_IsViable(id, ilvl) and
                        Result_MatchesFilter(members)
                    then
                        tinsert(viable_results,id)
                        d_print('Result '..id..': '..name..' by '..author..' ['..members..']')
                    else
                        no_results = no_results - 1
                    end
                end
            end

            if #viable_results > 0 then
                addon:UI_OpenLFGListToResults(viable_results)

                if not PremadeNotifierSaved.forever then
                    addon:StopSearch()
                    return
                end
            end
        end
    end
end

-- Prevent manually browsing the UI from interfering with an active search
local DisableDefaultButtons,EnableDefaultButtons
do
    DisableDefaultButtons = function()
        LFGListFrame.CategorySelection.FindGroupButton:Disable()
        SearchPanel.RefreshButton:Disable()
    end
    EnableDefaultButtons = function()
        LFGListFrame.CategorySelection.FindGroupButton:Enable()
        SearchPanel.RefreshButton:Enable()
    end
    local DefaultPanelOnShow = function()
        if waiting_for_results then
            DisableDefaultButtons()
        end
    end
    local DefaultPanelOnHide = function()
        if addon.interrupted then
            -- immediately retry search upon closing the panel
            addon:DoSearch()
        end
    end

    hooksecurefunc('LFGListCategorySelection_UpdateNavButtons', DefaultPanelOnShow)
    LFGListFrame.CategorySelection:HookScript('OnShow', DefaultPanelOnShow)
    LFGListFrame.SearchPanel:HookScript('OnShow', DefaultPanelOnShow)
    LFGListFrame.SearchPanel:HookScript('OnHide', DefaultPanelOnHide)
end

-- ignore functions ############################################################
function addon:IsIgnored(resultID)
    local _,_,name,_,_,_,_,_,_,_,_,_,author = C_LFGList.GetSearchResultInfo(resultID)
    if not name or not author then return end

    if addon.ignored_events[author] and addon.ignored_events[author] == name then
        return true
    end
end
function addon:IgnoreResult(id)
    local _,_,name,_,_,_,_,_,_,_,_,_,author = C_LFGList.GetSearchResultInfo(id)
    if not name or not author then return end
    addon.ignored_events[author] = name

    if PremadeNotifierSaved.ignored_events then
        PremadeNotifierSaved.ignored_events = addon.ignored_events
    end
end
function addon:UnignoreResult(id)
    local _,_,_,_,_,_,_,_,_,_,_,_,author = C_LFGList.GetSearchResultInfo(id)
    if not author then return end
    addon.ignored_events[author] = nil

    if PremadeNotifierSaved.ignored_events then
        PremadeNotifierSaved.ignored_events = addon.ignored_events
    end
end
function addon:ToggleIgnore(resultID,menu)
    local _,_,name,_,_,_,_,_,_,_,_,_,author = C_LFGList.GetSearchResultInfo(resultID)
    if not name or not author then return end

    -- you can only list one event at a time, so we use player names as the key
    if addon:IsIgnored(resultID) then
        addon.ignored_events[author] = nil
    else
        addon.ignored_events[author] = name
    end

    if menu then
        -- force the menu to update if we right click on this entry again
        menu.pn_modified = true
    end

    if PremadeNotifierSaved.ignored_events then
        -- update saved search ignores
        PremadeNotifierSaved.ignored_events = addon.ignored_events
    end
end

-- search functions ############################################################
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

    if (PremadeNotifierSaved.forever and IsInGroup())
       or
       (SearchPanel:IsVisible() and (
            SearchPanel.categoryID ~= self.categoryID or
            SearchPanel.SearchBox:GetText() ~= self.searchText or
            SearchPanel.filters ~= self.filters or
            SearchPanel.preferredFilters ~= self.preferredFilters
       ))
    then
        -- don't force a search now if the UI is in use (presumably)
        -- or if we're already in a group
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

    waiting_for_results = GetTime() + MAX_WAIT_TIME
    self:SetScript('OnUpdate',OnUpdate)

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

-- continuous search delay handler #############################################
function OnUpdate(self,elapsed)
    elap = elap + elapsed
    if elap >= UPDATE_INTERVAL then
        elap = 0

        if not parse_results and
           not waiting_for_results and
           not search_again_at
        then
            self:SetScript('OnUpdate',nil)
            return
        end

        if parse_results and GetTime() >= parse_results then
            ParseResults()
        end

       if (waiting_for_results and GetTime() >= waiting_for_results) or
          (search_again_at and GetTime() >= search_again_at)
        then
            self:DoSearch()
        end
    end
end
function addon:DelayedRefresh()
    -- insert a delayed refresh
    if waiting_for_results or search_again_at ~= nil then return end
    search_again_at = GetTime() + CONTINUOUS_SEARCH_INTERVAL
    self:SetScript('OnUpdate',OnUpdate)

    d_print('delayed refresh scheduled for '..search_again_at)
end

-- event handlers ##############################################################
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


function addon:LFG_LIST_SEARCH_RESULTS_RECEIVED()
    d_print('RESULTS_RECEIVED')
    self:StopWaitingForResults()

    -- results aren't immediately available, so parse them after a delay
    parse_results = GetTime() + PARSE_RESULTS_DELAY
    self:SetScript('OnUpdate',OnUpdate)

    -- search again after a short delay
    self:DelayedRefresh()
end

addon:SetScript('OnEvent', function(self,event,...)
    self[event](self,...)
end)

addon:RegisterEvent('ADDON_LOADED')
