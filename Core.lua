local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.TITLE = "TSM Tooltip Control"

-- Separator used to build datapoint ids: "<TSM section> > <label>"
ns.ID_SEP = " > "

local DB_VERSION = 1

local function NewDefaults()
	return {
		version = DB_VERSION,
		enabled = true,
		-- Datapoints that are not assigned to one of your headings stay under
		-- their original TSM heading when true, and are dropped when false.
		showUnassigned = true,
		-- Ordered list of { name = "Heading", items = { id, id, ... } }
		-- or { spacer = true, items = {} } for a blank line between headings
		-- or { standalone = true, items = { id } } for one datapoint shown at heading level
		headings = {},
		-- Ordered list of datapoint ids that are never shown.
		hidden = {},
		-- Every datapoint seen on a tooltip so far: [id] = { section = "", label = "" }
		catalog = {},
		-- Custom display names: [id] = "New label"
		renames = {},
		-- Datapoints drawn in a muted gray, as secondary information: [id] = true
		muted = {},
	}
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff" .. ns.TITLE .. "|r: " .. tostring(msg))
end

-- ============================================================================
-- Assignment lookup (id -> where it goes), rebuilt whenever the layout changes
-- ============================================================================

local assignment = nil

function ns.InvalidateLayout()
	assignment = nil
	if ns.OnLayoutChanged then
		ns.OnLayoutChanged()
	end
end

---Returns a table mapping datapoint id -> heading index, or `true` for hidden.
function ns.GetAssignment()
	if assignment then
		return assignment
	end
	assignment = {}
	for _, id in ipairs(ns.db.hidden) do
		assignment[id] = true
	end
	for index, heading in ipairs(ns.db.headings) do
		for _, id in ipairs(heading.items) do
			if assignment[id] == nil then
				assignment[id] = index
			end
		end
	end
	return assignment
end

---Removes a datapoint id from every heading and from the hidden list.
function ns.Unassign(id)
	for i = #ns.db.hidden, 1, -1 do
		if ns.db.hidden[i] == id then
			tremove(ns.db.hidden, i)
		end
	end
	for index = #ns.db.headings, 1, -1 do
		local heading = ns.db.headings[index]
		for i = #heading.items, 1, -1 do
			if heading.items[i] == id then
				tremove(heading.items, i)
			end
		end
		if heading.standalone and #heading.items == 0 then
			tremove(ns.db.headings, index)
		end
	end
end

---Shows a datapoint at heading level, inserted at `index` in the headings list.
function ns.AddStandalone(id, index)
	ns.Unassign(id)
	index = min(max(index or (#ns.db.headings + 1), 1), #ns.db.headings + 1)
	tinsert(ns.db.headings, index, { standalone = true, items = { id } })
	ns.InvalidateLayout()
	return index
end

---Records a datapoint seen on a tooltip so it can be offered in the options panel.
function ns.LearnDatapoint(id, section, label)
	if ns.db.catalog[id] then
		return
	end
	ns.db.catalog[id] = { section = section, label = label }
	if ns.OnCatalogChanged then
		ns.OnCatalogChanged()
	end
end

---Returns the custom name for a datapoint, if it has one.
function ns.GetRename(id)
	return ns.db.renames[id]
end

---Sets (or, with nil / "", clears) the custom name for a datapoint.
function ns.SetRename(id, name)
	if name then
		name = strtrim(name)
	end
	ns.db.renames[id] = (name and name ~= "") and name or nil
	ns.InvalidateLayout()
end

---Returns whether a datapoint is shown muted.
function ns.IsMuted(id)
	return ns.db.muted[id] == true
end

---Shows a datapoint muted (gray) or normally.
function ns.SetMuted(id, muted)
	ns.db.muted[id] = muted and true or nil
	ns.InvalidateLayout()
end

---Resets headings, hidden datapoints and settings; keeps learned datapoints,
---renames and muted datapoints.
function ns.ResetAll()
	local catalog, renames, muted = ns.db.catalog, ns.db.renames, ns.db.muted
	TSMTooltipControlDB = NewDefaults()
	ns.db = TSMTooltipControlDB
	ns.db.catalog = catalog
	ns.db.renames = renames
	ns.db.muted = muted
	ns.InvalidateLayout()
end

-- ============================================================================
-- Loading
-- ============================================================================

local function LoadDB()
	if type(TSMTooltipControlDB) ~= "table" then
		TSMTooltipControlDB = NewDefaults()
	end
	local db = TSMTooltipControlDB
	for key, value in pairs(NewDefaults()) do
		if db[key] == nil then
			db[key] = value
		end
	end
	-- Drop malformed headings defensively
	for i = #db.headings, 1, -1 do
		local heading = db.headings[i]
		if type(heading) ~= "table" or (not heading.spacer and not heading.standalone and type(heading.name) ~= "string") then
			tremove(db.headings, i)
		elseif type(heading.items) ~= "table" then
			heading.items = {}
		end
	end
	db.version = DB_VERSION
	ns.db = db
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg)
	if event == "ADDON_LOADED" and arg == ADDON_NAME then
		LoadDB()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		-- TSM installs its tooltip hook during its own ADDON_LOADED / PLAYER_LOGIN
		-- handling, so wait one frame to be sure our "finish" hook lands after it.
		C_Timer.After(0, ns.InstallFinishHook)
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)

SLASH_TSMTOOLTIPCONTROL1 = "/ttc"
SLASH_TSMTOOLTIPCONTROL2 = "/tsmttc"
SlashCmdList.TSMTOOLTIPCONTROL = function(msg)
	msg = strlower(strtrim(msg or ""))
	if msg == "on" or msg == "off" then
		ns.db.enabled = msg == "on"
		ns.Print(ns.db.enabled and "enabled" or "disabled")
		ns.InvalidateLayout()
	else
		ns.OpenOptions()
	end
end
