local _, ns = ...

-- Reads TSM's own tooltip settings (TSM > Settings > Tooltip Settings) so the
-- options panel can leave out datapoints that are switched off there, while
-- keeping their place in your layout for when they're switched back on.
--
-- TSM keeps its settings in the TradeSkillMasterDB saved variable, keyed
-- "<scope>@<scope value>@<namespace>@<key>"; tooltip settings are global
-- ("g@ @tooltipOptions@..."). Each tooltip setting produces lines with a fixed
-- (English) label, which is how a datapoint is matched to its setting. See
-- TradeSkillMaster/LibTSMApp/Source/Tooltip/Internal/*.lua.
--
-- Anything that can't be matched, or a setting that can't be read, counts as
-- switched on: a datapoint is only left out when TSM clearly has it off.

local function Setting(key)
	local db = _G.TradeSkillMasterDB
	if type(db) ~= "table" then
		return nil
	end
	return db["g@ @tooltipOptions@" .. key]
end

local function SubSetting(key, subKey)
	local tbl = Setting(key)
	if type(tbl) ~= "table" then
		return nil
	end
	return tbl[subKey]
end

local function ModuleSetting(module, key)
	local tbl = SubSetting("moduleTooltips", module)
	if type(tbl) ~= "table" then
		return nil
	end
	return tbl[key]
end

---TSM settings are booleans or format strings, where "none" means off.
local function IsOn(value)
	return value ~= false and value ~= "none"
end

local function Module(module, key)
	return function()
		return ModuleSetting(module, key)
	end
end

local function General(key)
	return function()
		return Setting(key)
	end
end

local DESTROY_LABELS = {
	["Disenchant Value"] = true,
	["Mill Value"] = true,
	["Prospect Value"] = true,
	["Transform Value"] = true,
	["Vendor Trade Value"] = true,
}

-- [section] = list of { pattern, getter }, checked in order. A getter returns
-- TSM's setting value; it gets the pattern's captures.
local RULES = {
	["TSM AuctionDB"] = {
		{ "^Min Buyout$", Module("AuctionDB", "minBuyout") },
		{ "^Recent Value$", Module("AuctionDB", "marketValueRecent") },
		{ "^Market Value$", Module("AuctionDB", "marketValue") },
		{ "^Historical Price$", Module("AuctionDB", "historical") },
		{ "^Region Market Value Avg$", Module("AuctionDB", "regionMarketValue") },
		{ "^Region Historical Price$", Module("AuctionDB", "regionHistorical") },
		{ "^Region Sale Avg$", Module("AuctionDB", "regionSale") },
		{ "^Region Sale Rate$", Module("AuctionDB", "regionSalePercent") },
		{ "^Region Avg Daily Sold$", Module("AuctionDB", "regionSoldPerDay") },
		-- "<other realm> - Min Buyout" etc.
		{ "^.+ %- Min Buyout$", Module("AuctionDB", "altMinBuyout") },
		{ "^.+ %- Recent Value$", Module("AuctionDB", "altMarketValueRecent") },
		{ "^.+ %- Market Value$", Module("AuctionDB", "altMarketValue") },
		{ "^.+ %- Historical Price$", Module("AuctionDB", "altHistorical") },
	},
	["TSM Accounting"] = {
		{ "^Purchased", Module("Accounting", "purchase") },
		{ "^Smart Avg Buy Price$", Module("Accounting", "purchase") },
		{ "^Last Purchased$", Module("Accounting", "purchase") },
		{ "^Sold", Module("Accounting", "sale") },
		{ "^Last Sold$", Module("Accounting", "sale") },
		{ "^Sale Rate$", Module("Accounting", "saleRate") },
		{ "^Expired Since Last Sale$", Module("Accounting", "expiredAuctions") },
		{ "^Cancelled Since Last Sale$", Module("Accounting", "cancelledAuctions") },
	},
	["TSM Crafting"] = {
		{ "^Crafting Cost$", Module("Crafting", "craftingCost") },
		{ "^Material Cost$", Module("Crafting", "matPrice") },
		-- Anything else under TSM Crafting is a line of the detailed materials list
		{ ".", Module("Crafting", "detailedMats") },
	},
	["TSM Shopping"] = {
		{ ".", Module("Shopping", "maxPrice") },
	},
	["TSM Sniper"] = {
		{ ".", Module("Sniper", "belowPrice") },
	},
	["TSM Auctioning"] = {
		{ "^Post Quantity$", Module("Auctioning", "postQuantity") },
		{ "^Min/Normal/Max Prices$", Module("Auctioning", "operationPrices") },
	},
	["TSM General Info"] = {
		{ "^Vendor Buy Price$", General("vendorBuyTooltip") },
		{ "^Vendor Sell Price$", General("vendorSellTooltip") },
		{ "^Group$", General("groupNameTooltip") },
		{ "^Group %(", General("groupNameTooltip") },
		{ "^(.+) Operation%(s%)$", function(typeName) return SubSetting("operationTooltips", typeName) end },
		{ "^Custom Source %((.+)%)$", function(name) return SubSetting("customPriceTooltips", name) end },
		{ "^Convert Value", General("convertTooltipFormat") },
		{ "^Inventory$", General("inventoryTooltipFormat") },
		{ "^(.+)$", function(label)
			if DESTROY_LABELS[label] then
				return Setting("destroyTooltipFormat")
			end
		end },
	},
	-- The detailed inventory format lists characters under its own heading
	["Inventory"] = {
		{ ".", General("inventoryTooltipFormat") },
	},
}

---Returns false when the datapoint is switched off in TSM's tooltip settings.
function ns.IsDatapointActive(id)
	local entry = ns.db.catalog[id]
	local section, label
	if entry then
		section, label = entry.section, entry.label
	else
		section, label = strmatch(id, "^(.-)" .. ns.ID_SEP .. "(.*)$")
	end
	local rules = section and label and RULES[section]
	if not rules then
		return true
	end
	for _, rule in ipairs(rules) do
		local captures = { strmatch(label, rule[1]) }
		if captures[1] then
			return IsOn(rule[2](unpack(captures)))
		end
	end
	return true
end
