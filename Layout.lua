local _, ns = ...

-- Turns the lines TSM writes into a tooltip into sections/datapoints, and
-- rebuilds them according to the user's headings.
--
-- A "line" is a table:
--   { double = bool, left = text, right = text,
--     lr, lg, lb, rr, rg, rb  -- colors (may be nil)
--     wrap = bool }           -- AddLine only
--
-- TSM's layout (TradeSkillMaster v4.15, LibTSMService TooltipBuilder):
--   " "                                  blank separator line
--   "|cffRRGGBBTSM AuctionDB|r" [right]  level 0 section heading (accent color)
--   "  Min Buyout"  <money>              level 1: one datapoint
--   "    <material> x2"  <money>         level 2+: belongs to the datapoint above

local Layout = {}
ns.Layout = Layout

local HEADING_PATTERN = "^(|c%x%x%x%x%x%x%x%x).+|r$"

local function StripCodes(text)
	text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = gsub(text, "|r", "")
	text = gsub(text, "|T.-|t", "")
	text = gsub(text, "|A.-|a", "")
	return text
end

local function IsHeading(line)
	local text = line.left
	return type(text) == "string" and strsub(text, 1, 1) ~= " " and strmatch(text, HEADING_PATTERN) ~= nil
end

local function IsIndented(line)
	local text = line.left
	return type(text) == "string" and strsub(text, 1, 2) == "  "
end

local function IsDeeper(line)
	return strsub(line.left, 1, 4) == "    "
end

---Normalizes a datapoint's left text into a stable label.
local function ToLabel(text)
	text = strtrim(StripCodes(text))
	-- TSM appends " x<stack size>" when shift is held
	text = gsub(text, " x%d+$", "")
	return text
end
Layout.ToLabel = ToLabel

---Finds the TSM block within a list of lines.
---@return number? first index of the first TSM heading
---@return number? last index of the last TSM line
function Layout.FindBlock(lines)
	for i = 1, #lines - 1 do
		local line = lines[i]
		local nextLine = lines[i + 1]
		-- Every TSM section heading starts with "TSM" (e.g. "TSM General Info"),
		-- which keeps Blizzard lines such as item set names from matching.
		if not line.double and line.left == " " and IsHeading(nextLine)
			and strfind(StripCodes(nextLine.left), "^TSM") then
			local last = i + 1
			while lines[last + 1] and (IsHeading(lines[last + 1]) or IsIndented(lines[last + 1])) do
				last = last + 1
			end
			return i + 1, last
		end
	end
	return nil, nil
end

---Label for the datapoint made from a section heading's right-hand text
---(e.g. AuctionDB's "5 auctions (2 min ago)").
local function HeadingInfoLabel(sectionTitle)
	return strfind(sectionTitle, "AuctionDB") and "Auctions" or "Heading info"
end

---Turns a heading's right-hand text into a datapoint of its own.
local function NewHeadingInfoPoint(section, headingLine)
	local label = HeadingInfoLabel(section.title)
	return {
		id = section.title .. ns.ID_SEP .. label,
		section = section.title,
		label = label,
		isHeadingInfo = true,
		lines = { {
			double = true,
			left = "  " .. label,
			right = headingLine.right,
			lr = headingLine.lr, lg = headingLine.lg, lb = headingLine.lb,
			rr = headingLine.rr, rg = headingLine.rg, rb = headingLine.rb,
		} },
	}
end

---Parses the TSM block into sections and datapoints.
function Layout.Parse(lines, first, last)
	local sections = {}
	local section, point = nil, nil
	for i = first, last do
		local line = lines[i]
		if IsHeading(line) then
			section = {
				title = strtrim(StripCodes(line.left)),
				line = line,
				accent = strmatch(line.left, HEADING_PATTERN),
				points = {},
			}
			if line.double and line.right and line.right ~= "" then
				section.info = NewHeadingInfoPoint(section, line)
			end
			tinsert(sections, section)
			point = nil
		elseif section then
			if point and IsDeeper(line) then
				tinsert(point.lines, line)
			else
				local label = ToLabel(line.left)
				point = {
					id = section.title .. ns.ID_SEP .. label,
					section = section.title,
					label = label,
					lines = { line },
				}
				tinsert(section.points, point)
			end
		end
	end
	return sections
end

local function AppendAll(out, lines)
	for _, line in ipairs(lines) do
		tinsert(out, line)
	end
end

---Returns a copy of a datapoint's first line with its label replaced, keeping
---the indentation, a leading color code and TSM's " x<stack>" suffix.
local function RenameLine(line, newLabel)
	local text = line.left
	local indent, rest = strmatch(text, "^(%s*)(.*)$")
	local color = strmatch(rest, "^(|c%x%x%x%x%x%x%x%x)")
	local quantity = strmatch(StripCodes(rest), " (x%d+)%s*$")
	local left = indent .. (color or "") .. newLabel .. (color and "|r" or "") .. (quantity and (" " .. quantity) or "")
	local copy = {}
	for k, v in pairs(line) do
		copy[k] = v
	end
	copy.left = left
	return copy
end
Layout.RenameLine = RenameLine

local MUTED_R, MUTED_G, MUTED_B = 0.5, 0.5, 0.5

---Removes color codes but keeps textures (e.g. coin icons).
local function StripColors(text)
	text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = gsub(text, "|r", "")
	return text
end

---Returns a copy of a line drawn in muted gray. TSM colors values, material
---names and ranges with inline codes, so those are removed and the whole line
---takes the muted color instead.
local function MuteLine(line)
	local copy = {}
	for k, v in pairs(line) do
		copy[k] = v
	end
	copy.left = StripColors(line.left)
	copy.lr, copy.lg, copy.lb = MUTED_R, MUTED_G, MUTED_B
	if line.double then
		copy.right = StripColors(line.right or "")
		copy.rr, copy.rg, copy.rb = MUTED_R, MUTED_G, MUTED_B
	end
	return copy
end
Layout.MuteLine = MuteLine

---Appends a datapoint's lines, applying the user's custom name and muting if any.
local function AppendPoint(out, point)
	local rename = ns.GetRename(point.id)
	local muted = ns.IsMuted(point.id)
	for i, line in ipairs(point.lines) do
		if i == 1 and rename then
			line = RenameLine(line, rename)
		end
		if muted then
			line = MuteLine(line)
		end
		tinsert(out, line)
	end
end

---Appends a datapoint at heading level: no indent and the label in the heading
---color. Lines below it (e.g. materials) move up one level with it.
local function AppendPromoted(out, point, accent)
	local muted = ns.IsMuted(point.id)
	for i, line in ipairs(point.lines) do
		local copy = {}
		for k, v in pairs(line) do
			copy[k] = v
		end
		if i == 1 then
			local quantity = strmatch(StripCodes(line.left), " (x%d+)%s*$")
			local name = ns.GetRename(point.id) or point.label
			copy.left = (accent or "|cffffd100") .. name .. (quantity and (" " .. quantity) or "") .. "|r"
		else
			copy.left = gsub(line.left, "^  ", "", 1)
		end
		if muted then
			copy = MuteLine(copy)
		end
		tinsert(out, copy)
	end
end

---Builds the replacement lines for the TSM block.
local function BuildBlock(sections)
	local db = ns.db
	local assignment = ns.GetAssignment()
	local byId = {}
	local accent, template = nil, nil

	for _, section in ipairs(sections) do
		accent = accent or section.accent
		template = template or section.line
		section.remaining = {}
		section.headingLine = section.line
		local info = section.info
		if info then
			ns.LearnDatapoint(info.id, info.section, info.label)
			local target = assignment[info.id]
			if target ~= nil then
				-- Moved or hidden: take the text off TSM's heading line
				section.headingLine = { double = false, left = section.line.left,
					lr = section.line.lr, lg = section.line.lg, lb = section.line.lb }
				if target ~= true then
					byId[info.id] = info
				end
			elseif ns.IsMuted(info.id) then
				-- Still on TSM's heading line: mute just the right-hand text
				section.headingLine = { double = true, left = section.line.left, right = StripColors(section.line.right),
					lr = section.line.lr, lg = section.line.lg, lb = section.line.lb,
					rr = MUTED_R, rg = MUTED_G, rb = MUTED_B }
			end
		end
		for _, point in ipairs(section.points) do
			ns.LearnDatapoint(point.id, point.section, point.label)
			local target = assignment[point.id]
			if target == nil then
				tinsert(section.remaining, point)
			elseif target ~= true then
				byId[point.id] = point
			end
		end
	end

	local out = {}
	-- Spacers only turn into a blank line once more content follows, so leading,
	-- trailing and back-to-back spacers (e.g. around an empty heading) collapse.
	local pendingSpacer = false
	local function EmitSpacer()
		if pendingSpacer then
			pendingSpacer = false
			tinsert(out, { double = false, left = " " })
		end
	end

	for _, heading in ipairs(db.headings) do
		local headingLine = nil
		if heading.spacer then
			pendingSpacer = #out > 0
		elseif heading.standalone then
			local point = byId[heading.items[1]]
			if point then
				EmitSpacer()
				AppendPromoted(out, point, accent)
			end
		end
		for _, id in ipairs((heading.spacer or heading.standalone) and {} or heading.items) do
			local point = byId[id]
			if point then
				if not headingLine then
					EmitSpacer()
					headingLine = {
						double = false,
						left = (accent or "|cffffd100") .. heading.name .. "|r",
						lr = template and template.lr, lg = template and template.lg, lb = template and template.lb,
					}
					tinsert(out, headingLine)
				end
				AppendPoint(out, point)
			end
		end
	end

	if db.showUnassigned then
		for _, section in ipairs(sections) do
			if #section.remaining > 0 then
				EmitSpacer()
				tinsert(out, section.headingLine)
				for _, point in ipairs(section.remaining) do
					AppendPoint(out, point)
				end
			end
		end
	end

	return out
end

---Takes every line written between our capture hooks and returns the lines
---that should actually be written, in order.
---@return table lines
---@return boolean changed Whether a TSM block was found
function Layout.Process(lines)
	local first, last = Layout.FindBlock(lines)
	if not first then
		return lines, false
	end
	local sections = Layout.Parse(lines, first, last)
	local block = BuildBlock(sections)

	local out = {}
	for i = 1, first - 1 do
		tinsert(out, lines[i])
	end
	if #block == 0 then
		-- Everything was hidden: drop TSM's blank separator line too
		if out[#out] and out[#out].left == " " and not out[#out].double then
			tremove(out)
		end
	else
		AppendAll(out, block)
	end
	for i = last + 1, #lines do
		tinsert(out, lines[i])
	end
	return out, true
end
