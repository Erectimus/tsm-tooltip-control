local _, ns = ...

-- How this works
-- --------------
-- TSM adds its lines from a TooltipDataProcessor post-call (TooltipWrapper.lua),
-- using tooltip:AddLine / tooltip:AddDoubleLine. Post-calls run in the order
-- they were registered, so we register two of our own around TSM's:
--
--   Begin  (registered at file load, before TSM loads)  -> start buffering
--   TSM    (registered during TSM's load)                -> lines go to buffer
--   Finish (registered one frame after PLAYER_LOGIN)     -> rewrite + flush
--
-- Buffering is done by temporarily shadowing AddLine/AddDoubleLine on the
-- tooltip frame itself; the shadow is removed again in Finish (and, as a
-- safety net, whenever the tooltip is cleared or hidden). Because nothing has
-- been written to the real tooltip yet, we can output fewer or more lines than
-- TSM produced without leaving gaps.
--
-- If the load order is wrong (TSM's hook registered before ours), TSM's lines
-- are already on the tooltip when Begin runs. We detect that and fall back to
-- rewriting the existing tooltip lines in place.

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip" }

local states = {}
local warnedOrder = false
local warnedError = false

local function Restore(tooltip)
	local state = states[tooltip]
	if not state or not state.capturing then
		return
	end
	state.capturing = false
	tooltip.AddLine = nil
	tooltip.AddDoubleLine = nil
end

local function ReportError(err)
	if not warnedError then
		warnedError = true
		ns.Print("error while rearranging the tooltip, showing TSM's original layout. " .. tostring(err))
	end
end

-- ============================================================================
-- Fallback: read / rewrite the lines already on the tooltip
-- ============================================================================

local function ReadLines(tooltip, first)
	local name = tooltip:GetName()
	local lines = {}
	for i = first, tooltip:NumLines() do
		local left = _G[name .. "TextLeft" .. i]
		local right = _G[name .. "TextRight" .. i]
		local line = { left = left and left:GetText() or "" }
		if left then
			line.lr, line.lg, line.lb = left:GetTextColor()
		end
		if right and right:IsShown() and right:GetText() then
			line.double = true
			line.right = right:GetText()
			line.rr, line.rg, line.rb = right:GetTextColor()
		end
		tinsert(lines, line)
	end
	return lines
end

local function RewriteInPlace(tooltip)
	local lines = ReadLines(tooltip, 1)
	local out, changed = ns.Layout.Process(lines)
	if not changed then
		return
	end
	local name = tooltip:GetName()
	local total = tooltip:NumLines()
	-- Only lines from the first difference on need touching
	for i = 1, total do
		local left = _G[name .. "TextLeft" .. i]
		local right = _G[name .. "TextRight" .. i]
		local line = out[i]
		if line ~= lines[i] and left and right then
			if line then
				left:SetText(line.left)
				if line.lr then
					left:SetTextColor(line.lr, line.lg, line.lb)
				end
				if line.double then
					right:SetText(line.right)
					if line.rr then
						right:SetTextColor(line.rr, line.rg, line.rb)
					end
					right:Show()
				else
					right:SetText(nil)
					right:Hide()
				end
			else
				-- GameTooltip can't remove lines; blank out the leftovers
				left:SetText(nil)
				right:SetText(nil)
				right:Hide()
			end
		end
	end
	-- If the new layout is longer (shouldn't normally happen), append the rest
	for i = total + 1, #out do
		local line = out[i]
		if line.double then
			tooltip:AddDoubleLine(line.left, line.right, line.lr, line.lg, line.lb, line.rr, line.rg, line.rb)
		else
			tooltip:AddLine(line.left, line.lr, line.lg, line.lb, line.wrap)
		end
	end
	tooltip:Show()
end

-- ============================================================================
-- Hooks
-- ============================================================================

local function Begin(tooltip)
	local state = states[tooltip]
	if not state or not ns.db or not ns.db.enabled or not ns.finishInstalled then
		return
	end
	if state.capturing then
		-- A previous capture never finished; flush nothing and start over
		Restore(tooltip)
	end
	if rawget(tooltip, "AddLine") or rawget(tooltip, "AddDoubleLine") then
		-- Someone else has replaced these methods; don't stack on top of them
		return
	end
	state.addLine = tooltip.AddLine
	state.addDoubleLine = tooltip.AddDoubleLine
	wipe(state.buffer)
	state.capturing = true
	tooltip.AddLine = state.captureLine
	tooltip.AddDoubleLine = state.captureDoubleLine
end

local function Finish(tooltip)
	local state = states[tooltip]
	if not state then
		return
	end
	if not state.capturing then
		return
	end
	Restore(tooltip)

	local buffer = state.buffer
	if #buffer == 0 then
		-- Nothing was written through us. If TSM's lines are on the tooltip anyway,
		-- TSM's hook ran before Begin (load order problem): fix them up in place.
		if ns.Layout.FindBlock(ReadLines(tooltip, 1)) then
			if not warnedOrder then
				warnedOrder = true
				ns.Print("loaded after TradeSkillMaster, so tooltips are rewritten in place (may leave small gaps). "
					.. "Make sure the addon folder is named '!TSMTooltipControl'.")
			end
			local ok, err = pcall(RewriteInPlace, tooltip)
			if not ok then
				ReportError(err)
			end
		end
		return
	end

	local ok, out = pcall(ns.Layout.Process, buffer)
	if not ok then
		ReportError(out)
		out = buffer
	end
	for _, line in ipairs(out) do
		if line.double then
			state.addDoubleLine(tooltip, line.left, line.right, line.lr, line.lg, line.lb, line.rr, line.rg, line.rb)
		else
			state.addLine(tooltip, line.left, line.lr, line.lg, line.lb, line.wrap)
		end
	end
	wipe(buffer)
	tooltip:Show()
end

local function SetupTooltip(tooltip)
	local state = { buffer = {}, capturing = false }
	state.captureLine = function(_, text, r, g, b, wrap)
		tinsert(state.buffer, { double = false, left = text, lr = r, lg = g, lb = b, wrap = wrap })
	end
	state.captureDoubleLine = function(_, leftText, rightText, lr, lg, lb, rr, rg, rb)
		tinsert(state.buffer, {
			double = true, left = leftText, right = rightText,
			lr = lr, lg = lg, lb = lb, rr = rr, rg = rg, rb = rb,
		})
	end
	states[tooltip] = state
	tooltip:HookScript("OnTooltipCleared", Restore)
	tooltip:HookScript("OnHide", Restore)
end

for _, name in ipairs(TOOLTIPS) do
	local tooltip = _G[name]
	if tooltip then
		SetupTooltip(tooltip)
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Begin)
end

function ns.InstallFinishHook()
	if ns.finishInstalled then
		return
	end
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then
		ns.Print("this client has no TooltipDataProcessor; tooltips will not be changed.")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Finish)
	ns.finishInstalled = true
end
