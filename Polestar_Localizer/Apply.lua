-- Polestar_Localizer/Apply.lua
-- Feeds Locale.lua into Polestar.L and localizes all registered Polestar_Guides
-- headers, steps, goals, prose notes, Dungeons, and Codex entries in-place for zhCN and zhTW.

local LOCALE = (GetLocale and GetLocale()) or "zhCN"
local IS_TW = (LOCALE == "zhTW")
if LOCALE ~= "zhCN" and LOCALE ~= "zhTW" then
    return
end

local localeTable = IS_TW and PolestarLocale_zhTW or PolestarLocale_zhCN
local steptitles  = (IS_TW and PolestarLocale_steptitlesTW) or PolestarLocale_steptitles or {}
local notes       = (IS_TW and PolestarLocale_notes_zhTW) or PolestarLocale_notes_zhCN or {}
local NameDB      = PolestarLocalizer_Names and (PolestarLocalizer_Names[LOCALE] or PolestarLocalizer_Names.zhCN) or {}

local zones     = NameDB.zones     or {}
local zonenames = NameDB.zonenames or {}
local places    = NameDB.places    or {}
local npcnames  = NameDB.npcnames  or {}
local itemnames = NameDB.itemnames or {}
local quests    = NameDB.quests    or {}
local items     = NameDB.items     or {}
local npcs      = NameDB.npcs      or {}
local objects   = NameDB.objects   or {}

-- Live client fallbacks for any IDs not in the static table
local function getQuestTitle(qid)
    if not qid then return nil end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local t = C_QuestLog.GetTitleForQuestID(qid)
        if t and t ~= "" then return t end
    end
    return nil
end

local function getItemName(itemId)
    if not itemId then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemId)
        if n and n ~= "" then return n end
    end
    if GetItemInfo then
        local n = GetItemInfo(itemId)
        if n and n ~= "" then return n end
    end
    return nil
end

local function getSpellName(spellId)
    if not spellId then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local n = C_Spell.GetSpellName(spellId)
        if n and n ~= "" then return n end
    end
    if GetSpellInfo then
        local n = GetSpellInfo(spellId)
        if n and n ~= "" then return n end
    end
    return nil
end

local function getFactionName(factionId)
    if not factionId or not GetFactionInfoByID then return nil end
    local n = GetFactionInfoByID(factionId)
    if n and n ~= "" then return n end
    return nil
end

-- Atomic lookup across all string-keyed dictionaries
local function lookupAtom(s)
    if not s or s == "" then return nil end
    return steptitles[s]
        or places[s]
        or zonenames[s]
        or npcnames[s]
        or itemnames[s]
        or notes[s]
        or (localeTable and localeTable[s])
end

-- Word-boundary substring fallback when a known entity name covers >= 50% of a title
local function isWordByte(b)
    if not b then return false end
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 39
end

local NAME_MAPS = { places, zonenames, npcnames, itemnames }
local function nameInside(text)
    if not text or #text < 4 then return nil end
    local best, bStart, bEnd, bLen = nil, nil, nil, 0
    local tLen = #text
    for _, dict in ipairs(NAME_MAPS) do
        for en, zh in pairs(dict) do
            local eLen = #en
            if eLen >= 4 and eLen * 2 >= tLen and eLen > bLen then
                local i = text:find(en, 1, true)
                while i do
                    local before = i > 1 and text:byte(i - 1) or nil
                    local after  = (i + eLen <= tLen) and text:byte(i + eLen) or nil
                    if not isWordByte(before) and not isWordByte(after) then
                        best, bStart, bEnd, bLen = zh, i, i + eLen - 1, eLen
                        break
                    end
                    i = text:find(en, i + 1, true)
                end
            end
        end
    end
    if best then
        return text:sub(1, bStart - 1) .. best .. text:sub(bEnd + 1)
    end
    return nil
end

-- Split compound strings by a delimiter (e.g., " / " or ", ") and translate each piece
local function resolveCompound(raw, sep, outSep)
    if not raw or not raw:find(sep, 1, true) then return nil end
    local parts = {}
    local pos = 1
    local changed = false
    while true do
        local s, e = raw:find(sep, pos, true)
        local token = s and raw:sub(pos, s - 1) or raw:sub(pos)
        local trimmed = token:match("^%s*(.-)%s*$")
        local zh = lookupAtom(trimmed)
        if not zh then
            local base, paren = trimmed:match("^(.-)%s*%((.-)%)$")
            if base then
                local zb = lookupAtom(base)
                local zp = lookupAtom(paren)
                if zb or zp then
                    zh = (zb or base) .. " (" .. (zp or paren) .. ")"
                end
            end
        end
        if zh then
            parts[#parts + 1] = zh
            changed = true
        else
            parts[#parts + 1] = trimmed
        end
        if not s then break end
        pos = e + 1
    end
    if changed then
        return table.concat(parts, outSep or sep)
    end
    return nil
end

-- Resolve a guide title, step title, explore subzone, waypoint label, or note
local function resolveTitle(raw)
    if not raw or raw == "" then return nil end
    local direct = lookupAtom(raw)
    if direct then return direct end

    local head, tail = raw:match("^(.-)%s*\226\128\148%s*(.+)$")
    if head then
        local zhHead = lookupAtom(head) or resolveCompound(head, " / ", " / ") or resolveCompound(head, ", ", "、")
        local zhTail = lookupAtom(tail) or resolveCompound(tail, " / ", " / ") or resolveCompound(tail, ", ", "、")
        if zhHead or zhTail then
            return (zhHead or head) .. " — " .. (zhTail or tail)
        end
    end

    local pfx, rest = raw:match("^(.-):%s*(.+)$")
    if pfx then
        local zhPfx  = lookupAtom(pfx)
        local zhRest = lookupAtom(rest) or resolveCompound(rest, " / ", " / ") or resolveCompound(rest, ", ", "、")
        if zhPfx or zhRest then
            return (zhPfx or pfx) .. "：" .. (zhRest or rest)
        end
    end

    local base, paren = raw:match("^(.-)%s*%((.-)%)$")
    if base then
        local zhBase  = lookupAtom(base) or resolveCompound(base, " / ", " / ") or resolveCompound(base, ", ", "、")
        local zhParen = lookupAtom(paren) or resolveCompound(paren, " / ", " / ") or resolveCompound(paren, ", ", "、")
        if zhBase or zhParen then
            return (zhBase or base) .. " (" .. (zhParen or paren) .. ")"
        end
    end

    local slash = resolveCompound(raw, " / ", " / ")
    if slash then return slash end
    local comma = resolveCompound(raw, ", ", "、")
    if comma then return comma end

    return nameInside(raw)
end

local function localizeGoal(goal)
    if not goal then return end

    if goal.quest then
        local qzh = quests[goal.quest] or getQuestTitle(goal.quest) or (goal.title and resolveTitle(goal.title))
        if qzh then goal.title = qzh end
    elseif goal.title then
        local tzh = resolveTitle(goal.title)
        if tzh then goal.title = tzh end
    end

    if goal.npc or goal.npcName then
        local nzh = (goal.npc and npcs[goal.npc])
            or (goal.npcName and (npcnames[goal.npcName] or resolveTitle(goal.npcName)))
        if nzh then goal.npcName = nzh end
    end

    if goal.item or goal.itemName then
        local izh = (goal.item and (items[goal.item] or getItemName(goal.item)))
            or (goal.itemName and (itemnames[goal.itemName] or resolveTitle(goal.itemName)))
        if izh then goal.itemName = izh end
    end

    if goal.object or goal.objName then
        local ozh = (goal.object and objects[goal.object])
            or (goal.objName and (places[goal.objName] or resolveTitle(goal.objName)))
        if ozh then goal.objName = ozh end
    end

    if goal.location then
        local lzh = places[goal.location] or zonenames[goal.location] or resolveTitle(goal.location)
        if lzh then goal.location = lzh end
    end

    if goal.target then
        local kzh = npcnames[goal.target] or places[goal.target] or itemnames[goal.target] or resolveTitle(goal.target)
        if kzh then goal.target = kzh end
    end

    if goal.from then
        local fzh = npcnames[goal.from] or places[goal.from] or itemnames[goal.from] or zonenames[goal.from] or resolveTitle(goal.from)
        if fzh then goal.from = fzh end
    end

    if goal.skill then
        local szh = places[goal.skill] or lookupAtom(goal.skill) or resolveTitle(goal.skill)
        if szh then goal.skill = szh end
    end

    if goal.spellName or goal.spell then
        local spzh = (goal.spellName and (itemnames[goal.spellName] or places[goal.spellName]))
            or (goal.spell and getSpellName(goal.spell))
            or (goal.spellName and resolveTitle(goal.spellName))
        if spzh then goal.spellName = spzh end
    end

    if goal.factionName or goal.faction then
        local fczh = (goal.factionName and (places[goal.factionName] or zonenames[goal.factionName]))
            or (goal.faction and getFactionName(goal.faction))
            or (goal.factionName and resolveTitle(goal.factionName))
        if fczh then goal.factionName = fczh end
    end

    if goal.candidates then
        for _, c in ipairs(goal.candidates) do
            if c.npc or c.npcName then
                local cnzh = (c.npc and npcs[c.npc])
                    or (c.npcName and (npcnames[c.npcName] or resolveTitle(c.npcName)))
                if cnzh then c.npcName = cnzh end
            end
            if c.location then
                local clzh = places[c.location] or zonenames[c.location] or resolveTitle(c.location)
                if clzh then c.location = clzh end
            end
        end
    end

    if goal.text then
        local xtzh = resolveTitle(goal.text) or notes[goal.text]
        if xtzh then goal.text = xtzh end
    end

    if goal.note then
        local gnzh = notes[goal.note] or resolveTitle(goal.note)
        if gnzh then goal.note = gnzh end
    end
end

local function localizeHeaderFields(tbl)
    if not tbl then return end
    local zzh = (tbl.zone and zones[tbl.zone])
        or (tbl.zoneName and (zonenames[tbl.zoneName] or resolveTitle(tbl.zoneName)))
    if zzh and tbl.zoneName then
        tbl.zoneName = zzh
    end
    if tbl.title then
        local tzh = resolveTitle(tbl.title) or (tbl.zone and zones[tbl.zone])
        if tzh then tbl.title = tzh end
    end
end

local function localizeGuide(def, header)
    if header then
        localizeHeaderFields(header)
    end
    if not def or def._polestarLocalized then return end
    def._polestarLocalized = true

    localizeHeaderFields(def)

    if def.steps then
        for _, step in ipairs(def.steps) do
            if step.title then
                local stzh = resolveTitle(step.title)
                if stzh then step.title = stzh end
            end
            if step.note then
                local snzh = notes[step.note] or resolveTitle(step.note)
                if snzh then step.note = snzh end
            end
            if step.goals then
                for _, goal in ipairs(step.goals) do
                    localizeGoal(goal)
                end
            end
        end
    end
end

-- Hook Polestar.Dungeons and Polestar.Codex so Dungeons, Rares, and Lookup also render Chinese
local function localizeCodexName(kind, id, enName)
    if id then
        if kind == "quest" then
            local q = quests[id] or getQuestTitle(id)
            if q then return q end
        elseif kind == "npc" or kind == "rare" then
            if npcs[id] then return npcs[id] end
        elseif kind == "item" or kind == "mount" or kind == "pet" or kind == "recipe" or kind == "tabard" then
            local it = items[id] or getItemName(id)
            if it then return it end
        elseif kind == "object" or kind == "treasure" then
            if objects[id] then return objects[id] end
        elseif kind == "zone" then
            if zones[id] then return zones[id] end
        elseif kind == "spell" then
            local sp = getSpellName(id)
            if sp then return sp end
        elseif kind == "faction" then
            local fc = getFactionName(id)
            if fc then return fc end
        end
    end
    if enName and enName ~= "" then
        return resolveTitle(enName) or enName
    end
    return enName
end

local function hookDungeonsAndCodex()
    local D = Polestar and Polestar.Dungeons
    if D and not D._localizerHooked then
        D._localizerHooked = true
        local function locDungeonSummary(s)
            if not s then return s end
            if s.name then s.name = resolveTitle(s.name) or s.name end
            if s.zone and zones[s.zone] then s.zoneName = zones[s.zone]
            elseif s.zoneName then s.zoneName = zonenames[s.zoneName] or resolveTitle(s.zoneName) or s.zoneName end
            return s
        end
        local function locDungeonQuest(q)
            if not q or q._locDone then return q end
            q._locDone = true
            if q.id and quests[q.id] then q.title = quests[q.id]
            elseif q.title then q.title = resolveTitle(q.title) or q.title end
            for _, ep in ipairs({ q.start, q.finish }) do
                if ep then
                    if ep.kind == "npc" and ep.id and npcs[ep.id] then ep.name = npcs[ep.id]
                    elseif ep.kind == "object" and ep.id and objects[ep.id] then ep.name = objects[ep.id]
                    elseif ep.name then ep.name = resolveTitle(ep.name) or ep.name end
                end
            end
            if q.startItem then
                q.startItem.name = (q.startItem.id and items[q.startItem.id]) or resolveTitle(q.startItem.name) or q.startItem.name
            end
            if q.rewards then
                for _, it in ipairs(q.rewards.items or {}) do
                    it.name = (it.id and (items[it.id] or getItemName(it.id))) or resolveTitle(it.name) or it.name
                end
                for _, rp in ipairs(q.rewards.rep or {}) do
                    rp.name = (rp.name and (places[rp.name] or resolveTitle(rp.name))) or rp.name
                end
            end
            if q.bosses then
                for i, bn in ipairs(q.bosses) do
                    q.bosses[i] = npcnames[bn] or resolveTitle(bn) or bn
                end
            end
            return q
        end
        if type(D.List) == "function" then
            local origList = D.List
            D.List = function(...)
                local list = origList(...)
                if type(list) == "table" then
                    for _, s in ipairs(list) do locDungeonSummary(s) end
                end
                return list
            end
        end
        if type(D.Get) == "function" then
            local origGet = D.Get
            D.Get = function(...)
                return locDungeonSummary(origGet(...))
            end
        end
        if type(D.Quests) == "function" then
            local origQuests = D.Quests
            D.Quests = function(...)
                local list = origQuests(...)
                if type(list) == "table" then
                    for _, q in ipairs(list) do locDungeonQuest(q) end
                end
                return list
            end
        end
        if type(D.Quest) == "function" then
            local origQuest = D.Quest
            D.Quest = function(...)
                return locDungeonQuest(origQuest(...))
            end
        end
        if type(D.Bosses) == "function" then
            local origBosses = D.Bosses
            D.Bosses = function(...)
                local list = origBosses(...)
                if type(list) == "table" then
                    for _, b in ipairs(list) do
                        if not b._locDone then
                            b._locDone = true
                            b.name = (b.npc and npcs[b.npc]) or npcnames[b.name] or resolveTitle(b.name) or b.name
                            for _, q in ipairs(b.quests or {}) do
                                if q.itemName then
                                    q.itemName = (q.item and items[q.item]) or itemnames[q.itemName] or resolveTitle(q.itemName) or q.itemName
                                end
                            end
                        end
                    end
                end
                return list
            end
        end
    end

    local C = Polestar and Polestar.Codex
    if C and not C._localizerHooked then
        C._localizerHooked = true
        if type(C.Name) == "function" then
            local origName = C.Name
            C.Name = function(kind, id, ...)
                local en = origName(kind, id, ...)
                return localizeCodexName(kind, id, en)
            end
        end
        for _, m in ipairs({
            { "Item", "item", "name" },
            { "Npc", "npc", "name" },
            { "Object", "object", "name" },
            { "Quest", "quest", "title" },
            { "Instance", "instance", "name" },
            { "Zone", "zone", "name" },
            { "Faction", "faction", "name" },
            { "Spell", "spell", "name" },
        }) do
            local fnName, kind, field = m[1], m[2], m[3]
            if type(C[fnName]) == "function" then
                local origFn = C[fnName]
                C[fnName] = function(id, ...)
                    local rec = origFn(id, ...)
                    if type(rec) == "table" and rec[field] then
                        rec[field] = localizeCodexName(kind, rec.id or id, rec[field])
                        if kind == "instance" and rec.bosses then
                            for _, b in ipairs(rec.bosses) do
                                b.name = (b.npc and npcs[b.npc]) or npcnames[b.name] or resolveTitle(b.name) or b.name
                            end
                        end
                    end
                    return rec
                end
            end
        end
        if type(C.Each) == "function" then
            local origEach = C.Each
            C.Each = function(kind, fn, ...)
                return origEach(kind, function(id, name, quality, status)
                    return fn(id, localizeCodexName(kind, id, name), quality, status)
                end, ...)
            end
        end
    end
end

local function applyLocaleStrings()
    if not Polestar or not Polestar.L or not localeTable then return end
    for k, v in pairs(localeTable) do
        Polestar.L[k] = v
    end
end

local function applyAll()
    if not Polestar then return end
    applyLocaleStrings()
    hookDungeonsAndCodex()

    local G = Polestar.Guides
    if G and type(G.List) == "function" and type(G.Get) == "function" then
        local ok, list = pcall(G.List)
        if ok and type(list) == "table" then
            for _, h in ipairs(list) do
                if h and h.id then
                    local okGet, def = pcall(G.Get, h.id)
                    localizeGuide(okGet and def or nil, h)
                end
            end
        end
    end

    if type(Polestar.RegisterGuide) == "function" and not Polestar._localizerHooked then
        Polestar._localizerHooked = true
        local origRegisterGuide = Polestar.RegisterGuide
        Polestar.RegisterGuide = function(def, ...)
            if type(def) == "table" then
                localizeGuide(def, nil)
            end
            return origRegisterGuide(def, ...)
        end
    end
end

applyAll()

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Polestar" or arg1 == "Polestar_Guides" or arg1 == "Polestar_Codex" or arg1 == "Polestar_Localizer" then
            applyAll()
        end
    elseif event == "PLAYER_LOGIN" then
        applyAll()
    end
end)
