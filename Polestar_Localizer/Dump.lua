-- Polestar_Localizer/Dump.lua
-- Exports the client's own localised names for every id Polestar can display.
--
--   /pstar dump      run every pass (quests, items, maps, taxi, objects)
--   /pstar item      retry the item pass (item names arrive asynchronously)
--   /pstar status    what has been collected so far
--   /pstar wipe      clear the collected data
--
-- Results land in PolestarLocalizerDB, so after logging out the file to send is
--   WTF/Account/<account>/SavedVariables/Polestar_Localizer.lua
--
-- Everything is guarded: a client without an API simply collects less.

local ADDON = "Polestar_Localizer"

local db
local function DB()
	if type(PolestarLocalizerDB) ~= "table" then PolestarLocalizerDB = {} end
	db = PolestarLocalizerDB
	db.quests = db.quests or {}
	db.items = db.items or {}
	db.maps = db.maps or {}
	db.taxi = db.taxi or {}
	db.objects = db.objects or {}
	db.missing = db.missing or {}
	db.progress = db.progress or {}
	return db
end

local function out(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Polestar Localizer|r " .. tostring(msg))
end

local function countTable(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- Kept as locals so a missing global is nil instead of an error.
local C_QuestLog, C_Item, C_Map, C_TaxiMap = C_QuestLog, C_Item, C_Map, C_TaxiMap
local GetItemInfo, GetLocale, GetBuildInfo = GetItemInfo, GetLocale, GetBuildInfo

local function questTitle(id)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local t = C_QuestLog.GetTitleForQuestID(id)
		if t and t ~= "" then return t end
	end
	if C_QuestLog and C_QuestLog.GetInfo then
		for i = 1, (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0) do
			local info = C_QuestLog.GetInfo(i)
			if info and info.questID == id and info.title then return info.title end
		end
	end
	return nil
end

local function questObjectives(id)
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local list = C_QuestLog.GetQuestObjectives(id)
		if type(list) == "table" and #list > 0 then
			local texts = {}
			for i = 1, math.min(#list, 12) do
				local row = list[i]
				local t = row and row.text
				if t and t ~= "" then
					local kind = row.type or row.objectiveType or ""
					texts[#texts + 1] = (kind ~= "" and (kind .. "|") or "") .. t
				end
			end
			if #texts > 0 then return texts end
		end
	end
	return nil
end

local function itemName(id)
	local name
	if C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(id)
	elseif GetItemInfo then name = GetItemInfo(id) end
	if name and name ~= "" then return name end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return nil
end

local function mapInfo(id)
	if not (C_Map and C_Map.GetMapInfo) then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, id)
	if not ok or type(info) ~= "table" or not info.name or info.name == "" then return nil end
	return info.name, info.parentMapID, info.mapType
end

-- A chunked walker: step() returns true while it has more to do.
local function walker(label, list, step, done)
	local i = 1
	local total = #list
	local function tick()
		local stop = i + 250
		while i <= stop and i <= total do
			local ok, err = pcall(step, list[i], i)
			if not ok then
				db.errors = (db.errors or 0) + 1
				if db.errors <= 3 then out("|cffff5555" .. label .. " error on id " .. tostring(list[i]) .. ": " .. tostring(err)) end
			end
			i = i + 1
		end
		if i <= total then return true end
		if done then done() end
		return false
	end
	return tick
end

local stepFn            -- the current pass's step closure, or nil when idle
local queue = {}

local function pump()
	if not stepFn then return end
	if stepFn() then
		C_Timer.After(0, pump)      -- more work in this pass: come back next frame
		return
	end
	stepFn = nil
	local nextPass = table.remove(queue, 1)
	if nextPass then
		stepFn = nextPass()
		if stepFn then C_Timer.After(0, pump) end
	else
		db.doneAt = time and time() or 0
		out("|cff55ff55done|r - quests " .. countTable(db.quests)
			.. ", items " .. countTable(db.items) .. ", maps " .. countTable(db.maps)
			.. ", taxi " .. #(db.taxi or {}) .. ", npcs " .. countTable(db.npcs) .. ", object ids " .. countTable(db.objects))
		out("log out, then send: WTF/Account/<account>/SavedVariables/Polestar_Localizer.lua")
	end
end

local function begin()
	if stepFn then return end
	local first = table.remove(queue, 1)
	if first then
		stepFn = first()
		if stepFn then C_Timer.After(0, pump) end
	end
end

local function passQuests()
	local ids = PolestarLocalizer_Ids and PolestarLocalizer_Ids.quests or {}
	local n = 0
	return walker("quests", ids, function(id)
		local title = questTitle(id)
		if title then
			db.quests[id] = title
			n = n + 1
			local objs = questObjectives(id)
			if objs then db.objectives = db.objectives or {}; db.objectives[id] = objs end
		end
		db.progress.quests = n
	end, function() out("quests: " .. n .. " / " .. #ids) end)
end

local function passItems()
	local ids = PolestarLocalizer_Ids and PolestarLocalizer_Ids.items or {}
	local n, miss = 0, {}
	return walker("items", ids, function(id)
		local name = itemName(id)
		if name then db.items[id] = name; n = n + 1 else miss[#miss + 1] = id end
		db.itemCount = n
		db.missing.items = miss
	end, function() out("items: " .. n .. " / " .. #ids .. (n < #ids and (" (retry with /pstar item)") or "")) end)
end

local function passMaps()
	local n = 0
	local i = 0
	local last = 2600
	return function()
		local stop = i + 200
		while i < stop and i < last do
			i = i + 1
			local name, parent, kind = mapInfo(i)
			if name then db.maps[i] = { name, parent, kind }; n = n + 1 end
		end
		db.mapCount = n
		if i < last then return true end
		out("maps: " .. n .. " named maps found (ids 1-" .. last .. ")")
		return false
	end
end

local function passTaxi()
	local ids = { 1411, 1412, 1413, 1414, 1415, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429,
		1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446,
		1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464 }
	local i, n = 0, 0
	return function()
		local stop = i + 8
		while i < stop and i < #ids do
			i = i + 1
			local mapID = ids[i]
			if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
				local okTaxi, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
				if not okTaxi then nodes = nil end
				if type(nodes) == "table" then
					for k = 1, #nodes do
						local node = nodes[k]
						local name = node and (node.name or node.nodeName)
						if name then
							db.taxi[#db.taxi + 1] = { name, node.nodeID or node.slot or k, mapID }
							n = n + 1
						end
					end
				end
			end
			db.taxiCount = n
		end
		if i < #ids then return true end
		out("taxi: " .. n .. " nodes")
		return false
	end
end

-- npc names: the client has no "npc id -> name" API, so try the two routes that
-- do exist before falling back to the quest objective text offline.
local function creatureLinkName(id)
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local ok, info = pcall(C_TooltipInfo.GetHyperlink, "unit:Creature-0-0-0-0-" .. id .. "-00000000")
		if ok and type(info) == "table" and type(info.lines) == "table" then
			for i = 1, #info.lines do
				local line = info.lines[i]
				local txt = line and line.leftText
				if type(txt) == "string" and txt ~= "" then return txt end
			end
		end
	end
	local get = (C_CreatureInfo and C_CreatureInfo.GetCreatureInfo) or GetCreatureInfo
	if get then
		local ok, a = pcall(get, id)
		if ok then
			if type(a) == "table" and type(a.name) == "string" then return a.name end
			if type(a) == "string" then return a end
		end
	end
	return nil
end

local function passNpcs()
	local ids = PolestarLocalizer_Ids and PolestarLocalizer_Ids.npcs or {}
	local n = 0
	db.npcs = db.npcs or {}
	return walker("npcs", ids, function(id)
		if db.npcs[id] then n = n + 1; return end
		local name = creatureLinkName(id)
		if name then db.npcs[id] = name; n = n + 1 end
		db.npcCount = n
	end, function() out("npcs: " .. n .. " / " .. #ids .. " named by the client") end)
end

local function passObjects()
	local ids = PolestarLocalizer_Ids and PolestarLocalizer_Ids.objects or {}
	local n = 0
	return walker("objects", ids, function(id)
		-- There is no id->name API for game objects; the map pins carry the name at
		-- runtime, so this pass only records which ids were asked for.
		db.objects[id] = db.objects[id] or false
		n = n + 1
	end, function() out("objects: " .. n .. " ids noted (no client API for object names)") end)
end

local function start(which)
	DB()
	db.locale = GetLocale and GetLocale() or "?"
	db.build = GetBuildInfo and select(1, GetBuildInfo()) or "?"
	db.startedAt = time and time() or 0
	db.errors = 0
	queue = {}
	if which == "item" then
		queue = { passItems }
	else
		queue = { passQuests, passItems, passMaps, passTaxi, passNpcs, passObjects }
	end
	out("started (" .. (db.locale or "?") .. ") - this takes a few seconds")
	begin()
end

local function status()
	DB()
	local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
	out("locale " .. tostring(db.locale) .. ", build " .. tostring(db.build))
	out("quests " .. count(db.quests) .. ", items " .. count(db.items)
		.. ", maps " .. count(db.maps) .. ", taxi " .. #(db.taxi or {})
		.. ", object ids " .. count(db.objects))
	if db.doneAt and db.doneAt > 0 then out("last full run finished at " .. date("%Y-%m-%d %H:%M", db.doneAt)) end
end

SLASH_POLESTARLOC1 = "/pstar"
SLASH_POLESTARLOC2 = "/polestarloc"
SlashCmdList.POLESTARLOC = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "dump" or msg == "" then start("all")
	elseif msg == "item" then start("item")
	elseif msg == "status" then status()
	elseif msg == "wipe" then PolestarLocalizerDB = nil; DB(); out("cleared")
	else out("commands: /pstar dump | item | status | wipe") end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, event, id)
	if event == "PLAYER_LOGIN" then
		DB()
		out("loaded. Type |cffffd100/pstar dump|r to export every name, then /pstar status.")
	elseif event == "GET_ITEM_INFO_RECEIVED" and db and db.items then
		-- Item names arrive asynchronously. Once the client has had a moment, retry the
		-- stragglers automatically (bounded: one retry per request).
		local ids = PolestarLocalizer_Ids and PolestarLocalizer_Ids.items
		if ids and not db.pendingPass and countTable(db.items) < #ids then
			db.pendingPass = true
			C_Timer.After(20, function()
				db.pendingPass = nil
				if not stepFn and countTable(db.items) < #ids then
					queue = { passItems }
					begin()
				end
			end)
		end
	end
end)
