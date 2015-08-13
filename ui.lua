--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local addon = PremadeNotifierFrame
local button, menu_frame

local tooltip_default_title = 'Continuous search'
local tooltip_default_text = 'Continuously search for this filter in the background and open the search results when an event is found.\n\nHold SHIFT while clicking to search and save this search across sessions.\nRIGHT CLICK to change advanced settings.'

local tooltip_search_title = 'Searching...'
local tooltip_search_cancel = 'Click again to cancel.'
local tooltip_search_save = 'Shift click to save this search.'

local SearchPanel

-- toggled by the auto_signup checkbox
local AutoSignUp_Enabled

local function ui_print(m)
    print('Premade|cff9966ffNotifier|r: '..m)
end

-- element creation helpers ----------------------------------------------------
local function CreateCheckBox(parent, name, desc, callback)
    local check = CreateFrame('CheckButton', 'PremadeNotifierMenuFrame_'..name..'Check', parent, 'OptionsBaseCheckButtonTemplate')

    check:SetScript('OnClick', function(self)
        if self:GetChecked() then
            PlaySound("igMainMenuOptionCheckBoxOn")
        else
            PlaySound("igMainMenuOptionCheckBoxOff")
        end

        if callback then
            callback(self)
        end
    end)

    check.desc = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
    check.desc:SetText(desc)
    check.desc:SetPoint('LEFT', check, 'RIGHT')

    return check
end
-- script handlers -------------------------------------------------------------
local function ButtonOnMouseDown(button)
    button.icon:SetPoint('CENTER', button, 'CENTER', -2, -1)
end
local function ButtonOnMouseUp(button)
    button.icon:SetPoint('CENTER', button, 'CENTER', -1, 0)
end

local function ButtonTooltip(button)
    GameTooltip:SetOwner(button, 'ANCHOR_RIGHT')
    GameTooltip:SetWidth(200)

    if not addon.searching then
        GameTooltip:AddLine(tooltip_default_title)
        GameTooltip:AddLine(tooltip_default_text,1,1,1,true)
    else
        -- add search information to the tooltip
        if addon.interrupted then
            GameTooltip:AddLine('Paused')
        else
            GameTooltip:AddLine(tooltip_search_title)
        end

        if addon.searchText and addon.searchText ~= '' then
            GameTooltip:AddDoubleLine('Search text:', addon.searchText, 1,.82,0, 1,1,1)
        end

        if addon.categoryID then
            local category_name = C_LFGList.GetCategoryInfo(addon.categoryID)
            GameTooltip:AddDoubleLine('Category:', category_name, 1,.82,0, 1,1,1)
        end

        if addon.filter.min_members then
            GameTooltip:AddDoubleLine('Min. members:', addon.filter.min_members, 1,.82,0, 1,1,1)
        end
        if addon.filter.max_members then
            GameTooltip:AddDoubleLine('Max. members:', addon.filter.max_members, 1,.82,0, 1,1,1)
        end

        if AutoSignUp_Enabled then
            GameTooltip:AddLine('Will automatically sign up.')
        end
        if PremadeNotifierSaved.filter then
            GameTooltip:AddLine('Search is saved.')
        end

        GameTooltip:AddLine(' ')

        if not PremadeNotifierSaved.filter and not addon.interrupted then
            GameTooltip:AddLine(tooltip_search_save,1,1,1)
        end

        GameTooltip:AddLine(tooltip_search_cancel,1,1,1)

        if addon.interrupted then
            GameTooltip:AddLine(' ')
            GameTooltip:AddLine('Search is paused while you use the UI.',1,.3,.3)
        end
    end

    GameTooltip:Show()
end
local function ButtonTooltipHide(button)
    GameTooltip:Hide()
end

local function UpdateSavedSearch(reset)
    if not reset and not PremadeNotifierSaved.filter then return end
    if not addon.active_panel then return end

    PremadeNotifierSaved.AutoSignUp_Enabled = AutoSignUp_Enabled
    PremadeNotifierSaved.filter = addon.filter
    PremadeNotifierSaved.active_panel = addon.active_panel
    PremadeNotifierSaved.default_filter = {
        categoryID       = addon.categoryID,
        searchText       = addon.searchText,
        filters          = addon.filters,
        preferredFilters = addon.preferredFilters
    }
end
local function GetDefaultFilterVariables()
    -- get filter variables from default UI
    addon.categoryID = addon.SearchPanel.categoryID
    addon.searchText = addon.SearchPanel.SearchBox:GetText()
    addon.filters = addon.SearchPanel.filters
    addon.preferredFilters = addon.SearchPanel.preferredFilters

    UpdateSavedSearch()
end
local function SetFilter(key, value)
    addon.filter[key] = value
    UpdateSavedSearch()
end

local function ButtonOnClick(button, mouse_button)
    PlaySound("igMainMenuOptionCheckBoxOn")

    if mouse_button == 'LeftButton' then
        if addon.searching then
            if IsShiftKeyDown() and not addon.interrupted then
                -- save the active search
                UpdateSavedSearch(true)
                HideUIPanel(PVEFrame)
                return
            else
                -- stop the current search
                addon:StopSearch()
                ButtonTooltip(button)
                wipe(PremadeNotifierSaved)
                return
            end
        end

        --                          refreshbtn  searchpanel lfglistfrm  pve/pvpstub
        local active_panel = button:GetParent():GetParent():GetParent():GetParent():GetName()
        addon.active_panel = active_panel

        -- grab category & filter at time of search
        GetDefaultFilterVariables()
        addon:StartNewSearch()

        if IsShiftKeyDown() then
            -- save this search
            UpdateSavedSearch(true)
        else
            -- clear saved search if manually refreshed/changed
            wipe(PremadeNotifierSaved)
        end

        -- Don't worry about the active panel here, as the PVEFrame contains
        -- all of them anyway
        HideUIPanel(PVEFrame)
    else
        -- immediately update the tooltip
        ButtonTooltip(button)

        -- toggle advanced menu
        if menu_frame:IsShown() then
            menu_frame:Hide()
        else
            menu_frame:Show()
        end
    end
end

-- edit box scripts
local function OnEnterPressed(self)
    self:ClearFocus()
end
local function OnEscapePressed(self)
    self:ClearFocus()
end
local function OnEditFocusLost(self)
    if self.filter_key then
        SetFilter(self.filter_key, tonumber(self:GetText()))
    end
end
-- activity menu hook ---------------------------------------------------------
-- modify the search entry menu dropdown
-- I had limited success modifying the menu BEFORE it was shown, so resorted
-- to this. I should take another look at some point.
local function EasyMenu_Hook(menu,frame,anchor,x,y,display)
    -- dumb-verify we're modifying the right menu
    if frame ~= LFGListFrameDropDown then return end
    if  not menu[3] or not menu[3].menuList[1] or
        not menu[3].menuList[1].arg1 or not menu[2]
    then
        return
    end

    if menu[2].text == 'Whisper' then
        -- this is a player; remove our ignore option
        if menu.pn_modified == 'player' then return end
        if menu[4] and menu[4].text == 'Ignore' then
            tremove(menu,4)
        end

        menu.pn_modified = 'player'
    else
        -- this is an activity;
        -- fetch result id from one of the report options
        local resultID = tonumber(menu[3].menuList[1].arg1)
        if not resultID then return end

        -- stop recursing if the menu was already modified for this entry
        if menu.pn_modified == resultID then return end

        if not menu.pn_modified or not menu[4] or menu[4].text ~= 'Ignore' then
            -- insert our ignore option
            tinsert(menu, 4, {
                text='Ignore',
                tooltipOnButton=true,
                tooltipTitle='Ignore',
                tooltipText="Don't notify about this event when continuously searching (unless the title or leader changes)."
            })
        end

        if menu[4] and menu[4].text == 'Ignore' then
            menu[4].checked = addon:IsIgnored(resultID)
            menu[4].func = addon.ToggleIgnore
            menu[4].arg1 = resultID
            menu[4].arg2 = menu
        end

        menu.pn_modified = resultID
    end

    -- re-display the menu with our modifications
    EasyMenu(menu, frame, anchor, x, y, display)
end
-- default interface panel helpers ---------------------------------------------
local function AutoSignUp(id)
    local d = LFGListApplicationDialog
    local result_data = { C_LFGList.GetSearchResultInfo(id) }

    LFGListSearchPanel_SignUp(LFGListFrame)
    LFGListSearchPanel_UpdateButtonStatus(LFGListFrame.SearchPanel)

    if d.SignUpButton:IsEnabled() then
        -- auto sign up and hide the sign up frame if roles are already checked
        C_LFGList.ApplyToGroup(
            id, "",
            d.TankButton:IsShown() and d.TankButton.CheckButton:GetChecked(),
            d.HealerButton:IsShown() and d.HealerButton.CheckButton:GetChecked(),
            d.DamagerButton:IsShown() and d.DamagerButton.CheckButton:GetChecked()
        )

        StaticPopupSpecial_Hide(d)

        ui_print('Applied to '..result_data[3].. ' by '..result_data[12]..' ('..result_data[13]..' members)')
    end
end
function addon:UI_OpenLFGListToResult(id)
    -- TODO
    -- default provides LFGListFrame_SelectResult(LFGListFrame.SearchPanel, result_id)
    -- but doesn't scroll down to it

    -- open frame to panel which was active at time of search
    -- (doesn't actually affect displayed results)
    if addon.active_panel == 'LFGListPVEStub' then
        PVEFrame_TabOnClick(PVEFrameTab1)
        GroupFinderFrameGroupButton4:Click()
    else
        PVEFrame_TabOnClick(PVEFrameTab2)
        PVPQueueFrameCategoryButton4:Click()
    end

    -- jump to the search panel (updated by the search itself)
    LFGListFrame_SetActivePanel(LFGListFrame, LFGListFrame.SearchPanel)
    LFGListSearchPanel_SelectResult(LFGListFrame.SearchPanel, id)

    -- result found notification/s
    PlaySoundKitID(8960) -- readycheck
    FlashClientIcon()

    if AutoSignUp_Enabled then
        AutoSignUp(id)
    end

    -- clear saved search
    wipe(PremadeNotifierSaved)
end
-- initialize ------------------------------------------------------------------
function addon:UI_Init()
    -- create loop search button
    button = CreateFrame('Button','PremadeNotifierButton',LFGListFrame.SearchPanel.RefreshButton)
    button:SetPoint('RIGHT', LFGListFrame.SearchPanel.RefreshButton, 'LEFT', 0, 0)

    -- this is a copy of RefreshButton from FrameXML/LFGList.xml
    button:SetSize(32,32)
    button:SetNormalTexture('Interface\\Buttons\\UI-SquareButton-Up')
    button:SetPushedTexture('Interface\\Buttons\\UI-SquareButton-Down')
    button:SetDisabledTexture('Interface\\Buttons\\UI-SquareButton-Disabled')
    button:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight')

    button.icon = button:CreateTexture(nil, 'ARTWORK', nil, 5)
    button.icon:SetTexture('Interface\\Buttons\\UI-RefreshButton')
    button.icon:SetPoint('CENTER', -1, 0)
    button.icon:SetSize(16,16)
    button.icon:SetVertexColor(.3,1,.2)

    do -- create icon animator
        local icon_ani = button.icon:CreateAnimationGroup()
        icon_ani:SetLooping('REPEAT')

        local icon_rot = icon_ani:CreateAnimation('Rotation')
        icon_rot:SetDuration(4)
        icon_rot:SetDegrees(-360)

        function addon:UI_SearchStarted()
            icon_ani:Play()
        end
        function addon:UI_SearchStopped()
            icon_ani:Stop()
        end
        function addon:UI_SearchInterrupted()
            icon_ani:Pause()

            if button:IsVisible() and
               GameTooltip:IsVisible() and
               GetMouseFocus() == button
            then
                -- update tooltip
                ButtonTooltip(button)
            end
        end
    end

    hooksecurefunc('EasyMenu', EasyMenu_Hook)

    button:RegisterForClicks('LeftButtonUp','RightButtonUp')
    button:SetScript('OnClick', ButtonOnClick)
    button:SetScript('OnEnter', ButtonTooltip)
    button:SetScript('OnLeave', ButtonTooltipHide)
    button:SetScript('OnMouseDown', ButtonOnMouseDown)
    button:SetScript('OnMouseUp', ButtonOnMouseUp)

    do -- create advanced menu
        menu_frame = CreateFrame('Frame', 'PremadeNotifierMenuFrame', LFGListFrame.SearchPanel)
        menu_frame:SetPoint('TOPLEFT', LFGListFrame.SearchPanel, 'TOPRIGHT', 6, 1)
        menu_frame:SetSize(150,110)
        menu_frame:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            tile = true,
            tileSize = 32,
            edgeSize = 16,
            insets = {
                top = 2,
                right = 2,
                bottom = 3,
                left = 2
            }
        })

        menu_frame:Hide()
        menu_frame:EnableMouse(true)

        menu_frame.filter_elements = {}

        local function InitFilterElement(element, key, default)
            element.filter_key = key
            element.filter_default = default
            tinsert(menu_frame.filter_elements, element)
        end

        LFGListFrame.SearchPanel:HookScript('OnHide', function()
            menu_frame:Hide()
        end)

        local at_least = CreateFrame('EditBox', 'PremadeNotifierMenuFrame_AtLeast', menu_frame, 'InputBoxTemplate')
        at_least:SetSize(30,10)
        at_least:SetAutoFocus(false)
        at_least:SetFontObject(ChatFontNormal)

        local at_most = CreateFrame('EditBox', 'PremadeNotifierMenuFrame_AtMost', menu_frame, 'InputBoxTemplate')
        at_most:SetSize(30,10)
        at_most:SetAutoFocus(false)
        at_most:SetFontObject(ChatFontNormal)

        local num_members_between = menu_frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
        local num_members_and = menu_frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
        local num_members_members = menu_frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')

        num_members_between:SetText('Between')
        num_members_and:SetText('and')
        num_members_members:SetText('members')

        num_members_between:SetPoint('TOP', 0, -15)
        num_members_and:SetPoint('TOP', num_members_between, 'BOTTOM', 0, -5)
        num_members_members:SetPoint('TOP', num_members_and, 'BOTTOM', 0, -5)

        at_least:SetPoint('RIGHT', num_members_and, 'LEFT', -3, 0)
        at_most:SetPoint('LEFT', num_members_and, 'RIGHT', 8, 0)

        at_least:SetScript('OnEscapePressed', OnEscapePressed)
        at_least:SetScript('OnEnterPressed', OnEscapePressed)
        at_least:SetScript('OnEditFocusLost', OnEditFocusLost)

        at_most:SetScript('OnEscapePressed', OnEscapePressed)
        at_most:SetScript('OnEnterPressed', OnEscapePressed)
        at_most:SetScript('OnEditFocusLost', OnEditFocusLost)

        InitFilterElement(at_least, 'min_members', 0)
        InitFilterElement(at_most, 'max_members', 40)

        -- auto-signup checkbox ################################################
        local auto_signup_callback = function(self)
            AutoSignUp_Enabled = self:GetChecked()
            UpdateSavedSearch()
        end

        local auto_signup = CreateCheckBox(menu_frame, 'AutoSignUp', 'Automatically sign up', auto_signup_callback)
        auto_signup:SetPoint('BOTTOMLEFT', 10, 10)

        -- advanced frame scripts
        menu_frame:SetScript('OnShow', function(self)
            for i,element in pairs(self.filter_elements) do
                -- restore current filter values
                element:SetText(addon.filter[element.filter_key] or element.filter_default)
            end

            auto_signup:SetChecked(AutoSignUp_Enabled)
        end)
    end

    -- restore saved search
    if PremadeNotifierSaved.filter then
        addon.filter = PremadeNotifierSaved.filter
        addon.active_panel = PremadeNotifierSaved.active_panel
        for k,v in pairs(PremadeNotifierSaved.default_filter) do
            addon[k] = v
        end

        AutoSignUp_Enabled = PremadeNotifierSaved.AutoSignUp_Enabled

        ui_print('Saved search restored.')

        -- begin saved search
        addon:StartNewSearch()
    end
end
