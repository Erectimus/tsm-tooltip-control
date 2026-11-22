local _, ns = ...

-- Options panel: Esc > Options > AddOns > TSM Tooltip Control
--
--  [Your headings]        [Datapoints in heading]   [Available datapoints]
--   (Hidden)               Min Buyout                TSM AuctionDB
--   Prices                 Market Value                Region Market Avg
--   ...                    ...                       TSM General Info ...

local COLUMN_WIDTH = 196
local COLUMN_GAP = 12
local LIST_HEIGHT = 300
local ROW_HEIGHT = 18
local HIDDEN_KEY = 0

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local canvas = CreateFrame("Frame")
canvas.name = ns.TITLE
canvas:Hide()

local selectedHeading = nil -- HIDDEN_KEY or heading index
local selectedAssigned = nil -- datapoint id
local selectedAvailable = nil -- datapoint id
local Refresh -- forward declaration

-- ============================================================================
-- Helpers
-- ============================================================================

---@return string displayName The custom name if renamed, otherwise TSM's label
---@return string? section The TSM section the datapoint comes from
---@return string originalLabel TSM's label
local function DisplayName(id)
	local entry = ns.db.catalog[id]
	local label, section
	if entry then
		label, section = entry.label, entry.section
	else
		section, label = strmatch(id, "^(.-)" .. ns.ID_SEP .. "(.*)$")
		label = label or id
	end
	return ns.GetRename(id) or label, section, label
end

---Text and tooltip for a datapoint row in either datapoint list.
local function DatapointRow(id, indent)
	local name, section, original = DisplayName(id)
	local text, tooltip = name, section and ("From " .. section) or nil
	if name ~= original then
		text = name .. " |cff808080(" .. original .. ")|r"
		tooltip = (tooltip and (tooltip .. "\n") or "") .. "TSM name: " .. original
	end
	local muted = ns.IsMuted(id)
	if muted then
		tooltip = (tooltip and (tooltip .. "\n") or "") .. "Shown muted"
	end
	return { key = id, text = text, color = muted and { 0.5, 0.5, 0.5 } or { 1, 1, 1 }, indent = indent, tooltip = tooltip, sortName = name }
end

local function GetSelectedList()
	if selectedHeading == HIDDEN_KEY then
		return ns.db.hidden
	end
	local heading = selectedHeading and ns.db.headings[selectedHeading]
	if not heading or heading.spacer or heading.standalone then
		return nil
	end
	return heading.items
end

local function GetSelectedHeading()
	return selectedHeading and selectedHeading ~= HIDDEN_KEY and ns.db.headings[selectedHeading] or nil
end

local function IndexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
end

local function Changed()
	ns.InvalidateLayout()
	Refresh()
end

local function CreateButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function CreateCheckbox(parent, text, tooltipText, getter, setter)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	local label = check.Text or check.text
	if not label then
		label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	end
	label:SetText(text)
	check:SetScript("OnClick", function(self)
		setter(self:GetChecked() and true or false)
		Changed()
	end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, 1, 1, 1)
		GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	check.Update = function(self)
		self:SetChecked(getter())
	end
	return check
end

-- ============================================================================
-- Name prompt (new / rename heading)
-- ============================================================================

local function GetPopupEditBox(popup)
	return (popup.GetEditBox and popup:GetEditBox()) or popup.editBox or popup.EditBox
end

StaticPopupDialogs["TSMTOOLTIPCONTROL_HEADING_NAME"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 64,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnShow = function(self, data)
		local editBox = GetPopupEditBox(self)
		editBox:SetText(data and data.default or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	OnAccept = function(self, data)
		data.callback(GetPopupEditBox(self):GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local popup = self:GetParent()
		local data = popup.data
		if data then
			data.callback(self:GetText())
		end
		popup:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
}

StaticPopupDialogs["TSMTOOLTIPCONTROL_CONFIRM"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(_, data)
		data.callback()
	end,
}

---@param allowEmpty? boolean Pass empty text through to the callback (used to clear a rename)
local function PromptName(prompt, default, callback, allowEmpty)
	StaticPopup_Show("TSMTOOLTIPCONTROL_HEADING_NAME", prompt, nil, {
		default = default,
		callback = function(text)
			text = strtrim(text or "")
			if text ~= "" or allowEmpty then
				callback(text)
			end
		end,
	})
end

local function Confirm(prompt, callback)
	StaticPopup_Show("TSMTOOLTIPCONTROL_CONFIRM", prompt, nil, { callback = callback })
end

-- ============================================================================
-- Scrolling list widget
-- ============================================================================

local function CreateList(parent, titleText, onSelect, onDoubleClick)
	local list = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
	list:SetSize(COLUMN_WIDTH, LIST_HEIGHT)
	if list.SetBackdrop then
		list:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		list:SetBackdropColor(0, 0, 0, 0.5)
		list:SetBackdropBorderColor(0.4, 0.4, 0.4)
	end

	local title = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 2, 4)
	title:SetText(titleText)
	list.title = title

	local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 5, -5)
	scroll:SetPoint("BOTTOMRIGHT", -27, 5)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(COLUMN_WIDTH - 32, 1)
	scroll:SetScrollChild(content)

	local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", 10, -10)
	empty:SetPoint("TOPRIGHT", -30, -10)
	empty:SetJustifyH("LEFT")
	list.empty = empty

	list.rows = {}
	list.items = {}

	local function OnRowClick(row)
		if row.item and not row.item.isHeader then
			onSelect(row.item.key)
		end
	end

	local function OnRowDoubleClick(row)
		if row.item and not row.item.isHeader and onDoubleClick then
			onDoubleClick(row.item.key)
		end
	end

	local function OnRowEnter(row)
		if row.item and row.item.tooltip then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(row.item.text, 1, 1, 1)
			GameTooltip:AddLine(row.item.tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end

	local function GetRow(index)
		local row = list.rows[index]
		if row then
			return row
		end
		row = CreateFrame("Button", nil, content)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", content, "RIGHT")
		row:RegisterForClicks("LeftButtonUp")

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)

		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetAllPoints()
		row.selected:SetColorTexture(1, 0.82, 0, 0.25)

		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)

		row:SetScript("OnClick", OnRowClick)
		row:SetScript("OnDoubleClick", OnRowDoubleClick)
		row:SetScript("OnEnter", OnRowEnter)
		row:SetScript("OnLeave", GameTooltip_Hide)
		list.rows[index] = row
		return row
	end

	---@param items table[] { key = any, text = string, isHeader = bool?, color = {r,g,b}?, tooltip = string? }
	function list:SetItems(items, selectedKey, emptyText)
		self.items = items
		for i, item in ipairs(items) do
			local row = GetRow(i)
			row.item = item
			row.text:SetText(item.text)
			if item.isHeader then
				row.text:SetFontObject("GameFontNormalSmall")
				row.text:SetTextColor(1, 0.82, 0)
				row.text:SetPoint("LEFT", 2, 0)
				row:EnableMouse(false)
			else
				row.text:SetFontObject("GameFontHighlightSmall")
				row.text:SetPoint("LEFT", item.indent and 12 or 4, 0)
				row:EnableMouse(true)
			end
			local color = item.color
			if color then
				row.text:SetTextColor(color[1], color[2], color[3])
			end
			row.selected:SetShown(not item.isHeader and selectedKey ~= nil and item.key == selectedKey)
			row:Show()
		end
		for i = #items + 1, #self.rows do
			self.rows[i].item = nil
			self.rows[i]:Hide()
		end
		content:SetHeight(max(1, #items * ROW_HEIGHT))
		self.empty:SetText(#items == 0 and (emptyText or "") or "")
	end

	return list
end

-- ============================================================================
-- Actions
-- ============================================================================

local function NewHeading()
	PromptName("Name for the new heading:", "", function(name)
		tinsert(ns.db.headings, { name = name, items = {} })
		selectedHeading = #ns.db.headings
		selectedAssigned = nil
		Changed()
	end)
end

local function NewSpacer()
	-- Insert below the selected heading, or at the end
	local index = GetSelectedHeading() and (selectedHeading + 1) or (#ns.db.headings + 1)
	tinsert(ns.db.headings, index, { spacer = true, items = {} })
	selectedHeading = index
	selectedAssigned = nil
	Changed()
end

local function RenameDatapoint(id)
	if not id then
		return
	end
	local name, _, original = DisplayName(id)
	PromptName(format("Rename \"%s\":\n(leave empty to use TSM's name)", original), name, function(newName)
		ns.SetRename(id, newName ~= original and newName or nil)
		Refresh()
	end, true)
end

local function RenameHeading()
	local heading = GetSelectedHeading()
	if not heading or heading.spacer then
		return
	elseif heading.standalone then
		RenameDatapoint(heading.items[1])
		return
	end
	PromptName("Rename heading:", heading.name, function(name)
		heading.name = name
		Changed()
	end)
end

local function DeleteHeading()
	local heading = selectedHeading and ns.db.headings[selectedHeading]
	if not heading then
		return
	end
	local index = selectedHeading
	local function Delete()
		tremove(ns.db.headings, index)
		selectedHeading = nil
		selectedAssigned = nil
		Changed()
	end
	if heading.spacer or heading.standalone or #heading.items == 0 then
		-- Nothing to lose: a standalone datapoint just goes back to the available list
		Delete()
	else
		Confirm(format("Delete the heading \"%s\"?\nIts datapoints go back to their TSM headings.", heading.name), Delete)
	end
end

local function MoveHeading(delta)
	local headings = ns.db.headings
	local index = selectedHeading
	if not index or index == HIDDEN_KEY then
		return
	end
	local target = index + delta
	if target < 1 or target > #headings then
		return
	end
	headings[index], headings[target] = headings[target], headings[index]
	selectedHeading = target
	Changed()
end

local function MoveAssigned(delta)
	local list = GetSelectedList()
	local index = list and selectedAssigned and IndexOf(list, selectedAssigned)
	if not index then
		return
	end
	local target = index + delta
	if target < 1 or target > #list then
		return
	end
	list[index], list[target] = list[target], list[index]
	Changed()
end

local function RemoveAssigned(id)
	id = id or selectedAssigned
	if not id then
		return
	end
	ns.Unassign(id)
	selectedAssigned = nil
	selectedAvailable = id
	Changed()
end

local function AddAvailable(id)
	id = id or selectedAvailable
	local list = GetSelectedList()
	if not id or not list then
		if not list then
			ns.Print("select or create a heading first.")
		end
		return
	end
	ns.Unassign(id)
	tinsert(list, id)
	selectedAvailable = nil
	selectedAssigned = id
	Changed()
end

local function PromoteDatapoint(id)
	if not id then
		return
	end
	-- Insert below the selected entry in the headings list, or at the end
	local index = GetSelectedHeading() and (selectedHeading + 1) or nil
	selectedHeading = ns.AddStandalone(id, index)
	selectedAssigned, selectedAvailable = nil, nil
	Changed()
end

local function ToggleMuted(id)
	if not id then
		return
	end
	ns.SetMuted(id, not ns.IsMuted(id))
	Refresh()
end

---The datapoint the middle column's buttons act on: the selected datapoint, or
---the datapoint of a selected heading-level entry.
local function GetAssignedTarget()
	if selectedAssigned then
		return selectedAssigned
	end
	local heading = GetSelectedHeading()
	return heading and heading.standalone and heading.items[1] or nil
end

local function ForgetAvailable()
	if not selectedAvailable then
		return
	end
	ns.db.catalog[selectedAvailable] = nil
	selectedAvailable = nil
	Refresh()
end

-- ============================================================================
-- Layout
-- ============================================================================

local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ns.TITLE)

local subtitle = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(COLUMN_WIDTH * 3 + COLUMN_GAP * 2)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Create your own headings and move TSM datapoints into them. "
	.. "Which datapoints appear at all is still controlled in TSM > Settings > Tooltip Settings. "
	.. "Datapoints show up in the right-hand list after you've seen them on an item tooltip. "
	.. "Requires TSM's \"Embed TSM tooltip\" option.")

local enabledCheck = CreateCheckbox(canvas, "Enabled",
	"Rearrange TSM's tooltip lines using the headings below.",
	function() return ns.db.enabled end,
	function(value) ns.db.enabled = value end)
enabledCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -10)

local unassignedCheck = CreateCheckbox(canvas, "Show unassigned datapoints under their TSM headings",
	"When unchecked, only datapoints you've placed under one of your headings are shown.",
	function() return ns.db.showUnassigned end,
	function(value) ns.db.showUnassigned = value end)
unassignedCheck:SetPoint("LEFT", enabledCheck, "RIGHT", 90, 0)

local headingList = CreateList(canvas, "Your headings",
	function(key)
		selectedHeading = key
		selectedAssigned = nil
		Refresh()
	end,
	function(key)
		if key ~= HIDDEN_KEY then
			selectedHeading = key
			RenameHeading()
		end
	end)
headingList:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 4, -26)

local assignedList = CreateList(canvas, "Datapoints in heading",
	function(key)
		selectedAssigned = key
		Refresh()
	end,
	RemoveAssigned)
assignedList:SetPoint("TOPLEFT", headingList, "TOPRIGHT", COLUMN_GAP, 0)

local availableList = CreateList(canvas, "Available datapoints",
	function(key)
		selectedAvailable = key
		Refresh()
	end,
	AddAvailable)
availableList:SetPoint("TOPLEFT", assignedList, "TOPRIGHT", COLUMN_GAP, 0)

local HALF = (COLUMN_WIDTH - 4) / 2
local THIRD = (COLUMN_WIDTH - 8) / 3

local newButton = CreateButton(canvas, "New", THIRD, NewHeading)
newButton:SetPoint("TOPLEFT", headingList, "BOTTOMLEFT", 0, -6)
local spacerButton = CreateButton(canvas, "Spacer", THIRD, NewSpacer)
spacerButton:SetPoint("LEFT", newButton, "RIGHT", 4, 0)
spacerButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Add Spacer", 1, 1, 1)
	GameTooltip:AddLine("Adds one blank line between the headings around it. Spacers with nothing below or above them are skipped.", nil, nil, nil, true)
	GameTooltip:Show()
end)
spacerButton:SetScript("OnLeave", GameTooltip_Hide)
local renameButton = CreateButton(canvas, "Rename", THIRD, RenameHeading)
renameButton:SetPoint("LEFT", spacerButton, "RIGHT", 4, 0)
local deleteButton = CreateButton(canvas, "Delete", THIRD, DeleteHeading)
deleteButton:SetPoint("TOPLEFT", newButton, "BOTTOMLEFT", 0, -4)
local headingUpButton = CreateButton(canvas, "Up", THIRD, function() MoveHeading(-1) end)
headingUpButton:SetPoint("LEFT", deleteButton, "RIGHT", 4, 0)
local headingDownButton = CreateButton(canvas, "Down", THIRD, function() MoveHeading(1) end)
headingDownButton:SetPoint("LEFT", headingUpButton, "RIGHT", 4, 0)

local assignedUpButton = CreateButton(canvas, "Move Up", HALF, function() MoveAssigned(-1) end)
assignedUpButton:SetPoint("TOPLEFT", assignedList, "BOTTOMLEFT", 0, -6)
local assignedDownButton = CreateButton(canvas, "Move Down", HALF, function() MoveAssigned(1) end)
assignedDownButton:SetPoint("LEFT", assignedUpButton, "RIGHT", 4, 0)
local assignedRenameButton = CreateButton(canvas, "Rename", HALF, function() RenameDatapoint(selectedAssigned) end)
assignedRenameButton:SetPoint("TOPLEFT", assignedUpButton, "BOTTOMLEFT", 0, -4)
local removeButton = CreateButton(canvas, "Remove", HALF, function() RemoveAssigned() end)
removeButton:SetPoint("LEFT", assignedRenameButton, "RIGHT", 4, 0)

local PROMOTE_TOOLTIP = "Show this datapoint at the same level as headings, as if it were its own heading. "
	.. "It appears in Your headings, where you can move it with Up / Down and put it back with Delete."
local function AddPromoteTooltip(button)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Show at Heading Level", 1, 1, 1)
		GameTooltip:AddLine(PROMOTE_TOOLTIP, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end
local assignedPromoteButton = CreateButton(canvas, "Show at Heading Level", COLUMN_WIDTH, function() PromoteDatapoint(selectedAssigned) end)
assignedPromoteButton:SetPoint("TOPLEFT", assignedRenameButton, "BOTTOMLEFT", 0, -4)
AddPromoteTooltip(assignedPromoteButton)

local addButton = CreateButton(canvas, "<< Add to Heading", COLUMN_WIDTH, function() AddAvailable() end)
addButton:SetPoint("TOPLEFT", availableList, "BOTTOMLEFT", 0, -6)
local availableRenameButton = CreateButton(canvas, "Rename", HALF, function() RenameDatapoint(selectedAvailable) end)
availableRenameButton:SetPoint("TOPLEFT", addButton, "BOTTOMLEFT", 0, -4)
local forgetButton = CreateButton(canvas, "Forget", HALF, ForgetAvailable)
forgetButton:SetPoint("LEFT", availableRenameButton, "RIGHT", 4, 0)
local availablePromoteButton = CreateButton(canvas, "Show at Heading Level", COLUMN_WIDTH, function() PromoteDatapoint(selectedAvailable) end)
availablePromoteButton:SetPoint("TOPLEFT", availableRenameButton, "BOTTOMLEFT", 0, -4)
AddPromoteTooltip(availablePromoteButton)

local MUTE_TOOLTIP = "Draw this datapoint in gray, as secondary information, so the lines you care about stand out. "
	.. "Click again to show it normally."
local function AddMuteTooltip(button)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self:GetText(), 1, 1, 1)
		GameTooltip:AddLine(MUTE_TOOLTIP, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end
local assignedMuteButton = CreateButton(canvas, "Mute", COLUMN_WIDTH, function() ToggleMuted(GetAssignedTarget()) end)
assignedMuteButton:SetPoint("TOPLEFT", assignedPromoteButton, "BOTTOMLEFT", 0, -4)
AddMuteTooltip(assignedMuteButton)
local availableMuteButton = CreateButton(canvas, "Mute", COLUMN_WIDTH, function() ToggleMuted(selectedAvailable) end)
availableMuteButton:SetPoint("TOPLEFT", availablePromoteButton, "BOTTOMLEFT", 0, -4)
AddMuteTooltip(availableMuteButton)

forgetButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Forget", 1, 1, 1)
	GameTooltip:AddLine("Remove a datapoint you no longer see from this list. It comes back the next time it appears on a tooltip.", nil, nil, nil, true)
	GameTooltip:Show()
end)
forgetButton:SetScript("OnLeave", GameTooltip_Hide)

local resetButton = CreateButton(canvas, "Reset Headings", HALF, function()
	Confirm("Delete all of your headings and hidden datapoints?\n(Renamed and muted datapoints keep those settings.)", function()
		ns.ResetAll()
		selectedHeading, selectedAssigned, selectedAvailable = nil, nil, nil
		Refresh()
	end)
end)
resetButton:SetPoint("TOP", enabledCheck, "TOP", 0, 0)
resetButton:SetPoint("RIGHT", availableList, "RIGHT", 0, 0)

local hint = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", deleteButton, "BOTTOMLEFT", 0, -64)
hint:SetWidth(COLUMN_WIDTH * 3 + COLUMN_GAP * 2)
hint:SetJustifyH("LEFT")
hint:SetText("Tip: double-click an available datapoint to add it, double-click a datapoint in a heading to remove it, "
	.. "and double-click a heading to rename it. Put a datapoint under (Hidden) to never show it. "
	.. "Rename a datapoint to change its label on tooltips; leave the name empty to go back to TSM's. "
	.. "Mute a datapoint to show it in gray as secondary information.")

-- ============================================================================
-- Refresh
-- ============================================================================

local GRAY = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }

Refresh = function()
	if not canvas:IsVisible() or not ns.db then
		return
	end
	local db = ns.db
	if selectedHeading and selectedHeading ~= HIDDEN_KEY and not db.headings[selectedHeading] then
		selectedHeading = nil
	end

	enabledCheck:Update()
	unassignedCheck:Update()

	-- Headings
	local items = {
		{ key = HIDDEN_KEY, text = format("(Hidden)  [%d]", #db.hidden), color = GRAY,
			tooltip = "Datapoints placed here are never shown on tooltips." },
	}
	for index, heading in ipairs(db.headings) do
		if heading.spacer then
			tinsert(items, { key = index, text = "- - - spacer - - -", color = GRAY,
				tooltip = "A blank line between the headings above and below." })
		elseif heading.standalone then
			local id = heading.items[1]
			local name, section = DisplayName(id)
			local muted = ns.IsMuted(id)
			tinsert(items, { key = index, text = "|cff808080>|r " .. name, color = muted and GRAY or WHITE,
				tooltip = "Datapoint shown at heading level" .. (section and (" (from " .. section .. ")") or "") .. "."
					.. (muted and "\nShown muted" or "") })
		else
			tinsert(items, { key = index, text = format("%s  [%d]", heading.name, #heading.items), color = WHITE })
		end
	end
	headingList:SetItems(items, selectedHeading)

	-- Datapoints in the selected heading
	local list = GetSelectedList()
	if selectedAssigned and not (list and IndexOf(list, selectedAssigned)) then
		selectedAssigned = nil
	end
	items = {}
	if list then
		for _, id in ipairs(list) do
			tinsert(items, DatapointRow(id))
		end
	end
	local selectedIsSpacer = GetSelectedHeading() and GetSelectedHeading().spacer
	local selectedIsStandalone = GetSelectedHeading() and GetSelectedHeading().standalone
	if selectedHeading == HIDDEN_KEY then
		assignedList.title:SetText("Hidden datapoints")
	elseif selectedIsSpacer then
		assignedList.title:SetText("Spacer")
	elseif selectedIsStandalone then
		assignedList.title:SetText("Heading-level datapoint")
	elseif list then
		assignedList.title:SetText("In \"" .. db.headings[selectedHeading].name .. "\"")
	else
		assignedList.title:SetText("Datapoints in heading")
	end
	assignedList:SetItems(items, selectedAssigned,
		list and "Add datapoints from the list on the right."
			or selectedIsSpacer and "Spacers add a blank line and don't hold datapoints. Use Up / Down to position it."
			or selectedIsStandalone and "This datapoint is shown at heading level. Use Up / Down to position it, Rename to change its label, and Delete to put it back."
			or "Select a heading, or create one with New.")

	-- Available (unassigned) datapoints, grouped by TSM section
	local assignment = ns.GetAssignment()
	local bySection, sectionNames = {}, {}
	for id, entry in pairs(db.catalog) do
		if assignment[id] == nil then
			local section = entry.section or "?"
			if not bySection[section] then
				bySection[section] = {}
				tinsert(sectionNames, section)
			end
			tinsert(bySection[section], id)
		end
	end
	if selectedAvailable and assignment[selectedAvailable] ~= nil then
		selectedAvailable = nil
	end
	sort(sectionNames)
	items = {}
	for _, section in ipairs(sectionNames) do
		tinsert(items, { key = section, text = section, isHeader = true })
		local rows = {}
		for _, id in ipairs(bySection[section]) do
			tinsert(rows, DatapointRow(id, true))
		end
		sort(rows, function(a, b) return a.sortName < b.sortName end)
		for _, row in ipairs(rows) do
			tinsert(items, row)
		end
	end
	availableList:SetItems(items, selectedAvailable,
		next(db.catalog) and "Everything has been placed." or "Hover over some items to discover TSM's datapoints.")

	-- Button states
	local hasHeading = selectedHeading and selectedHeading ~= HIDDEN_KEY
	renameButton:SetEnabled(hasHeading and not selectedIsSpacer or false)
	deleteButton:SetEnabled(hasHeading and true or false)
	headingUpButton:SetEnabled(hasHeading and selectedHeading > 1 or false)
	headingDownButton:SetEnabled(hasHeading and selectedHeading < #db.headings or false)
	local assignedIndex = list and selectedAssigned and IndexOf(list, selectedAssigned)
	assignedUpButton:SetEnabled(assignedIndex and assignedIndex > 1 or false)
	assignedDownButton:SetEnabled(assignedIndex and assignedIndex < #list or false)
	removeButton:SetEnabled(assignedIndex and true or false)
	assignedRenameButton:SetEnabled(assignedIndex and true or false)
	availableRenameButton:SetEnabled(selectedAvailable and true or false)
	assignedPromoteButton:SetEnabled(assignedIndex and true or false)
	availablePromoteButton:SetEnabled(selectedAvailable and true or false)
	addButton:SetEnabled((list and selectedAvailable) and true or false)
	forgetButton:SetEnabled(selectedAvailable and true or false)
	local assignedTarget = (assignedIndex and selectedAssigned) or (selectedIsStandalone and GetSelectedHeading().items[1]) or nil
	assignedMuteButton:SetEnabled(assignedTarget and true or false)
	assignedMuteButton:SetText(assignedTarget and ns.IsMuted(assignedTarget) and "Unmute" or "Mute")
	availableMuteButton:SetEnabled(selectedAvailable and true or false)
	availableMuteButton:SetText(selectedAvailable and ns.IsMuted(selectedAvailable) and "Unmute" or "Mute")
end

canvas:SetScript("OnShow", Refresh)
ns.OnCatalogChanged = Refresh

-- ============================================================================
-- Registration
-- ============================================================================

local category = nil
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(canvas, ns.TITLE)
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(canvas)
end

function ns.OpenOptions()
	if Settings and Settings.OpenToCategory and category then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(canvas)
		InterfaceOptionsFrame_OpenToCategory(canvas)
	end
end
