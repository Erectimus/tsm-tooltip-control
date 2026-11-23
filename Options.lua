local _, ns = ...

-- Options panel: Esc > Options > AddOns > TSM Tooltip Control
--
--  [Your layout]                         [Available datapoints]
--   Prices                                TSM AuctionDB
--     Min Buyout                            Region Market Avg
--     Market Value                        TSM General Info
--   - - - spacer - - -                      ...
--   > Disenchant Value
--   (Hidden)
--     Region Sale Avg
--
-- Everything is moved by dragging: datapoints into a heading, between
-- headings (shown at heading level), into (Hidden) or back to Available;
-- headings and spacers up and down.

local TREE_WIDTH = 372
local AVAILABLE_WIDTH = 228
local COLUMN_GAP = 12
local TOTAL_WIDTH = TREE_WIDTH + COLUMN_GAP + AVAILABLE_WIDTH
local LIST_HEIGHT = 300
local ROW_HEIGHT = 18
local HIDDEN_KEY = 0 -- list key for the hidden datapoints (heading keys start at 1)
local HEADING_INDENT = 4
local POINT_INDENT = 20
local AUTOSCROLL_EDGE = 20
local AUTOSCROLL_SPEED = 300

local GOLD = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GRAY = { 0.5, 0.5, 0.5 }
local DIM = { 0.4, 0.4, 0.4 }

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local LIST_BACKDROP = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local canvas = CreateFrame("Frame")
canvas.name = ns.TITLE
canvas:Hide()

-- The selected row: a datapoint id (string) or a heading / spacer entry (table)
local selected = nil
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

---Row for a datapoint in either list.
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
	return {
		text = text,
		tooltipTitle = name,
		tooltip = tooltip,
		color = muted and GRAY or WHITE,
		indent = indent,
		sel = id,
		drag = { id = id },
		sortName = name,
	}
end

local function IndexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
end

---The heading entry list or hidden list a datapoint list key refers to.
local function ListFor(key)
	if key == HIDDEN_KEY then
		return ns.db.hidden
	end
	return ns.db.headings[key].items
end

---Index of the standalone entry showing `id`, if any.
local function StandaloneIndex(id)
	for index, heading in ipairs(ns.db.headings) do
		if heading.standalone and heading.items[1] == id then
			return index
		end
	end
end

local function SelectedEntry()
	return type(selected) == "table" and selected or nil
end

local function SelectedId()
	return type(selected) == "string" and selected or nil
end

---Index in the headings list of the selected entry, or of the heading the
---selected datapoint is in. Nil for available or hidden datapoints.
local function SelectedBlockIndex()
	local entry = SelectedEntry()
	if entry then
		return IndexOf(ns.db.headings, entry)
	end
	local id = SelectedId()
	local where = id and ns.GetAssignment()[id]
	return type(where) == "number" and where or nil
end

local function Changed()
	ns.InvalidateLayout()
	Refresh()
end

local function SetTooltip(frame, title, body)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 1, 1)
		GameTooltip:AddLine(type(body) == "function" and body(self) or body, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
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
	SetTooltip(check, text, tooltipText)
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
-- Moving things (used by drag and drop)
-- ============================================================================

---Moves a heading or spacer to `index` in the headings list (before the entry
---currently there).
local function MoveEntry(entry, index)
	local headings = ns.db.headings
	local from = IndexOf(headings, entry)
	if not from then
		return
	end
	if from < index then
		index = index - 1
	end
	tremove(headings, from)
	tinsert(headings, min(max(index, 1), #headings + 1), entry)
end

---Shows a datapoint at heading level at `index` in the headings list.
local function MovePointToTop(id, index)
	local from = StandaloneIndex(id)
	if from and from < index then
		-- AddStandalone removes the old entry first, which shifts the ones after it
		index = index - 1
	end
	ns.AddStandalone(id, index)
end

---Moves a datapoint to position `pos` of a heading's list or the hidden list.
local function MovePointInto(id, key, pos)
	local list = ListFor(key)
	local from = IndexOf(list, id)
	if from and from < pos then
		pos = pos - 1
	end
	-- `list` stays valid even if Unassign removes a standalone entry before it
	ns.Unassign(id)
	tinsert(list, min(max(pos, 1), #list + 1), id)
end

-- ============================================================================
-- Actions
-- ============================================================================

---Where new headings, spacers and heading-level datapoints go: below the
---selected heading (or the heading of the selected datapoint), else at the end.
local function InsertIndex()
	local index = SelectedBlockIndex()
	return index and (index + 1) or (#ns.db.headings + 1)
end

local function NewHeading()
	PromptName("Name for the new heading:", "", function(name)
		local entry = { name = name, items = {} }
		tinsert(ns.db.headings, InsertIndex(), entry)
		selected = entry
		Changed()
	end)
end

local function NewSpacer()
	local entry = { spacer = true, items = {} }
	tinsert(ns.db.headings, InsertIndex(), entry)
	selected = entry
	Changed()
end

local function RenameDatapoint(id)
	local name, _, original = DisplayName(id)
	PromptName(format("Rename \"%s\":\n(leave empty to use TSM's name)", original), name, function(newName)
		ns.SetRename(id, newName ~= original and newName or nil)
		Refresh()
	end, true)
end

local function RenameHeading(entry)
	PromptName("Rename heading:", entry.name, function(name)
		entry.name = name
		Changed()
	end)
end

local function RenameSelected()
	local entry = SelectedEntry()
	if entry and not entry.spacer then
		RenameHeading(entry)
	elseif SelectedId() then
		RenameDatapoint(SelectedId())
	end
end

local function DeleteEntry(entry)
	local function Delete()
		local index = IndexOf(ns.db.headings, entry)
		if index then
			tremove(ns.db.headings, index)
		end
		selected = nil
		Changed()
	end
	if entry.spacer or #entry.items == 0 then
		Delete()
	else
		Confirm(format("Delete the heading \"%s\"?\nIts datapoints go back to Available.", entry.name), Delete)
	end
end

---Delete for headings and spacers, Remove (back to Available) for datapoints.
local function DeleteSelected()
	local entry = SelectedEntry()
	if entry then
		DeleteEntry(entry)
	elseif SelectedId() and ns.GetAssignment()[SelectedId()] ~= nil then
		ns.Unassign(SelectedId())
		Changed()
	end
end

local function PromoteSelected()
	local id = SelectedId()
	if not id or StandaloneIndex(id) then
		return
	end
	ns.AddStandalone(id, InsertIndex())
	Changed()
end

local function ToggleMutedSelected()
	local id = SelectedId()
	if id then
		ns.SetMuted(id, not ns.IsMuted(id))
		Refresh()
	end
end

local function ToggleHiddenSelected()
	local id = SelectedId()
	if not id then
		return
	end
	local wasHidden = ns.GetAssignment()[id] == true
	ns.Unassign(id)
	if not wasHidden then
		tinsert(ns.db.hidden, id)
	end
	Changed()
end

local function ForgetSelected()
	local id = SelectedId()
	if id and ns.GetAssignment()[id] == nil then
		ns.db.catalog[id] = nil
		selected = nil
		Refresh()
	end
end

-- ============================================================================
-- Scrolling list widget
-- ============================================================================

local drag = nil -- { id = id } or { entry = heading }, while dragging
local StartDrag, FinishDrag -- defined with the drag and drop code below

---Item fields:
---  text, color, font, indent  how the row looks
---  sel        selection key: a datapoint id or a heading entry
---  drag       what dragging the row moves: { id = id } or { entry = heading }
---  drop       what the row means as a drop target (layout list only)
---  inert      not clickable (section names, placeholders)
---  tooltipTitle, tooltip
local function CreateList(parent, titleText, width, onDoubleClick)
	local list = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
	list:SetSize(width, LIST_HEIGHT)
	if list.SetBackdrop then
		list:SetBackdrop(LIST_BACKDROP)
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
	content:SetSize(width - 32, 1)
	scroll:SetScrollChild(content)
	list.scroll = scroll
	list.content = content

	local empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", 10, -10)
	empty:SetPoint("TOPRIGHT", -30, -10)
	empty:SetJustifyH("LEFT")
	list.empty = empty

	list.rows = {}
	list.items = {}

	local function OnRowClick(row)
		if row.item and row.item.sel ~= nil then
			selected = row.item.sel
			Refresh()
		end
	end

	local function OnRowDoubleClick(row)
		if row.item and row.item.sel ~= nil and onDoubleClick then
			selected = row.item.sel
			onDoubleClick()
		end
	end

	local function OnRowEnter(row)
		if drag or not (row.item and row.item.tooltip) then
			return
		end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.item.tooltipTitle or row.item.text, 1, 1, 1)
		GameTooltip:AddLine(row.item.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end

	local function OnRowDragStart(row)
		if row.item and row.item.drag then
			selected = row.item.sel
			Refresh()
			StartDrag(row.item.drag, row.item.text)
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
		row:RegisterForDrag("LeftButton")

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
		row:SetScript("OnDragStart", OnRowDragStart)
		row:SetScript("OnDragStop", function() FinishDrag() end)
		list.rows[index] = row
		return row
	end

	function list:SetItems(items, emptyText)
		self.items = items
		for i, item in ipairs(items) do
			local row = GetRow(i)
			row.item = item
			row.text:SetFontObject(item.font or "GameFontHighlightSmall")
			row.text:SetText(item.text)
			row.text:SetPoint("LEFT", item.indent or HEADING_INDENT, 0)
			local color = item.color or WHITE
			row.text:SetTextColor(color[1], color[2], color[3])
			row:EnableMouse(not item.inert)
			row.selected:SetShown(item.sel ~= nil and item.sel == selected)
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
-- Layout
-- ============================================================================

local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ns.TITLE)

local subtitle = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(TOTAL_WIDTH)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Create your own headings and drag TSM datapoints into them. "
	.. "Which datapoints appear at all is still controlled in TSM > Settings > Tooltip Settings. "
	.. "Datapoints show up in the right-hand list after you've seen them on an item tooltip. "
	.. "Requires TSM's \"Embed TSM tooltip\" option.")

local enabledCheck = CreateCheckbox(canvas, "Enabled",
	"Rearrange TSM's tooltip lines using your layout below.",
	function() return ns.db.enabled end,
	function(value) ns.db.enabled = value end)
enabledCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -10)

local unassignedCheck = CreateCheckbox(canvas, "Show unassigned datapoints under their TSM headings",
	"When unchecked, only datapoints you've placed under one of your headings are shown.",
	function() return ns.db.showUnassigned end,
	function(value) ns.db.showUnassigned = value end)
unassignedCheck:SetPoint("LEFT", enabledCheck, "RIGHT", 90, 0)

local keepPlacementCheck = CreateCheckbox(canvas, "Remember where datapoints switched off in TSM were placed",
	"When checked, a datapoint you switch off in TSM > Settings > Tooltip Settings keeps its place in your layout "
	.. "and goes back there when you switch it on again.\n\n"
	.. "When unchecked, it's taken out of your layout, and you place it again after switching it back on.",
	function() return ns.db.keepDisabledPlacement end,
	function(value)
		ns.db.keepDisabledPlacement = value
		ns.ForgetInactivePlacements()
	end)
keepPlacementCheck:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 0, 0)

local tree = CreateList(canvas, "Your layout", TREE_WIDTH, RenameSelected)
tree:SetPoint("TOPLEFT", keepPlacementCheck, "BOTTOMLEFT", 4, -26)

local availableList = CreateList(canvas, "Available datapoints", AVAILABLE_WIDTH, RenameSelected)
availableList:SetPoint("TOPLEFT", tree, "TOPRIGHT", COLUMN_GAP, 0)

-- Buttons below the layout. They act on the selected row, in either list.
local newButton = CreateButton(canvas, "New Heading", 108, NewHeading)
newButton:SetPoint("TOPLEFT", tree, "BOTTOMLEFT", 0, -6)
SetTooltip(newButton, "New Heading", "Adds a heading below the selected one, or at the end.")
local spacerButton = CreateButton(canvas, "Spacer", 80, NewSpacer)
spacerButton:SetPoint("LEFT", newButton, "RIGHT", 4, 0)
SetTooltip(spacerButton, "Add Spacer",
	"Adds one blank line below the selected heading, or at the end. Spacers with nothing below or above them are skipped.")
local renameButton = CreateButton(canvas, "Rename", 88, RenameSelected)
renameButton:SetPoint("LEFT", spacerButton, "RIGHT", 4, 0)
SetTooltip(renameButton, "Rename",
	"Changes the selected heading's name, or the selected datapoint's label on tooltips. "
	.. "Leave a datapoint's name empty to go back to TSM's.")
local deleteButton = CreateButton(canvas, "Delete", 84, DeleteSelected)
deleteButton:SetPoint("LEFT", renameButton, "RIGHT", 4, 0)
SetTooltip(deleteButton, function(self) return self:GetText() end, function(self)
	if self:GetText() == "Remove" then
		return "Takes the datapoint out of your layout and puts it back in Available."
	end
	return "Deletes the selected heading or spacer. Its datapoints go back to Available."
end)

local muteButton = CreateButton(canvas, "Mute", 80, ToggleMutedSelected)
muteButton:SetPoint("TOPLEFT", newButton, "BOTTOMLEFT", 0, -4)
SetTooltip(muteButton, function(self) return self:GetText() end,
	"Draws the datapoint in gray, as secondary information, so the lines you care about stand out. "
	.. "Click again to show it normally.")
local hideButton = CreateButton(canvas, "Hide", 80, ToggleHiddenSelected)
hideButton:SetPoint("LEFT", muteButton, "RIGHT", 4, 0)
SetTooltip(hideButton, function(self) return self:GetText() end,
	"Moves the datapoint to (Hidden) so it's never shown. Unhide puts it back in Available.")
local promoteButton = CreateButton(canvas, "Show at Heading Level", TREE_WIDTH - 168, PromoteSelected)
promoteButton:SetPoint("LEFT", hideButton, "RIGHT", 4, 0)
SetTooltip(promoteButton, "Show at Heading Level",
	"Shows the datapoint at the same level as headings, as if it were its own heading. "
	.. "You can also drag a datapoint between two headings. Drag it into a heading to put it back.")

local forgetButton = CreateButton(canvas, "Forget", AVAILABLE_WIDTH, ForgetSelected)
forgetButton:SetPoint("TOPLEFT", availableList, "BOTTOMLEFT", 0, -6)
SetTooltip(forgetButton, "Forget",
	"Removes a datapoint you no longer see from this list. It comes back the next time it appears on a tooltip.")

local resetButton = CreateButton(canvas, "Reset Headings", 114, function()
	Confirm("Delete all of your headings and hidden datapoints?\n(Renamed and muted datapoints keep those settings.)", function()
		ns.ResetAll()
		selected = nil
		Refresh()
	end)
end)
resetButton:SetPoint("TOP", enabledCheck, "TOP", 0, 0)
resetButton:SetPoint("RIGHT", availableList, "RIGHT", 0, 0)

local hint = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", muteButton, "BOTTOMLEFT", 0, -10)
hint:SetWidth(TOTAL_WIDTH)
hint:SetJustifyH("LEFT")
hint:SetText("Drag datapoints into a heading, between headings to show them at heading level, "
	.. "into (Hidden) to never show them, or back to Available. Drag headings and spacers to reorder them. "
	.. "Double-click a heading or datapoint to rename it.")

-- ============================================================================
-- Drag and drop
-- ============================================================================

-- Rows of the layout list by what they show, rebuilt by Refresh. Datapoints
-- switched off in TSM have no row, so entries and points are ordered lists:
--   entry = { { index = headingIndex, row = rowIndex }, ... }
--   point[listKey] = { { pos = position, row = rowIndex }, ... }
--   empty[listKey] = rowIndex, hidden = rowIndex
local treeRows = { entry = {}, point = {}, empty = {} }

local ghost = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetSize(180, ROW_HEIGHT + 6)
if ghost.SetBackdrop then
	ghost:SetBackdrop(LIST_BACKDROP)
	ghost:SetBackdropColor(0, 0, 0, 0.85)
	ghost:SetBackdropBorderColor(1, 0.82, 0)
end
ghost.text = ghost:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
ghost.text:SetPoint("LEFT", 8, 0)
ghost.text:SetPoint("RIGHT", -8, 0)
ghost.text:SetJustifyH("LEFT")
ghost.text:SetWordWrap(false)
ghost:Hide()

-- Insertion line drawn above the rows of the layout list
local indicator = CreateFrame("Frame", nil, tree.content)
indicator:SetHeight(2)
indicator:SetFrameLevel(tree.content:GetFrameLevel() + 10)
local indicatorTexture = indicator:CreateTexture(nil, "OVERLAY")
indicatorTexture:SetAllPoints()
indicatorTexture:SetColorTexture(1, 0.82, 0, 0.9)
indicator:Hide()

local function CursorY(frame)
	local _, y = GetCursorPosition()
	return y / frame:GetEffectiveScale()
end

---What dropping at the cursor would do in the layout list:
---  { kind = "top", index = n }           insert in the headings list before entry n
---  { kind = "into", key = k, pos = p }   insert into heading k (or hidden) at position p
local function TreeTarget()
	if not tree.scroll:IsMouseOver() then
		return nil
	end
	local row, hit = nil, false
	for i = 1, #tree.items do
		row = tree.rows[i]
		if row:IsMouseOver() then
			hit = true
			break
		end
	end
	if not row then
		return nil
	end
	-- Below the last row counts as the lower half of the last row
	local upper = hit and CursorY(row) > (row:GetTop() + row:GetBottom()) / 2
	local drop = row.item.drop
	if drop.kind == "entry" then
		if upper then
			return { kind = "top", index = drop.index }
		elseif drop.isHeading then
			return { kind = "into", key = drop.index, pos = 1 }
		end
		return { kind = "top", index = drop.index + 1 }
	elseif drop.kind == "point" then
		return { kind = "into", key = drop.key, pos = upper and drop.pos or (drop.pos + 1) }
	elseif drop.kind == "empty" then
		return { kind = "into", key = drop.key, pos = 1 }
	elseif drop.kind == "hidden" then
		if upper then
			return { kind = "top", index = #ns.db.headings + 1 }
		end
		return { kind = "into", key = HIDDEN_KEY, pos = 1 }
	end
end

---What dropping the current drag at the cursor would do, or nil for nothing.
local function DropTarget()
	if availableList:IsMouseOver() then
		-- Back to Available: only for datapoints that are in the layout
		if drag.id and ns.GetAssignment()[drag.id] ~= nil then
			return { kind = "unassign" }
		end
		return nil
	end
	local target = TreeTarget()
	if target and drag.entry and target.kind == "into" then
		-- Headings and spacers can't go inside a heading: put them after it
		if target.key == HIDDEN_KEY then
			target = { kind = "top", index = #ns.db.headings + 1 }
		else
			target = { kind = "top", index = target.key + 1 }
		end
	end
	return target
end

local function ShowIndicator(target)
	indicator:Hide()
	if availableList.SetBackdropBorderColor then
		local unassign = target and target.kind == "unassign"
		availableList:SetBackdropBorderColor(unassign and 1 or 0.4, unassign and 0.82 or 0.4, unassign and 0 or 0.4)
	end
	if not target or target.kind == "unassign" then
		return
	end
	-- Rows are listed with their real list position; the line goes above the
	-- first shown row at or after the target position.
	local rowIndex, edge, indent
	if target.kind == "top" then
		rowIndex, edge, indent = treeRows.hidden, "TOP", 0
		for _, entry in ipairs(treeRows.entry) do
			if entry.index >= target.index then
				rowIndex = entry.row
				break
			end
		end
	else
		local points = treeRows.point[target.key] or {}
		indent = POINT_INDENT - 4
		for _, point in ipairs(points) do
			if point.pos >= target.pos then
				rowIndex, edge = point.row, "TOP"
				break
			end
		end
		if not rowIndex then
			if #points > 0 then
				rowIndex, edge = points[#points].row, "BOTTOM"
			else
				rowIndex, edge = treeRows.empty[target.key], "TOP"
			end
		end
	end
	local row = rowIndex and tree.rows[rowIndex]
	if not row then
		return
	end
	indicator:ClearAllPoints()
	indicator:SetPoint("LEFT", row, edge .. "LEFT", indent, 0)
	indicator:SetPoint("RIGHT", row, edge .. "RIGHT", 0, 0)
	indicator:Show()
end

---Scrolls the layout list while dragging near its top or bottom edge.
local function AutoScroll(elapsed)
	local scroll = tree.scroll
	local scale = scroll:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	if x < scroll:GetLeft() or x > scroll:GetRight() then
		return
	end
	local direction
	if y > scroll:GetTop() - AUTOSCROLL_EDGE and y < scroll:GetTop() + AUTOSCROLL_EDGE then
		direction = -1
	elseif y < scroll:GetBottom() + AUTOSCROLL_EDGE and y > scroll:GetBottom() - AUTOSCROLL_EDGE then
		direction = 1
	else
		return
	end
	local offset = scroll:GetVerticalScroll() + direction * AUTOSCROLL_SPEED * elapsed
	offset = min(max(offset, 0), scroll:GetVerticalScrollRange())
	if scroll.ScrollBar then
		scroll.ScrollBar:SetValue(offset)
	else
		scroll:SetVerticalScroll(offset)
	end
end

local function StopDrag()
	drag = nil
	ghost:Hide()
	ShowIndicator(nil)
end

local function ApplyDrop(source, target)
	if target.kind == "unassign" then
		ns.Unassign(source.id)
	elseif target.kind == "top" then
		if source.entry then
			MoveEntry(source.entry, target.index)
		else
			MovePointToTop(source.id, target.index)
		end
	else
		MovePointInto(source.id, target.key, target.pos)
	end
	selected = source.id or source.entry
	Changed()
end

StartDrag = function(source, text)
	GameTooltip:Hide()
	drag = source
	ghost.text:SetText(text)
	ghost:SetWidth(min(max(ghost.text:GetStringWidth() + 20, 80), 260))
	ghost:Show()
end

FinishDrag = function()
	if not drag then
		return
	end
	local source, target = drag, DropTarget()
	StopDrag()
	-- Switched off in TSM during the drag: it's no longer shown, so don't place it
	if target and not (source.id and not ns.IsDatapointActive(source.id)) then
		ApplyDrop(source, target)
	end
end

ghost:SetScript("OnUpdate", function(self, elapsed)
	if not drag then
		self:Hide()
		return
	end
	if not IsMouseButtonDown("LeftButton") then
		-- In case OnDragStop never reached the row (e.g. it was hidden mid-drag)
		FinishDrag()
		return
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	self:ClearAllPoints()
	self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 10)
	AutoScroll(elapsed)
	ShowIndicator(DropTarget())
end)

-- ============================================================================
-- Refresh
-- ============================================================================

local function AddRow(items, item)
	tinsert(items, item)
	return #items
end

local function BuildTree()
	local db = ns.db
	local items = {}
	treeRows = { entry = {}, point = {}, empty = {} }

	-- Datapoints switched off in TSM's tooltip settings are left out, but keep
	-- their place in the lists, so drop positions use the real list positions.
	local function AddPoints(key, list, emptyText)
		local rows = {}
		treeRows.point[key] = rows
		for pos, id in ipairs(list) do
			if ns.IsDatapointActive(id) then
				local row = DatapointRow(id, POINT_INDENT)
				row.drop = { kind = "point", key = key, pos = pos }
				tinsert(rows, { pos = pos, row = AddRow(items, row) })
			end
		end
		if #rows == 0 then
			treeRows.empty[key] = AddRow(items, { text = emptyText, color = DIM, indent = POINT_INDENT,
				inert = true, drop = { kind = "empty", key = key } })
		end
	end

	local function AddEntry(index, item)
		tinsert(treeRows.entry, { index = index, row = AddRow(items, item) })
	end

	for index, heading in ipairs(db.headings) do
		local drop = { kind = "entry", index = index }
		if heading.spacer then
			AddEntry(index, { text = "- - - spacer - - -", color = GRAY,
				font = "GameFontHighlightSmall", sel = heading, drag = { entry = heading }, drop = drop,
				tooltipTitle = "Spacer", tooltip = "A blank line between the headings above and below." })
		elseif heading.standalone then
			local id = heading.items[1]
			if ns.IsDatapointActive(id) then
				local row = DatapointRow(id, HEADING_INDENT)
				local _, section = DisplayName(id)
				row.text = "|cff808080>|r " .. row.text
				row.font = "GameFontNormal"
				row.color = ns.IsMuted(id) and GRAY or GOLD
				row.tooltip = "Shown at heading level" .. (section and (" (from " .. section .. ")") or "") .. "."
					.. (ns.IsMuted(id) and "\nShown muted" or "")
				row.drop = drop
				AddEntry(index, row)
			end
		else
			drop.isHeading = true
			AddEntry(index, { text = heading.name, color = GOLD, font = "GameFontNormal",
				sel = heading, drag = { entry = heading }, drop = drop })
			AddPoints(index, heading.items, "Drag datapoints here")
		end
	end

	treeRows.hidden = AddRow(items, { text = "(Hidden)", color = GRAY, font = "GameFontNormal", inert = true,
		drop = { kind = "hidden" } })
	AddPoints(HIDDEN_KEY, db.hidden, "Drag datapoints here to never show them")
	return items
end

local function BuildAvailable()
	local db = ns.db
	local assignment = ns.GetAssignment()
	local bySection, sectionNames = {}, {}
	for id, entry in pairs(db.catalog) do
		if assignment[id] == nil and ns.IsDatapointActive(id) then
			local section = entry.section or "?"
			if not bySection[section] then
				bySection[section] = {}
				tinsert(sectionNames, section)
			end
			tinsert(bySection[section], id)
		end
	end
	sort(sectionNames)
	local items = {}
	for _, section in ipairs(sectionNames) do
		tinsert(items, { text = section, color = GOLD, font = "GameFontNormalSmall", indent = 2, inert = true })
		local rows = {}
		for _, id in ipairs(bySection[section]) do
			tinsert(rows, DatapointRow(id, 12))
		end
		sort(rows, function(a, b) return a.sortName < b.sortName end)
		for _, row in ipairs(rows) do
			tinsert(items, row)
		end
	end
	return items
end

---The datapoints currently switched off in TSM's tooltip settings, as a string
---that changes whenever one is switched on or off.
local function InactiveSignature()
	local off = {}
	for id in pairs(ns.db.catalog) do
		if not ns.IsDatapointActive(id) then
			off[id] = true
		end
	end
	for id in pairs(ns.GetAssignment()) do
		if not ns.IsDatapointActive(id) then
			off[id] = true
		end
	end
	local ids = {}
	for id in pairs(off) do
		tinsert(ids, id)
	end
	sort(ids)
	return table.concat(ids, "\n")
end

local lastSignature = nil

Refresh = function()
	if not canvas:IsVisible() or not ns.db then
		return
	end
	local db = ns.db
	local assignment = ns.GetAssignment()
	lastSignature = InactiveSignature()

	-- Drop a selection that no longer exists
	if type(selected) == "table" and not IndexOf(db.headings, selected) then
		selected = nil
	elseif type(selected) == "string" and ((assignment[selected] == nil and not db.catalog[selected])
		or not ns.IsDatapointActive(selected)) then
		selected = nil
	end

	enabledCheck:Update()
	unassignedCheck:Update()
	keepPlacementCheck:Update()

	tree:SetItems(BuildTree())
	availableList:SetItems(BuildAvailable(),
		next(db.catalog) and "Everything has been placed." or "Hover over some items to discover TSM's datapoints.")

	-- Button states
	local entry, id = SelectedEntry(), SelectedId()
	local where = id and assignment[id] -- heading index, true (hidden) or nil (available)
	renameButton:SetEnabled((entry and not entry.spacer) or id ~= nil)
	deleteButton:SetText((id and "Remove") or "Delete")
	deleteButton:SetEnabled(entry ~= nil or where ~= nil)
	muteButton:SetEnabled(id ~= nil)
	muteButton:SetText(id and ns.IsMuted(id) and "Unmute" or "Mute")
	hideButton:SetEnabled(id ~= nil)
	hideButton:SetText(where == true and "Unhide" or "Hide")
	promoteButton:SetEnabled(id ~= nil and not StandaloneIndex(id))
	forgetButton:SetEnabled(id ~= nil and where == nil)
end

canvas:SetScript("OnShow", Refresh)
canvas:SetScript("OnHide", StopDrag)

-- TSM's settings window saves changes straight away, so while the panel is
-- open, check now and then whether a datapoint was switched on or off there.
local SETTINGS_CHECK_INTERVAL = 0.5
local sinceCheck = 0
canvas:SetScript("OnUpdate", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck < SETTINGS_CHECK_INTERVAL or drag or not ns.db then
		return
	end
	sinceCheck = 0
	if InactiveSignature() ~= lastSignature then
		Refresh()
	end
end)
ns.OnCatalogChanged = function()
	-- Don't rebuild the rows under an active drag
	if not drag then
		Refresh()
	end
end
ns.RefreshOptions = ns.OnCatalogChanged

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
