--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local addon = PremadeNotifierFrame

local button = CreateFrame('Button','PremadeNotifierButton',LFGListFrame.SearchPanel.RefreshButton)
button:SetPoint('RIGHT', LFGListFrame.SearchPanel.RefreshButton, 'LEFT', 0, 0)

-- modify the search entry menu dropdown --
hooksecurefunc('EasyMenu', function(menu,frame,anchor,x,y,display)
    if frame ~= LFGListFrameDropDown then return end
    -- fetch result id from one of the report options
    local resultID = menu[3].menuList[1].arg1

    if not menu.pn_modified then
        -- insert our ignore option
        tinsert(menu, 4, {
            text='Ignore',
            tooltipOnButton=true,
            tooltipTitle='Ignore',
            tooltipText="Don't notify about this event when continuously searching."
        })
    elseif menu.pn_modified == resultID then
        -- stop iterating if the menu was already modified for this entry
        return
    end

    menu.pn_modified = resultID
    menu[4].checked = addon:IsIgnored(resultID)
    menu[4].func = addon.ToggleIgnore
    menu[4].arg1 = resultID
    menu[4].arg2 = menu

    EasyMenu(menu, frame, anchor, x, y, display)
end)

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

-- script handlers --
local function ButtonOnMouseDown(button)
    button.icon:SetPoint('CENTER', button, 'CENTER', -2, -1)
end
local function ButtonOnMouseUp(button)
    button.icon:SetPoint('CENTER', button, 'CENTER', -1, 0)
end

local function ButtonOnClick(button, mouse_button)
    if mouse_button == 'LeftButton' then
        HideUIPanel(PVEFrame)
    end

    local req_members = IsShiftKeyDown() and 10 or IsControlKeyDown() and 2 or nil
    addon:StartNewSearch(req_members)
end

local function ButtonTooltip(button)
    GameTooltip:SetOwner(button, 'ANCHOR_RIGHT')
    GameTooltip:SetWidth(200)
    
    GameTooltip:AddLine('Continuous search')
    GameTooltip:AddLine(
        'Continuously search for this filter in the background and open the search results when an event is found.\n\nRight click to search without closing the UI.',
        1,1,1,true)

    GameTooltip:Show()
end
local function ButtonTooltipHide(button)
    GameTooltip:Hide()
end

button:SetScript('OnClick', ButtonOnClick)
button:SetScript('OnEnter', ButtonTooltip)
button:SetScript('OnLeave', ButtonTooltipHide)

button:SetScript('OnMouseDown', ButtonOnMouseDown)
button:SetScript('OnMouseUp', ButtonOnMouseUp)
