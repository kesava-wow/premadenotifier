--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local addon = PremadeNotifierFrame
local button, menu_frame

local tooltip_default_title = 'Continuous search'
local tooltip_default_text = 'Continuously search for this filter in the background and open the search results when an event is found.\n\nRight click to search without closing the UI.\nCtrl-click to search with a minimum member requirement of 2.\nShift-click to search with a minimum member requirement of 10.'

local tooltip_search_title = 'Searching...'
local tooltip_search_text = '\nClick again to cancel.'

--[[
Button context menu:
Options in the context menu do not close the UI and trigger an immediate search
rather than waiting 10 seconds.

Options:
"Search" immediately search
"At least x members..."
    "2", "4", "9", "14", "19", "24"
"At most x members..."
    "1", "2", "3", "5", "10", "15", "20", "25", "30", "40"
]]

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
            GameTooltip:AddLine('Search is paused while you use the UI.\n',1,1,1)
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

        if addon.req_members and addon.req_members > 1 then
            GameTooltip:AddDoubleLine('Members:', addon.req_members, 1,.82,0, 1,1,1)
        end

        GameTooltip:AddLine(tooltip_search_text,1,1,1)
    end

    GameTooltip:Show()
end
local function ButtonTooltipHide(button)
    GameTooltip:Hide()
end

local function ButtonOnClick(button, mouse_button)
    if mouse_button == 'LeftButton' then
        -- start a search on left click...
        if addon.searching then
            -- stop the current search
            addon:StopSearch()
            ButtonTooltip(button)
            return
        end

        --                          refreshbtn  searchpanel lfglistfrm  pve/pvpstub
        local active_panel = button:GetParent():GetParent():GetParent():GetParent():GetName()
        local req_members = IsShiftKeyDown() and 10 or IsControlKeyDown() and 2 or nil
        addon:StartNewSearch(req_members, active_panel)

        -- Don't worry about the active panel here, as the PVEFrame contains
        -- all of them anyway
        HideUIPanel(PVEFrame)
    else
        -- immediately update the tooltip
        ButtonTooltip(button)

        -- show advanced menu
        menu_frame:Show()
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
        menu_frame:SetSize(150,200)
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

        LFGListFrame.SearchPanel:HookScript('OnHide', function()
            menu_frame:Hide()
        end)

        local function OnEnterPressed(self)
            self:ClearFocus()
        end
        local function OnEscapePressed(self)
            self:ClearFocus()
        end

        local at_least = CreateFrame('EditBox', 'PremadeNotifierMenuFrame_AtLeast', menu_frame, 'InputBoxTemplate')
        at_least:SetSize(30,10)
        at_least:SetText('0')
        at_least:SetAutoFocus(false)
        at_least:SetFontObject(ChatFontNormal)

        local at_most = CreateFrame('EditBox', 'PremadeNotifierMenuFrame_AtMost', menu_frame, 'InputBoxTemplate')
        at_most:SetSize(30,10)
        at_most:SetText('40')
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

        at_most:SetScript('OnEscapePressed', OnEscapePressed)
        at_most:SetScript('OnEnterPressed', OnEscapePressed)
    end
end
