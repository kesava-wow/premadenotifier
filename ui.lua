--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local addon = PremadeNotifierFrame
local button

local tooltip_default_title = 'Continuous search'
local tooltip_default_text = 'Continuously search for this filter in the background and open the search results when an event is found.\n\nRight click to search without closing the UI.\nCtrl-click to search with a minimum member requirement of 2.\nShift-click to search with a minimum member requirement of 10.'

local tooltip_search_title = 'Searching...'
local tooltip_search_text = '\nClick again to cancel.'

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

    if mouse_button == 'LeftButton' then
        -- Don't worry about the active panel here, as the PVEFrame contains
        -- all of them anyway
        HideUIPanel(PVEFrame)
    else
        -- immediately update the tooltip
        ButtonTooltip(button)
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

    -- fetch result id from one of the report options
    local resultID = tonumber(menu[3].menuList[1].arg1)
    if not resultID then return end

    if not menu.pn_modified then
        -- insert our ignore option
        tinsert(menu, 4, {
            text='Ignore',
            tooltipOnButton=true,
            tooltipTitle='Ignore',
            tooltipText="Don't notify about this event when continuously searching (unless the title or leader changes)."
        })
    elseif menu.pn_modified == resultID then
        -- stop recursing if the menu was already modified for this entry
        return
    end

    menu.pn_modified = resultID

    if menu[2] and menu[2].text == "Whisper" then
        -- this is a player; just disable the ignore option
        menu[4].disabled = true
    else
        menu[4].disabled = nil
        menu[4].checked = addon:IsIgnored(resultID)
        menu[4].func = addon.ToggleIgnore
        menu[4].arg1 = resultID
        menu[4].arg2 = menu
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
end
