--[[
    MINECRAFT DS - V22 + UPDATE (Farming, Layers, Minimap)
    - Dzien i noc.
    - XP i level.
    - Skrzynia 2x4 z odkladaniem przedmiotow jak w craftingu.
    - Pochodnie rozjasniajace noc.
    - Zapis/odczyt gry do osobnego pliku.
    - Lepszy FPS: rzadsze liczenie swiatla i mniej rysowania.
    - Dane statyczne ladowane z osobnego pliku.
    - Menu startowe, drzwi i NPC.
    -- NOWOSCI: --
    - Rolnictwo (Motyka, nasiona, zboze, wzrost roslin).
    - Drabiny i warstwy (zejscie pod ziemie).
    - ZOPTYMALIZOWANA Minimapa na dolnym ekranie (wzrost FPS).
]]

local DATA = dofile("/lua/MCDSV01_data.lua")

local TILE = DATA.TILE
local WORLD_MAX = DATA.WORLD_MAX
local PLAYER_SIZE = DATA.PLAYER_SIZE
local PLAYER_HALF = DATA.PLAYER_HALF
local HOTBAR_COUNT = DATA.HOTBAR_COUNT
local SAVE_PATH = DATA.SAVE_PATH
local DAY_LENGTH = DATA.DAY_LENGTH
local TORCH_RADIUS = DATA.TORCH_RADIUS
local TORCH_STRENGTH = DATA.TORCH_STRENGTH

local ITEM_WOOD = DATA.ITEM_WOOD
local ITEM_STONE = DATA.ITEM_STONE
local ITEM_TABLE = DATA.ITEM_TABLE
local ITEM_SWORD = DATA.ITEM_SWORD
local ITEM_PICK = DATA.ITEM_PICK
local ITEM_CHEST = DATA.ITEM_CHEST
local ITEM_TORCH = DATA.ITEM_TORCH
local ITEM_DOOR = DATA.ITEM_DOOR
local ITEM_HOE = DATA.ITEM_HOE
local ITEM_SEED = DATA.ITEM_SEED
local ITEM_WHEAT = DATA.ITEM_WHEAT
local ITEM_LADDER = DATA.ITEM_LADDER

local BLOCK_WOOD = DATA.BLOCK_WOOD
local BLOCK_STONE = DATA.BLOCK_STONE
local BLOCK_TABLE = DATA.BLOCK_TABLE
local BLOCK_CHEST = DATA.BLOCK_CHEST
local BLOCK_TORCH = DATA.BLOCK_TORCH
local BLOCK_DOOR_CLOSED = DATA.BLOCK_DOOR_CLOSED
local BLOCK_DOOR_OPEN = DATA.BLOCK_DOOR_OPEN
local BLOCK_DIRT_TILLED = DATA.BLOCK_DIRT_TILLED
local BLOCK_CROP_1 = DATA.BLOCK_CROP_1
local BLOCK_CROP_2 = DATA.BLOCK_CROP_2
local BLOCK_CROP_3 = DATA.BLOCK_CROP_3
local BLOCK_LADDER_DOWN = DATA.BLOCK_LADDER_DOWN
local BLOCK_LADDER_UP = DATA.BLOCK_LADDER_UP

local ITEM_TO_BLOCK = DATA.ITEM_TO_BLOCK
local ITEM_NAMES = DATA.ITEM_NAMES
local COLOR = DATA.COLOR
local BLOCK_COLORS = DATA.BLOCK_COLORS

local pX, pY
local tX, tY
local hp, maxHp, dead
local xp, level, dayClock
local inv, slot
local mTimer, minedX, minedY
local world, zombies, npcs, chests, torchLight
local cGrid, ccX, ccY
local chestX, chestY
local saveMessage, saveTimer
local colorCache = {}
local menuBg
local gameState = "main_menu"
local mainMenuChoice = 1
local deathMenuChoice = 1
local saveExists = false
local npcMessage = ""
local npcMessageTimer = 0

-- ZMIENNE (WARSTWY)
local currentLayer = 0
local worldsCache = {}

local MENU_BG_PATH = "/lua/TLO.jpg"
local MENU_BG_X = 58
local MENU_BG_Y = 10
local MENU_BUTTONS = {
    {x1 = MENU_BG_X + 12, y1 = MENU_BG_Y + 52, x2 = MENU_BG_X + 62, y2 = MENU_BG_Y + 63},
    {x1 = MENU_BG_X + 76, y1 = MENU_BG_Y + 52, x2 = MENU_BG_X + 128, y2 = MENU_BG_Y + 63}
}

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function tint(color, factor)
    factor = clamp(factor or 1, 0, 1)
    local level = math.floor(factor * 12 + 0.5)
    local key = color[1] * 1024 + color[2] * 32 + color[3]
    local bucket = colorCache[key]

    if not bucket then
        bucket = {}
        colorCache[key] = bucket
    end

    if not bucket[level] then
        bucket[level] = Color.new(
            math.floor(color[1] * (level / 12)),
            math.floor(color[2] * (level / 12)),
            math.floor(color[3] * (level / 12))
        )
    end

    return bucket[level]
end

local function inBounds(tx, ty)
    return tx >= 0 and tx <= WORLD_MAX and ty >= 0 and ty <= WORLD_MAX
end

local function makeEmptyWorld()
    world = {}
    worldsCache[currentLayer] = world
end

local function getTile(tx, ty)
    if not inBounds(tx, ty) then
        return nil
    end
    local column = world[tx]
    if column then
        return column[ty] or 0
    end
    return 0
end

local function setTile(tx, ty, id)
    if not inBounds(tx, ty) then
        return
    end

    if id and id > 0 then
        if not world[tx] then
            world[tx] = {}
        end
        world[tx][ty] = id
    else
        local column = world[tx]
        if column then
            column[ty] = nil
            if not next(column) then
                world[tx] = nil
            end
        end
    end
end

local function rebuildTorchLight()
    torchLight = {}
    for tx, column in pairs(world) do
        for ty, blockId in pairs(column) do
            if blockId == BLOCK_TORCH then
                changeTorchLight(tx, ty, 1)
            end
        end
    end
end

local function switchLayer(newLayer)
    worldsCache[currentLayer] = world
    currentLayer = newLayer
    if not worldsCache[currentLayer] then
        worldsCache[currentLayer] = {}
    end
    world = worldsCache[currentLayer]
    rebuildTorchLight()
end

local function refreshSaveFlag()
    local probe = io.open(SAVE_PATH, "r")
    saveExists = probe ~= nil
    if probe then
        probe:close()
    end
end

local function loadMenuBackground()
    local ok, image = pcall(function()
        return Image.load(MENU_BG_PATH, VRAM)
    end)

    if ok then
        menuBg = image
    else
        menuBg = nil
    end
end

local function chestKey(tx, ty)
    return tostring(tx) .. ":" .. tostring(ty)
end

local function parseChestKey(key)
    local sx, sy = string.match(key or "", "^(%-?%d+):(%-?%d+)$")
    if sx and sy then
        return tonumber(sx), tonumber(sy)
    end
    return nil, nil
end

local function createChestSlots()
    local slots = {}
    for i = 1, 8 do
        slots[i] = {id = 0, count = 0}
    end
    return slots
end

local function normalizeChestSlots(data)
    local fixed = createChestSlots()
    if type(data) ~= "table" then
        return fixed
    end

    for i = 1, 8 do
        local slotData = data[i]
        if type(slotData) == "table" then
            fixed[i].id = clamp(math.floor(slotData.id or 0), 0, 15)
            fixed[i].count = math.max(0, math.floor(slotData.count or 0))
            if fixed[i].count == 0 then
                fixed[i].id = 0
            end
        end
    end

    return fixed
end

local function getChest(tx, ty)
    local key = chestKey(tx, ty)
    if not chests[key] then
        chests[key] = createChestSlots()
    end
    return chests[key], key
end

local function copyNpc(data)
    return {
        x = data.x or 0,
        y = data.y or 0,
        name = data.name or "NPC",
        text = data.text or "..."
    }
end

local function spawnStarterNpcs()
    npcs = {}
    for i, npc in ipairs(DATA.STARTER_NPCS or {}) do
        npcs[i] = copyNpc(npc)
    end
end

local function collectNpcs()
    local data = {}
    for _, npc in ipairs(npcs or {}) do
        data[#data + 1] = copyNpc(npc)
    end
    return data
end

local function findNpcAtTile(tx, ty)
    for _, npc in ipairs(npcs or {}) do
        local nx = math.floor((npc.x + PLAYER_HALF) / TILE)
        local ny = math.floor((npc.y + PLAYER_HALF) / TILE)
        if nx == tx and ny == ty then
            return npc
        end
    end
    return nil
end

local function addTorchLightValue(tx, ty, amount)
    if not inBounds(tx, ty) or amount == 0 then
        return
    end

    if not torchLight[tx] then
        torchLight[tx] = {}
    end

    torchLight[tx][ty] = math.max(0, (torchLight[tx][ty] or 0) + amount)
    if torchLight[tx][ty] <= 0 then
        torchLight[tx][ty] = nil
        if not next(torchLight[tx]) then
            torchLight[tx] = nil
        end
    end
end

function changeTorchLight(tx, ty, direction)
    for dx = -TORCH_RADIUS, TORCH_RADIUS do
        for dy = -TORCH_RADIUS, TORCH_RADIUS do
            local strength = TORCH_STRENGTH - math.abs(dx) - math.abs(dy)
            if strength > 0 then
                addTorchLightValue(tx + dx, ty + dy, strength * direction)
            end
        end
    end
end

local function addTorch(tx, ty)
    changeTorchLight(tx, ty, 1)
end

local function removeTorch(tx, ty)
    changeTorchLight(tx, ty, -1)
end

local function getTorchLight(tx, ty)
    local column = torchLight[tx]
    if column then
        return column[ty] or 0
    end
    return 0
end

local function resetMining()
    mTimer = 0
    minedX, minedY = nil, nil
end

local function addItem(itemId, count)
    count = count or 1
    inv[itemId] = math.max(0, (inv[itemId] or 0) + count)
end

local function xpForNextLevel(lvl)
    return 12 + (lvl - 1) * 8
end

local function addXp(amount)
    xp = xp + amount
    while xp >= xpForNextLevel(level) do
        xp = xp - xpForNextLevel(level)
        level = level + 1
        maxHp = math.min(160, maxHp + 5)
        hp = math.min(maxHp, hp + 10)
        saveMessage = "Level " .. level .. "!"
        saveTimer = 150
    end
end

local function blockIsSolid(id)
    return id == BLOCK_WOOD
        or id == BLOCK_STONE
        or id == BLOCK_TABLE
        or id == BLOCK_CHEST
        or id == BLOCK_DOOR_CLOSED
end

function isSolid(nx, ny)
    local tx = math.floor(nx / TILE)
    local ty = math.floor(ny / TILE)
    if not inBounds(tx, ty) then
        return true
    end
    return blockIsSolid(getTile(tx, ty))
end

local function entityBlocked(nx, ny, size)
    size = size or PLAYER_SIZE
    return isSolid(nx, ny)
        or isSolid(nx + size - 1, ny)
        or isSolid(nx, ny + size - 1)
        or isSolid(nx + size - 1, ny + size - 1)
end

local function playerTile()
    return math.floor((pX + PLAYER_HALF) / TILE), math.floor((pY + PLAYER_HALF) / TILE)
end

local function getTargetTile()
    local bx = math.floor((pX + PLAYER_HALF) / TILE) + tX
    local by = math.floor((pY + PLAYER_HALF) / TILE) + tY
    return bx, by, getTile(bx, by)
end

local function clampTarget()
    tX = clamp(tX, -3, 3)
    tY = clamp(tY, -3, 3)
end

local function getAmbientLight()
    if currentLayer > 0 then return 0.22 end
    local ratio = (dayClock % DAY_LENGTH) / DAY_LENGTH
    local wave = (math.cos(ratio * math.pi * 2) + 1) * 0.5
    return 0.22 + wave * 0.78
end

local function getDayLabel()
    local light = getAmbientLight()
    if light > 0.72 then
        return "Dzien"
    elseif light < 0.4 then
        return "Noc"
    end
    return "Zmierzch"
end

local function getTileLight(tx, ty, ambient)
    if not inBounds(tx, ty) then
        return ambient
    end

    local best = ambient
    local ptx, pty = playerTile()
    local playerDist = math.abs(tx - ptx) + math.abs(ty - pty)
    local torchBonus = getTorchLight(tx, ty) * 0.07

    if playerDist <= 3 then
        local playerGlow = 0.9 - playerDist * 0.16
        if playerGlow > best then
            best = playerGlow
        end
    end

    if ambient + torchBonus > best then
        best = ambient + torchBonus
    end

    return clamp(best, 0.2, 1)
end

local function hotbarRect(index)
    local x = 4 + (index - 1) * 31
    return x, 138, x + 27, 171
end

local function countGridItems()
    local count = 0
    for y = 1, 3 do
        for x = 1, 3 do
            if cGrid[y][x] > 0 then
                count = count + 1
            end
        end
    end
    return count
end

local function clearCraftGrid()
    cGrid = {
        {0, 0, 0},
        {0, 0, 0},
        {0, 0, 0}
    }
end

local function refundCraftGrid()
    for y = 1, 3 do
        for x = 1, 3 do
            local itemId = cGrid[y][x]
            if itemId > 0 then
                addItem(itemId, 1)
                cGrid[y][x] = 0
            end
        end
    end
end

local function recipeTable()
    if countGridItems() ~= 4 then return false end
    for y = 1, 2 do
        for x = 1, 2 do
            if cGrid[y][x] == ITEM_WOOD and cGrid[y][x + 1] == ITEM_WOOD and cGrid[y + 1][x] == ITEM_WOOD and cGrid[y + 1][x + 1] == ITEM_WOOD then
                return true
            end
        end
    end
    return false
end

local function recipeChest()
    if countGridItems() ~= 8 or cGrid[2][2] ~= 0 then return false end
    for y = 1, 3 do
        for x = 1, 3 do
            if not (x == 2 and y == 2) and cGrid[y][x] ~= ITEM_WOOD then
                return false
            end
        end
    end
    return true
end

local function recipeTorch()
    return countGridItems() == 2 and cGrid[1][2] == ITEM_WOOD and cGrid[2][2] == ITEM_STONE
end

local function recipeSword()
    if countGridItems() ~= 3 then return false end
    for x = 1, 3 do
        local itemId = cGrid[1][x]
        if itemId > 0 and itemId == cGrid[2][x] and itemId == cGrid[3][x] then
            return true
        end
    end
    return false
end

local function recipePick()
    if countGridItems() ~= 5 then return false end
    local head = cGrid[1][2]
    if head <= 0 then return false end
    return cGrid[1][1] == head and cGrid[1][3] == head and cGrid[2][2] == head and cGrid[3][2] == head
end

local function recipeDoor()
    if countGridItems() ~= 6 then return false end
    for x = 1, 2 do
        if cGrid[1][x] == ITEM_WOOD and cGrid[1][x + 1] == ITEM_WOOD and cGrid[2][x] == ITEM_WOOD and cGrid[2][x + 1] == ITEM_WOOD and cGrid[3][x] == ITEM_WOOD and cGrid[3][x + 1] == ITEM_WOOD then
            return true
        end
    end
    return false
end

local function recipeHoe()
    if countGridItems() ~= 3 then return false end
    return cGrid[1][2] == ITEM_WOOD and cGrid[2][2] == ITEM_WOOD and cGrid[3][2] == ITEM_WOOD
end

local function recipeLadder()
    if countGridItems() ~= 3 then return false end
    return cGrid[1][1] == ITEM_WOOD and cGrid[2][1] == ITEM_WOOD and cGrid[3][1] == ITEM_WOOD
end

local function tryCraft()
    local crafted = false
    if recipeChest() then addItem(ITEM_CHEST, 1); addXp(4); crafted = true
    elseif recipeTable() then addItem(ITEM_TABLE, 1); addXp(3); crafted = true
    elseif recipeTorch() then addItem(ITEM_TORCH, 4); addXp(2); crafted = true
    elseif recipeDoor() then addItem(ITEM_DOOR, 1); addXp(3); crafted = true
    elseif recipePick() then addItem(ITEM_PICK, 1); addXp(5); crafted = true
    elseif recipeSword() then addItem(ITEM_SWORD, 1); addXp(5); crafted = true
    elseif recipeHoe() then addItem(ITEM_HOE, 1); addXp(3); crafted = true
    elseif recipeLadder() then addItem(ITEM_LADDER, 2); addXp(2); crafted = true
    end

    if crafted then
        clearCraftGrid()
        saveMessage = "Craft OK"
        saveTimer = 90
    else
        saveMessage = "Brak recepty"
        saveTimer = 90
    end
end

local function buildStarterWorld()
    setTile(33, 32, BLOCK_TABLE)
    for _, pos in ipairs(DATA.STARTER_WOOD_NODES) do setTile(pos[1], pos[2], BLOCK_WOOD) end
    for _, pos in ipairs(DATA.STARTER_STONE_NODES) do setTile(pos[1], pos[2], BLOCK_STONE) end
    for tx = 24, 28 do
        if tx ~= 26 then setTile(tx, 34, BLOCK_WOOD) end
        setTile(tx, 30, BLOCK_WOOD)
    end
    for ty = 31, 33 do
        setTile(24, ty, BLOCK_WOOD)
        setTile(28, ty, BLOCK_WOOD)
    end
    setTile(26, 34, BLOCK_DOOR_CLOSED)
    addItem(ITEM_SEED, 3)
end

local function spawnStarterZombies()
    zombies = {}
    for i, zombie in ipairs(DATA.STARTER_ZOMBIES) do
        zombies[i] = { x = zombie.x, y = zombie.y, hp = zombie.hp }
    end
end

local function newGame()
    pX, pY = DATA.START_POS.x, DATA.START_POS.y
    tX, tY = DATA.START_POS.tx, DATA.START_POS.ty
    hp, maxHp = 100, 100
    dead = false
    xp, level = 0, 1
    dayClock = 0
    inv = {}
    for i = 1, HOTBAR_COUNT do
        inv[i] = DATA.START_INV[i] or 0
    end
    slot = 1
    chests = {}
    cGrid = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}
    ccX, ccY = 2, 2
    chestX, chestY = 1, 1
    saveMessage = ""
    saveTimer = 0
    currentLayer = 0
    worldsCache = {}
    resetMining()
    makeEmptyWorld()
    buildStarterWorld()
    spawnStarterZombies()
    spawnStarterNpcs()
    rebuildTorchLight()
end

local function sortedKeys(tab)
    local keys = {}
    for key in pairs(tab) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            if type(a) == "number" or type(a) == "string" then return a < b end
            return tostring(a) < tostring(b)
        end
        return type(a) < type(b)
    end)
    return keys
end

local function serializeKey(key)
    if type(key) == "number" then return "[" .. tostring(key) .. "]" end
    if type(key) == "string" and string.match(key, "^[_%a][_%w]*$") then return key end
    return "[" .. string.format("%q", key) .. "]"
end

local function serialize(value, indent)
    indent = indent or ""
    local valueType = type(value)

    if valueType == "number" or valueType == "boolean" then return tostring(value) end
    if valueType == "string" then return string.format("%q", value) end
    if valueType ~= "table" then return "nil" end

    local nextIndent = indent .. "  "
    local parts = {"{\n"}
    local keys = sortedKeys(value)

    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = nextIndent .. serializeKey(key) .. " = " .. serialize(value[key], nextIndent) .. ",\n"
    end

    parts[#parts + 1] = indent .. "}"
    return table.concat(parts)
end

local function collectWorldBlocks()
    local blocks = {}
    worldsCache[currentLayer] = world
    for layerId, layerWorld in pairs(worldsCache) do
        for x, column in pairs(layerWorld) do
            for y, id in pairs(column) do
                if id and id > 0 then
                    blocks[#blocks + 1] = {x = x, y = y, id = id, layer = layerId}
                end
            end
        end
    end
    table.sort(blocks, function(a, b)
        if a.x == b.x then return a.y < b.y end
        return a.x < b.x
    end)
    return blocks
end

local function collectZombies()
    local data = {}
    for _, zombie in ipairs(zombies) do
        if zombie.hp and zombie.hp > 0 then
            data[#data + 1] = { x = zombie.x, y = zombie.y, hp = zombie.hp }
        end
    end
    return data
end

local function saveGame(message)
    local file = io.open(SAVE_PATH, "w")
    if not file then
        saveMessage = "Blad zapisu"
        saveTimer = 180
        return false
    end

    local data = {
        version = 1,
        player = { x = pX, y = pY, tx = tX, ty = tY, hp = hp, maxHp = maxHp, dead = dead, slot = slot, layer = currentLayer },
        stats = { xp = xp, level = level, dayClock = dayClock },
        inventory = inv,
        worldBlocks = collectWorldBlocks(),
        chests = chests,
        zombies = collectZombies(),
        npcs = collectNpcs()
    }

    file:write("-- MCDS SAVE\nreturn ")
    file:write(serialize(data))
    file:close()
    saveExists = true
    saveMessage = message or "Zapisano"
    saveTimer = 180
    return true
end

local function applyWorldBlocks(blocks)
    worldsCache = {}
    makeEmptyWorld()
    if type(blocks) ~= "table" then return end

    for _, block in ipairs(blocks) do
        if type(block) == "table" and inBounds(block.x or -1, block.y or -1) then
            local l = block.layer or 0
            if not worldsCache[l] then worldsCache[l] = {} end
            if not worldsCache[l][block.x] then worldsCache[l][block.x] = {} end
            worldsCache[l][block.x][block.y] = clamp(math.floor(block.id or 0), 0, 15)
        end
    end
    
    world = worldsCache[currentLayer]
    if not world then
        world = {}
        worldsCache[currentLayer] = world
    end
end

local function loadGame()
    newGame()

    local probe = io.open(SAVE_PATH, "r")
    if not probe then
        saveExists = false
        saveMessage = "Brak save"
        saveTimer = 120
        return false
    end
    probe:close()

    local ok, data = pcall(dofile, SAVE_PATH)
    if not ok or type(data) ~= "table" then
        saveMessage = "Uszkodzony save"
        saveTimer = 180
        return false
    end

    if type(data.player) == "table" then
        pX = tonumber(data.player.x) or pX
        pY = tonumber(data.player.y) or pY
        tX = clamp(math.floor(data.player.tx or tX), -3, 3)
        tY = clamp(math.floor(data.player.ty or tY), -3, 3)
        hp = tonumber(data.player.hp) or hp
        maxHp = tonumber(data.player.maxHp) or maxHp
        dead = data.player.dead and true or false
        slot = clamp(math.floor(data.player.slot or slot), 1, HOTBAR_COUNT)
        currentLayer = tonumber(data.player.layer) or 0
    end

    if type(data.stats) == "table" then
        xp = math.max(0, math.floor(data.stats.xp or xp))
        level = math.max(1, math.floor(data.stats.level or level))
        dayClock = math.max(0, math.floor(data.stats.dayClock or dayClock)) % DAY_LENGTH
    end

    if type(data.inventory) == "table" then
        inv = {}
        for i = 1, HOTBAR_COUNT do
            inv[i] = math.max(0, math.floor(data.inventory[i] or 0))
        end
    end

    if data.worldBlocks ~= nil then applyWorldBlocks(data.worldBlocks) end

    chests = {}
    if type(data.chests) == "table" then
        for key, chestData in pairs(data.chests) do
            local tx, ty = parseChestKey(key)
            if tx and ty and getTile(tx, ty) == BLOCK_CHEST then
                chests[key] = normalizeChestSlots(chestData)
            end
        end
    end

    zombies = {}
    if type(data.zombies) == "table" then
        for _, zombie in ipairs(data.zombies) do
            if type(zombie) == "table" and (zombie.hp or 0) > 0 then
                zombies[#zombies + 1] = {
                    x = tonumber(zombie.x) or (16 * 32),
                    y = tonumber(zombie.y) or (16 * 32),
                    hp = math.max(1, tonumber(zombie.hp) or 1)
                }
            end
        end
    end

    npcs = {}
    if type(data.npcs) == "table" then
        for _, npc in ipairs(data.npcs) do
            if type(npc) == "table" then
                npcs[#npcs + 1] = copyNpc(npc)
            end
        end
    else
        spawnStarterNpcs()
    end

    rebuildTorchLight()
    resetMining()
    saveExists = true
    npcMessage = ""
    npcMessageTimer = 0
    saveMessage = "Save wczytany"
    saveTimer = 150
    return true
end

local function startNewGame()
    newGame()
    gameState = "game"
    npcMessage = ""
    npcMessageTimer = 0
    saveMessage = "Nowa gra"
    saveTimer = 120
end

local function respawnPlayer()
    pX, pY = DATA.START_POS.x, DATA.START_POS.y
    tX, tY = DATA.START_POS.tx, DATA.START_POS.ty
    hp = maxHp
    dead = false
    resetMining()
    chestX, chestY = 1, 1
    ccX, ccY = 2, 2
    
    currentLayer = 0
    world = worldsCache[currentLayer]
    rebuildTorchLight()
    
    gameState = "game"
    npcMessage = ""
    npcMessageTimer = 0
    saveMessage = "Respawn"
    saveTimer = 120
end

local function livingZombieOnTile(tx, ty)
    for _, zombie in ipairs(zombies) do
        if zombie.hp > 0 then
            local zx = math.floor((zombie.x + PLAYER_HALF) / TILE)
            local zy = math.floor((zombie.y + PLAYER_HALF) / TILE)
            if zx == tx and zy == ty then return true end
        end
    end
    return false
end

local function canPlaceAt(tx, ty)
    if not inBounds(tx, ty) or getTile(tx, ty) ~= 0 then return false end
    local px, py = playerTile()
    if px == tx and py == ty then return false end
    if livingZombieOnTile(tx, ty) then return false end
    if findNpcAtTile(tx, ty) then return false end
    return true
end

local function miningGoal(id)
    if id == BLOCK_WOOD then return 42
    elseif id == BLOCK_STONE then return 62
    elseif id == BLOCK_TABLE or id == BLOCK_CHEST then return 48
    elseif id == BLOCK_TORCH then return 14
    elseif id == BLOCK_DOOR_CLOSED or id == BLOCK_DOOR_OPEN then return 18
    elseif id == BLOCK_DIRT_TILLED then return 15
    elseif id == BLOCK_CROP_1 or id == BLOCK_CROP_2 or id == BLOCK_CROP_3 then return 10
    elseif id == BLOCK_LADDER_DOWN or id == BLOCK_LADDER_UP then return 20
    end
    return 45
end

local function miningPower()
    local toolBoost = (inv[ITEM_PICK] > 0) and 1 or 0
    return 0.55 + toolBoost + (level - 1) * 0.04
end

local function mineReward(id, tx, ty)
    local key = chestKey(tx, ty)

    if id == BLOCK_WOOD then addItem(ITEM_WOOD, 1); addXp(2)
    elseif id == BLOCK_STONE then addItem(ITEM_STONE, 1); addXp(3)
    elseif id == BLOCK_TABLE then addItem(ITEM_TABLE, 1); addXp(2)
    elseif id == BLOCK_CHEST then
        addItem(ITEM_CHEST, 1)
        if chests[key] then
            for i = 1, 8 do
                local slotData = chests[key][i]
                if slotData.id > 0 and slotData.count > 0 then addItem(slotData.id, slotData.count) end
            end
            chests[key] = nil
        end
        addXp(3)
    elseif id == BLOCK_TORCH then addItem(ITEM_TORCH, 1); removeTorch(tx, ty); addXp(1)
    elseif id == BLOCK_DOOR_CLOSED or id == BLOCK_DOOR_OPEN then addItem(ITEM_DOOR, 1); addXp(1)
    elseif id == BLOCK_CROP_1 or id == BLOCK_CROP_2 then addItem(ITEM_SEED, 1)
    elseif id == BLOCK_CROP_3 then addItem(ITEM_WHEAT, 1); addItem(ITEM_SEED, 2); addXp(2)
    elseif id == BLOCK_LADDER_DOWN or id == BLOCK_LADDER_UP then addItem(ITEM_LADDER, 1); addXp(1)
    end
    setTile(tx, ty, 0)
end

local function tryDepositInChest(tx, ty)
    local chest = getChest(tx, ty)
    local index = (chestY - 1) * 4 + chestX
    local slotData = chest[index]
    if (inv[slot] or 0) <= 0 then return end
    if slotData.id == 0 or slotData.id == slot then
        slotData.id = slot
        slotData.count = slotData.count + 1
        inv[slot] = inv[slot] - 1
    end
end

local function takeFromChest(tx, ty, wholeStack)
    local chest = getChest(tx, ty)
    local index = (chestY - 1) * 4 + chestX
    local slotData = chest[index]
    if slotData.id <= 0 or slotData.count <= 0 then return end
    local amount = wholeStack and slotData.count or 1
    addItem(slotData.id, amount)
    slotData.count = slotData.count - amount
    if slotData.count <= 0 then
        slotData.id = 0
        slotData.count = 0
    end
end

local function interactWithWorldTarget(tx, ty, targetId)
    local npc = findNpcAtTile(tx, ty)
    if npc then
        npcMessage = npc.name .. ": " .. npc.text
        npcMessageTimer = 240
        return true
    end

    if targetId == BLOCK_DOOR_CLOSED then setTile(tx, ty, BLOCK_DOOR_OPEN); saveMessage = "Drzwi otwarte"; saveTimer = 60; return true
    elseif targetId == BLOCK_DOOR_OPEN then setTile(tx, ty, BLOCK_DOOR_CLOSED); saveMessage = "Drzwi zamkniete"; saveTimer = 60; return true
    elseif targetId == BLOCK_LADDER_DOWN then switchLayer(currentLayer + 1); saveMessage = "Zejscie nizej"; saveTimer = 60; return true
    elseif targetId == BLOCK_LADDER_UP then switchLayer(math.max(0, currentLayer - 1)); saveMessage = "Wyjscie wyzej"; saveTimer = 60; return true
    end
    return false
end

local function tickCrops()
    if dayClock % 300 == 0 then
        for tx, column in pairs(world) do
            for ty, id in pairs(column) do
                if id == BLOCK_CROP_1 then setTile(tx, ty, BLOCK_CROP_2)
                elseif id == BLOCK_CROP_2 then setTile(tx, ty, BLOCK_CROP_3) end
            end
        end
    end
end

local function drawItemIcon(screenId, itemId, x1, y1, x2, y2, factor)
    factor = factor or 1
    local w = x2 - x1
    local h = y2 - y1
    local midX = math.floor((x1 + x2) / 2)
    local midY = math.floor((y1 + y2) / 2)

    if itemId == ITEM_WOOD then
        screen.drawFillRect(screenId, x1 + 2, y1 + 2, x2 - 2, y2 - 2, tint(COLOR.wood, factor))
    elseif itemId == ITEM_STONE then
        screen.drawFillRect(screenId, x1 + 2, y1 + 2, x2 - 2, y2 - 2, tint(COLOR.stone, factor))
    elseif itemId == ITEM_TABLE then
        screen.drawFillRect(screenId, x1 + 2, y1 + 4, x2 - 2, y2 - 4, tint(COLOR.table, factor))
        screen.drawLine(screenId, x1 + 4, y2 - 4, x1 + 4, y2 - 1, tint(COLOR.wood, factor))
        screen.drawLine(screenId, x2 - 4, y2 - 4, x2 - 4, y2 - 1, tint(COLOR.wood, factor))
    elseif itemId == ITEM_SWORD then
        screen.drawLine(screenId, x1 + 4, y2 - 4, x2 - 4, y1 + 4, tint(COLOR.text, factor))
        screen.drawFillRect(screenId, midX - 1, y2 - 6, midX + 1, y2 - 2, tint(COLOR.wood, factor))
    elseif itemId == ITEM_PICK then
        screen.drawFillRect(screenId, x1 + 4, y1 + 4, x2 - 4, y1 + 7, tint(COLOR.stone, factor))
        screen.drawLine(screenId, midX, y1 + 7, midX, y2 - 2, tint(COLOR.wood, factor))
    elseif itemId == ITEM_CHEST then
        screen.drawFillRect(screenId, x1 + 2, y1 + 4, x2 - 2, y2 - 2, tint(COLOR.chest, factor))
        screen.drawRect(screenId, x1 + 2, y1 + 4, x2 - 2, y2 - 2, tint(COLOR.wood, factor))
        screen.drawFillRect(screenId, midX - 1, midY, midX + 1, midY + 3, tint(COLOR.lock, factor))
    elseif itemId == ITEM_TORCH then
        screen.drawLine(screenId, midX, y1 + 6, midX, y2 - 2, tint(COLOR.wood, factor))
        screen.drawFillRect(screenId, midX - 2, y1 + 2, midX + 2, y1 + 6, tint(COLOR.torch, factor))
    elseif itemId == ITEM_DOOR then
        screen.drawFillRect(screenId, x1 + 4, y1 + 2, x2 - 4, y2 - 2, tint(COLOR.door, factor))
        screen.drawRect(screenId, x1 + 4, y1 + 2, x2 - 4, y2 - 2, tint(COLOR.wood, factor))
        screen.drawFillRect(screenId, x2 - 7, midY - 1, x2 - 6, midY, tint(COLOR.lock, factor))
    elseif itemId == ITEM_HOE then
        screen.drawLine(screenId, midX, y1 + 4, midX, y2 - 2, tint(COLOR.wood, factor))
        screen.drawLine(screenId, midX - 4, y1 + 4, midX, y1 + 4, tint(COLOR.stone, factor))
    elseif itemId == ITEM_SEED then
        screen.drawPoint(screenId, midX, midY, tint({100, 200, 50}, factor))
        screen.drawPoint(screenId, midX + 2, midY + 2, tint({100, 200, 50}, factor))
    elseif itemId == ITEM_WHEAT then
        screen.drawLine(screenId, midX, y1 + 2, midX, y2 - 2, tint({220, 200, 50}, factor))
    elseif itemId == ITEM_LADDER then
        screen.drawLine(screenId, x1 + 4, y1 + 2, x1 + 4, y2 - 2, tint(COLOR.wood, factor))
        screen.drawLine(screenId, x2 - 4, y1 + 2, x2 - 4, y2 - 2, tint(COLOR.wood, factor))
        screen.drawLine(screenId, x1 + 4, midY, x2 - 4, midY, tint(COLOR.wood, factor))
    end
end

local function drawInventorySlot(screenId, index, selected)
    local x1, y1, x2, y2 = hotbarRect(index)
    local count = inv[index] or 0
    local border = selected and tint(COLOR.text, 1) or tint(COLOR.panelLine, 1)
    local fill = selected and tint(COLOR.dark, 1) or tint(COLOR.panel, 1)
    local iconFactor = (count > 0) and 1 or 0.35

    screen.drawFillRect(screenId, x1, y1, x2, y2, fill)
    screen.drawRect(screenId, x1, y1, x2, y2, border)
    if ITEM_NAMES[index] then
        drawItemIcon(screenId, index, x1 + 2, y1 + 2, x2 - 2, y2 - 8, iconFactor)
        screen.print(screenId, x1 + 3, y2 - 10, tostring(count), tint(COLOR.text, 1))
    end
end

local function drawChestScreen(tx, ty)
    local chest = getChest(tx, ty)
    screen.drawFillRect(SCREEN_UP, 0, 0, 255, 191, tint(COLOR.chestBg, 1))
    screen.print(SCREEN_UP, 88, 8, "SKRZYNIA 2x4", tint(COLOR.text, 1))
    screen.print(SCREEN_UP, 18, 28, "Y: Odluz  A: Wez  B: Wez stos", tint(COLOR.dim, 1))
    screen.print(SCREEN_UP, 22, 44, "Wybrany: " .. (ITEM_NAMES[slot] or "Puste"), tint(COLOR.text, 1))

    for row = 1, 2 do
        for col = 1, 4 do
            local idx = (row - 1) * 4 + col
            local x = 40 + (col - 1) * 45
            local y = 72 + (row - 1) * 48
            local slotData = chest[idx]
            local selected = (col == chestX and row == chestY)
            local border = selected and tint(COLOR.text, 1) or tint(COLOR.panelLine, 1)

            screen.drawFillRect(SCREEN_UP, x, y, x + 34, y + 34, tint(COLOR.panel, 1))
            screen.drawRect(SCREEN_UP, x, y, x + 34, y + 34, border)
            if slotData.id > 0 and slotData.count > 0 then
                drawItemIcon(SCREEN_UP, slotData.id, x + 3, y + 3, x + 31, y + 25, 1)
                screen.print(SCREEN_UP, x + 3, y + 22, tostring(slotData.count), tint(COLOR.text, 1))
            end
        end
    end
end

local function drawCraftScreen()
    screen.drawFillRect(SCREEN_UP, 0, 0, 255, 191, tint(COLOR.craftBg, 1))
    screen.print(SCREEN_UP, 84, 8, "CRAFTING 3x3", tint(COLOR.text, 1))
    screen.print(SCREEN_UP, 14, 24, "Y: poloz  A: craft  B: zwroc siatke", tint(COLOR.dim, 1))
    screen.print(SCREEN_UP, 24, 42, "Wybrany: " .. (ITEM_NAMES[slot] or "Puste"), tint(COLOR.text, 1))

    for row = 1, 3 do
        for col = 1, 3 do
            local dx = 76 + (col - 1) * 34
            local dy = 64 + (row - 1) * 34
            local selected = (col == ccX and row == ccY)
            local border = selected and tint(COLOR.text, 1) or tint(COLOR.panelLine, 1)

            screen.drawFillRect(SCREEN_UP, dx, dy, dx + 28, dy + 28, tint(COLOR.panel, 1))
            screen.drawRect(SCREEN_UP, dx, dy, dx + 28, dy + 28, border)
            if cGrid[row][col] > 0 then
                drawItemIcon(SCREEN_UP, cGrid[row][col], dx + 3, dy + 3, dx + 25, dy + 23, 1)
            end
        end
    end
    screen.print(SCREEN_UP, 16, 170, "Stol 2x2, skrzynia ramka, drzwi 2x3", tint(COLOR.dim, 1))
end

local function drawWorldBlock(tx, ty, tileId, cx, cy, ambient)
    local light = getTileLight(tx, ty, ambient)
    local x1 = tx * TILE - cx
    local y1 = ty * TILE - cy
    local x2 = x1 + TILE - 1
    local y2 = y1 + TILE - 1
    local blockColor = BLOCK_COLORS[tileId] or COLOR.grass

    screen.drawFillRect(SCREEN_UP, x1, y1, x2, y2, tint(blockColor, light))

    if tileId == BLOCK_TABLE or tileId == BLOCK_CHEST then
        screen.drawRect(SCREEN_UP, x1, y1, x2, y2, tint(COLOR.wood, light))
    elseif tileId == BLOCK_TORCH then
        screen.drawLine(SCREEN_UP, x1 + 8, y1 + 3, x1 + 8, y2 - 2, tint(COLOR.wood, light))
        screen.drawFillRect(SCREEN_UP, x1 + 6, y1 + 2, x1 + 10, y1 + 7, tint(COLOR.torch, light))
    elseif tileId == BLOCK_DOOR_CLOSED then
        screen.drawFillRect(SCREEN_UP, x1 + 3, y1 + 1, x2 - 3, y2 - 1, tint(COLOR.door, light))
        screen.drawRect(SCREEN_UP, x1 + 3, y1 + 1, x2 - 3, y2 - 1, tint(COLOR.wood, light))
        screen.drawFillRect(SCREEN_UP, x2 - 5, y1 + 8, x2 - 4, y1 + 9, tint(COLOR.lock, light))
    elseif tileId == BLOCK_DOOR_OPEN then
        screen.drawFillRect(SCREEN_UP, x1 + 10, y1 + 1, x2 - 1, y2 - 1, tint(COLOR.doorOpen, light))
        screen.drawRect(SCREEN_UP, x1 + 10, y1 + 1, x2 - 1, y2 - 1, tint(COLOR.wood, light))
    elseif tileId == BLOCK_DIRT_TILLED then
        screen.drawRect(SCREEN_UP, x1, y1, x2, y2, tint({60, 40, 20}, light))
        screen.drawLine(SCREEN_UP, x1, y1 + 4, x2, y1 + 4, tint({40, 25, 10}, light))
        screen.drawLine(SCREEN_UP, x1, y1 + 10, x2, y1 + 10, tint({40, 25, 10}, light))
    elseif tileId == BLOCK_CROP_1 or tileId == BLOCK_CROP_2 or tileId == BLOCK_CROP_3 then
        screen.drawRect(SCREEN_UP, x1, y1, x2, y2, tint({60, 40, 20}, light))
        local cropH = (tileId == BLOCK_CROP_1) and 4 or ((tileId == BLOCK_CROP_2) and 8 or 12)
        screen.drawFillRect(SCREEN_UP, x1 + 4, y2 - cropH, x2 - 4, y2, tint(blockColor, light))
    elseif tileId == BLOCK_LADDER_DOWN or tileId == BLOCK_LADDER_UP then
        screen.drawRect(SCREEN_UP, x1, y1, x2, y2, tint({0,0,0}, light))
        screen.drawLine(SCREEN_UP, x1 + 2, y1, x1 + 2, y2, tint(COLOR.wood, light))
        screen.drawLine(SCREEN_UP, x2 - 2, y1, x2 - 2, y2, tint(COLOR.wood, light))
        for ly = 2, 14, 4 do
            screen.drawLine(SCREEN_UP, x1 + 2, y1 + ly, x2 - 2, y1 + ly, tint(COLOR.wood, light))
        end
    end
end

local function drawWorld()
    local ambient = getAmbientLight()
    local maxCx = ((WORLD_MAX + 1) * TILE) - 256
    local maxCy = ((WORLD_MAX + 1) * TILE) - 192
    local cx = clamp(pX - 120, 0, maxCx)
    local cy = clamp(pY - 90, 0, maxCy)
    local fromX = math.floor(cx / TILE)
    local toX = fromX + 17
    local fromY = math.floor(cy / TILE)
    local toY = fromY + 13

    local bgColor = currentLayer > 0 and tint({30, 30, 30}, 1) or tint(COLOR.grass, 0.28 + ambient * 0.68)
    screen.drawFillRect(SCREEN_UP, 0, 0, 255, 191, bgColor)

    for tx = fromX, toX do
        local column = world[tx]
        if column then
            for ty, tileId in pairs(column) do
                if ty >= fromY and ty <= toY then
                    drawWorldBlock(tx, ty, tileId, cx, cy, ambient)
                end
            end
        end
    end

    local bx, by = getTargetTile()
    if inBounds(bx, by) then
        screen.drawRect(SCREEN_UP, bx * TILE - cx, by * TILE - cy, bx * TILE + TILE - 1 - cx, by * TILE + TILE - 1 - cy, tint(COLOR.target, 1))
    end

    local ptx, pty = playerTile()
    local playerLight = getTileLight(ptx, pty, ambient)
    screen.drawFillRect(SCREEN_UP, pX - cx, pY - cy, pX + PLAYER_SIZE - 1 - cx, pY + PLAYER_SIZE - 1 - cy, tint(COLOR.player, playerLight))

    for _, zombie in ipairs(zombies) do
        local zx = math.floor((zombie.x + PLAYER_HALF) / TILE)
        local zy = math.floor((zombie.y + PLAYER_HALF) / TILE)
        if zx >= fromX - 1 and zx <= toX + 1 and zy >= fromY - 1 and zy <= toY + 1 then
            local light = getTileLight(zx, zy, ambient)
            screen.drawFillRect(SCREEN_UP, zombie.x - cx, zombie.y - cy, zombie.x + PLAYER_SIZE - 1 - cx, zombie.y + PLAYER_SIZE - 1 - cy, tint(COLOR.zombie, light))
            screen.drawFillRect(SCREEN_UP, zombie.x + 2 - cx, zombie.y + 2 - cy, zombie.x + 5 - cx, zombie.y + 3 - cy, tint(COLOR.zombieEye, light))
        end
    end

    for _, npc in ipairs(npcs or {}) do
        local nx = math.floor((npc.x + PLAYER_HALF) / TILE)
        local ny = math.floor((npc.y + PLAYER_HALF) / TILE)
        if nx >= fromX - 1 and nx <= toX + 1 and ny >= fromY - 1 and ny <= toY + 1 then
            local light = getTileLight(nx, ny, ambient)
            screen.drawFillRect(SCREEN_UP, npc.x - cx, npc.y - cy, npc.x + PLAYER_SIZE - 1 - cx, npc.y + PLAYER_SIZE - 1 - cy, tint(COLOR.npcCloth, light))
            screen.drawFillRect(SCREEN_UP, npc.x + 1 - cx, npc.y - cy, npc.x + 6 - cx, npc.y + 2 - cy, tint(COLOR.npcHair, light))
            screen.drawFillRect(SCREEN_UP, npc.x + 2 - cx, npc.y + 2 - cy, npc.x + 5 - cx, npc.y + 4 - cy, tint(COLOR.npcSkin, light))
        end
    end
end

-- ZOPTYMALIZOWANA MINIMAPA (Poprawa z 4 FPS do normy)
local function drawMinimap(screenId, ox, oy)
    screen.drawFillRect(screenId, ox - 2, oy - 2, ox + 34, oy + 34, tint(COLOR.panelLine, 1))
    screen.drawFillRect(screenId, ox, oy, ox + 32, oy + 32, tint(COLOR.black, 1))
    local px, py = playerTile()
    
    -- FPS FIX: Rysujemy kafelki co 2 krok uzywajac grubszych blokow (zmniejszenie obliczen 4-krotnie!)
    for dx = -16, 15, 2 do
        for dy = -16, 15, 2 do
            local tx = px + dx
            local ty = py + dy
            local tid = getTile(tx, ty)
            if tid and tid > 0 then
                local c = BLOCK_COLORS[tid] or COLOR.wood
                screen.drawFillRect(screenId, ox + 16 + dx, oy + 16 + dy, ox + 17 + dx, oy + 17 + dy, tint(c, 1))
            end
        end
    end
    screen.drawFillRect(screenId, ox + 15, oy + 15, ox + 17, oy + 17, tint(COLOR.player, 1))
end

local function drawLowerScreen(targetId)
    local bx, by = getTargetTile()
    local targetNpc = findNpcAtTile(bx, by)

    screen.drawFillRect(SCREEN_DOWN, 0, 0, 255, 191, tint(COLOR.black, 1))
    screen.print(SCREEN_DOWN, 8, 8, "HP: " .. math.floor(hp) .. "/" .. maxHp, tint(COLOR.text, 1))
    screen.print(SCREEN_DOWN, 96, 8, "Lvl: " .. level, tint(COLOR.text, 1))
    screen.print(SCREEN_DOWN, 160, 8, "XP: " .. xp .. "/" .. xpForNextLevel(level), tint(COLOR.xp, 1))
    screen.print(SCREEN_DOWN, 8, 24, getDayLabel() .. "  W: " .. currentLayer .. " X: Save Start: Wyjdz", tint(COLOR.dim, 1))

    if targetId == BLOCK_TABLE then
        screen.print(SCREEN_DOWN, 8, 40, "Stol: strzalki, Y poloz, A craft, B zwroc", tint(COLOR.text, 1))
    elseif targetId == BLOCK_CHEST then
        screen.print(SCREEN_DOWN, 8, 40, "Skrzynia: strzalki, Y odloz, A wez, B stos", tint(COLOR.text, 1))
    elseif targetId == BLOCK_DOOR_CLOSED or targetId == BLOCK_DOOR_OPEN then
        screen.print(SCREEN_DOWN, 8, 40, "Drzwi: A otworz/zamknij  R stawia", tint(COLOR.text, 1))
    elseif targetId == BLOCK_LADDER_DOWN or targetId == BLOCK_LADDER_UP then
        screen.print(SCREEN_DOWN, 8, 40, "Drabina: A wejdz/zejdz warstwe", tint(COLOR.text, 1))
    elseif targetNpc then
        screen.print(SCREEN_DOWN, 8, 40, "NPC: A rozmawia", tint(COLOR.text, 1))
    else
        screen.print(SCREEN_DOWN, 8, 40, "L+strz: kop  R: stawiaj  B: atak  A: akcja", tint(COLOR.text, 1))
    end

    screen.print(SCREEN_DOWN, 8, 56, "Select+strz lub rysik: zmiana slotu", tint(COLOR.dim, 1))
    screen.print(SCREEN_DOWN, 8, 72, "Slot: " .. (ITEM_NAMES[slot] or "Puste"), tint(COLOR.text, 1))

    local hpFill = clamp(math.floor((hp / maxHp) * 100), 0, 100)
    local xpFill = clamp(math.floor((xp / xpForNextLevel(level)) * 100), 0, 100)

    screen.drawRect(SCREEN_DOWN, 8, 92, 110, 100, tint(COLOR.panelLine, 1))
    screen.drawFillRect(SCREEN_DOWN, 10, 94, 10 + hpFill, 98, tint(COLOR.hp, 1))
    screen.drawRect(SCREEN_DOWN, 130, 92, 232, 100, tint(COLOR.panelLine, 1))
    screen.drawFillRect(SCREEN_DOWN, 132, 94, 132 + xpFill, 98, tint(COLOR.xp, 1))

    if npcMessageTimer > 0 and npcMessage ~= "" then
        screen.print(SCREEN_DOWN, 8, 112, npcMessage, tint(COLOR.text, 1))
    elseif saveTimer > 0 and saveMessage ~= "" then
        screen.print(SCREEN_DOWN, 8, 112, saveMessage, tint(COLOR.text, 1))
    end

    for i = 1, HOTBAR_COUNT do
        drawInventorySlot(SCREEN_DOWN, i, i == slot)
    end
    
    drawMinimap(SCREEN_DOWN, 215, 95)
end

local function centerTextX(text, leftX, rightX)
    return math.floor((leftX + rightX - (string.len(text) * 6)) / 2)
end

local function drawMenuButton(screenId, button, text, selected, enabled)
    local fill = enabled and tint(COLOR.text, 1) or tint(COLOR.dim, 1)
    local border = selected and tint(COLOR.target, 1) or tint(COLOR.black, 1)
    local textColor = enabled and tint(COLOR.black, 1) or tint(COLOR.panelLine, 1)
    local textX = centerTextX(text, button.x1, button.x2)
    local textY = math.floor((button.y1 + button.y2 - 8) / 2)

    screen.drawFillRect(screenId, button.x1, button.y1, button.x2, button.y2, fill)
    screen.drawRect(screenId, button.x1, button.y1, button.x2, button.y2, border)
    screen.print(screenId, textX, textY, text, textColor)
end

local function drawMenuTop(title, optionOne, optionTwo, selectedChoice)
    screen.drawFillRect(SCREEN_UP, 0, 0, 255, 191, tint(COLOR.black, 1))
    if menuBg then
        screen.blit(SCREEN_UP, MENU_BG_X, MENU_BG_Y, menuBg)
    else
        screen.drawFillRect(SCREEN_UP, 40, 10, 216, 100, tint(COLOR.grass, 1))
        screen.print(SCREEN_UP, 76, 40, "MINECRAFT", tint(COLOR.text, 1))
        screen.print(SCREEN_UP, 88, 54, "NDS", tint(COLOR.text, 1))
    end
    screen.print(SCREEN_UP, centerTextX(title, 0, 255), 102, title, tint(COLOR.text, 1))
    drawMenuButton(SCREEN_UP, MENU_BUTTONS[1], optionOne, selectedChoice == 1, true)
    drawMenuButton(SCREEN_UP, MENU_BUTTONS[2], optionTwo, selectedChoice == 2, saveExists)
end

local function drawMenuBottom(lineOne, lineTwo)
    screen.drawFillRect(SCREEN_DOWN, 0, 0, 255, 191, tint(COLOR.black, 1))
    screen.print(SCREEN_DOWN, 14, 20, lineOne, tint(COLOR.text, 1))
    screen.print(SCREEN_DOWN, 14, 36, lineTwo, tint(COLOR.dim, 1))
    screen.print(SCREEN_DOWN, 14, 60, "Gora/Dol + A: wybierz", tint(COLOR.text, 1))
    screen.print(SCREEN_DOWN, 14, 76, "Start: wyjscie", tint(COLOR.dim, 1))
    if saveTimer > 0 and saveMessage ~= "" then
        screen.print(SCREEN_DOWN, 14, 104, saveMessage, tint(COLOR.text, 1))
    elseif not saveExists then
        screen.print(SCREEN_DOWN, 14, 104, "Brak save do wczytania", tint(COLOR.dim, 1))
    end
end

local function drawDeadLowerScreen()
    screen.drawFillRect(SCREEN_DOWN, 0, 0, 255, 191, tint(COLOR.black, 1))
    screen.print(SCREEN_DOWN, 18, 30, "X: zapisz gre", tint(COLOR.text, 1))
    screen.print(SCREEN_DOWN, 18, 46, "Select: menu smierci", tint(COLOR.text, 1))
    screen.print(SCREEN_DOWN, 18, 62, "Start: zapisz i wyjdz", tint(COLOR.dim, 1))
    if saveTimer > 0 and saveMessage ~= "" then
        screen.print(SCREEN_DOWN, 18, 90, saveMessage, tint(COLOR.text, 1))
    end
end

local function selectCurrentMenuOption(choice)
    if gameState == "main_menu" then
        if choice == 1 then startNewGame()
        else
            if not saveExists then saveMessage = "Brak save"; saveTimer = 120
            elseif loadGame() then gameState = "game" end
        end
    elseif gameState == "death_menu" then
        if choice == 1 then respawnPlayer()
        else
            if not saveExists then saveMessage = "Brak save"; saveTimer = 120
            elseif loadGame() then gameState = "game" end
        end
    end
end

local function handleMainMenuInput()
    if Keys.newPress.Up then mainMenuChoice = math.max(1, mainMenuChoice - 1) end
    if Keys.newPress.Down then mainMenuChoice = math.min(2, mainMenuChoice + 1) end
    if Keys.newPress.A then selectCurrentMenuOption(mainMenuChoice) end
end

local function handleDeathMenuInput()
    if Keys.newPress.Up then deathMenuChoice = math.max(1, deathMenuChoice - 1) end
    if Keys.newPress.Down then deathMenuChoice = math.min(2, deathMenuChoice + 1) end
    if Keys.newPress.A then selectCurrentMenuOption(deathMenuChoice) end
    if Keys.newPress.B or Keys.newPress.Select or Keys.newPress.select then gameState = "game" end
end

loadMenuBackground()
refreshSaveFlag()
newGame()
saveMessage = ""
saveTimer = 0

while true do
    Controls.read()

    if saveTimer > 0 then saveTimer = saveTimer - 1 end
    if npcMessageTimer > 0 then npcMessageTimer = npcMessageTimer - 1 end

    if Keys.newPress.Start then
        if gameState == "game" or gameState == "death_menu" then saveGame("Auto-save OK") end
        break
    end

    if gameState == "main_menu" then handleMainMenuInput()
    elseif gameState == "death_menu" then handleDeathMenuInput()
    elseif gameState == "game" then
        if Keys.newPress.X then saveGame("Zapisano do MCDSV01_save.lua") end

        if hp <= 0 then
            hp = 0
            dead = true
        end

        if dead then
            if Keys.newPress.Select or Keys.newPress.select then
                deathMenuChoice = 1
                gameState = "death_menu"
            end
        else
            dayClock = (dayClock + 1) % DAY_LENGTH
            tickCrops()

            local holdL = Keys.held.L or Keys.held.l
            local holdSel = Keys.held.Select or Keys.held.select
            local ambientNow = getAmbientLight()
            local isNight = ambientNow < 0.4

            if holdL then
                if Keys.newPress.Up then tY = tY - 1 end
                if Keys.newPress.Down then tY = tY + 1 end
                if Keys.newPress.Left then tX = tX - 1 end
                if Keys.newPress.Right then tX = tX + 1 end
                clampTarget()

                local bx, by, targetId = getTargetTile()
                if targetId and targetId > 0 then
                    if minedX ~= bx or minedY ~= by then
                        resetMining()
                        minedX, minedY = bx, by
                    end
                    mTimer = mTimer + miningPower()
                    if mTimer >= miningGoal(targetId) then
                        mineReward(targetId, bx, by)
                        resetMining()
                    end
                else
                    resetMining()
                end
            else
                resetMining()
            end

            local bx, by, targetId = getTargetTile()
            local onTable = targetId == BLOCK_TABLE
            local onChest = targetId == BLOCK_CHEST

            if holdSel then
                if Keys.newPress.Left then slot = math.max(1, slot - 1) end
                if Keys.newPress.Right then slot = math.min(HOTBAR_COUNT, slot + 1) end
            elseif onChest and not holdL then
                if Keys.newPress.Up then chestY = math.max(1, chestY - 1) end
                if Keys.newPress.Down then chestY = math.min(2, chestY + 1) end
                if Keys.newPress.Left then chestX = math.max(1, chestX - 1) end
                if Keys.newPress.Right then chestX = math.min(4, chestX + 1) end

                if Keys.newPress.Y then tryDepositInChest(bx, by) end
                if Keys.newPress.A then takeFromChest(bx, by, false) end
                if Keys.newPress.B then takeFromChest(bx, by, true) end
            elseif onTable and not holdL then
                if Keys.newPress.Up then ccY = math.max(1, ccY - 1) end
                if Keys.newPress.Down then ccY = math.min(3, ccY + 1) end
                if Keys.newPress.Left then ccX = math.max(1, ccX - 1) end
                if Keys.newPress.Right then ccX = math.min(3, ccX + 1) end

                if Keys.newPress.Y and slot <= ITEM_STONE and inv[slot] > 0 and cGrid[ccY][ccX] == 0 then
                    cGrid[ccY][ccX] = slot
                    inv[slot] = inv[slot] - 1
                end
                if Keys.newPress.A then tryCraft() end
                if Keys.newPress.B then refundCraftGrid() end
            elseif not holdL then
                local oldX, oldY = pX, pY
                if Keys.held.Up then pY = pY - 2 end
                if Keys.held.Down then pY = pY + 2 end
                if Keys.held.Left then pX = pX - 2 end
                if Keys.held.Right then pX = pX + 2 end
                pX = clamp(pX, 0, ((WORLD_MAX + 1) * TILE) - PLAYER_SIZE)
                pY = clamp(pY, 0, ((WORLD_MAX + 1) * TILE) - PLAYER_SIZE)

                if entityBlocked(pX, pY, PLAYER_SIZE) then pX, pY = oldX, oldY end
            end

            if not holdL and not onTable and not onChest and Keys.newPress.A then
                interactWithWorldTarget(bx, by, targetId)
            end

            if not onTable and not onChest and Keys.newPress.B then
                local damage = 1 + ((inv[ITEM_SWORD] > 0) and 2 or 0) + math.floor((level - 1) / 3)
                for _, zombie in ipairs(zombies) do
                    if math.abs(zombie.x - bx * TILE) < TILE and math.abs(zombie.y - by * TILE) < TILE then
                        zombie.hp = zombie.hp - damage
                    end
                end
            end

            if Keys.newPress.R then
                if slot == ITEM_HOE and getTile(bx, by) == 0 and not isSolid(bx * TILE, by * TILE) then
                    setTile(bx, by, BLOCK_DIRT_TILLED)
                elseif slot == ITEM_SEED and getTile(bx, by) == BLOCK_DIRT_TILLED and inv[slot] > 0 then
                    setTile(bx, by, BLOCK_CROP_1)
                    inv[slot] = inv[slot] - 1
                elseif canPlaceAt(bx, by) and ITEM_TO_BLOCK[slot] and inv[slot] > 0 then
                    local blockId = ITEM_TO_BLOCK[slot]
                    if blockId == BLOCK_LADDER_DOWN and currentLayer > 0 then blockId = BLOCK_LADDER_UP end
                    setTile(bx, by, blockId)
                    inv[slot] = inv[slot] - 1
                    if blockId == BLOCK_CHEST then chests[chestKey(bx, by)] = createChestSlots()
                    elseif blockId == BLOCK_TORCH then addTorch(bx, by) end
                end
            end

            for i = #zombies, 1, -1 do
                local zombie = zombies[i]
                if zombie.hp <= 0 then
                    table.remove(zombies, i)
                    addXp(8)
                else
                    local speed = isNight and 0.55 or 0.4
                    local stepX = 0
                    local stepY = 0

                    if zombie.x < pX then stepX = speed
                    elseif zombie.x > pX then stepX = -speed end

                    if zombie.y < pY then stepY = speed
                    elseif zombie.y > pY then stepY = -speed end

                    local nextX = zombie.x + stepX
                    if not entityBlocked(nextX, zombie.y, PLAYER_SIZE) then zombie.x = nextX end
                    local nextY = zombie.y + stepY
                    if not entityBlocked(zombie.x, nextY, PLAYER_SIZE) then zombie.y = nextY end

                    if math.abs(zombie.x - pX) < 8 and math.abs(zombie.y - pY) < 8 then
                        hp = hp - (isNight and 0.35 or 0.25)
                    end
                end
            end

            if Stylus.newPress then
                for i = 1, HOTBAR_COUNT do
                    local x1, y1, x2, y2 = hotbarRect(i)
                    if Stylus.X > x1 and Stylus.X < x2 and Stylus.Y > y1 and Stylus.Y < y2 then
                        slot = i
                    end
                end
            end
        end
    end

    if gameState == "main_menu" then
        drawMenuTop("MENU", "PLAY", "LOAD", mainMenuChoice)
        drawMenuBottom("PLAY: nowa gra", "LOAD: wczytaj zapis")
    elseif gameState == "death_menu" then
        drawMenuTop("PO SMIERCI", "RESPAWN", "LOAD", deathMenuChoice)
        drawMenuBottom("RESPAWN: wracasz na start", "LOAD: ostatni zapis")
    elseif dead then
        screen.drawFillRect(SCREEN_UP, 0, 0, 255, 191, tint(COLOR.black, 1))
        screen.print(SCREEN_UP, 92, 84, "KONIEC GRY", tint(COLOR.target, 1))
        screen.print(SCREEN_UP, 30, 104, "Select: menu  X: zapis  Start: wyjdz", tint(COLOR.text, 1))
        drawDeadLowerScreen()
    else
        local bx, by, targetId = getTargetTile()
        if targetId == BLOCK_CHEST then drawChestScreen(bx, by)
        elseif targetId == BLOCK_TABLE then drawCraftScreen()
        else drawWorld() end
        
        local _, _, lowerTargetId = getTargetTile()
        drawLowerScreen(lowerTargetId)
    end

    if screen.display then screen.display() else render() end
end