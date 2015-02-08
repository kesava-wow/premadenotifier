--[[
    PremadeNotifier
    Kesava-Auchindoun
    All rights reserved.
]]
local addon = PremadeNotifierFrame

local button = CreateFrame('Button','PremadeNotifierButton',LFGListFrame.SearchPanel.RefreshButton)
button:SetPoint('RIGHT', LFGListFrame.SearchPanel.RefreshButton, 'LEFT', -5, 0)
button:SetSize(20,20)

button:SetBackdropColor(1,1,1,1)

button.icon = button:CreateTexture(nil, 'ARTWORK', nil, 5)
button.icon:SetTexture('Interface\\Buttons\\UI-RefreshButton')
button.icon:SetAllPoints(button)

button:EnableMouse(true)
button:SetScript('OnClick', function()
    HideUIPanel(PVEFrame)
    addon:StartNewSearch()
end)