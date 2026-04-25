return {
    TILE = 16,
    WORLD_MAX = 63,
    PLAYER_SIZE = 8,
    PLAYER_HALF = 4,
    HOTBAR_COUNT = 8,
    SAVE_PATH = "/lua/MCDSV01_save.lua",
    DAY_LENGTH = 4200,
    TORCH_RADIUS = 4,
    TORCH_STRENGTH = 5,

    ITEM_WOOD = 1,
    ITEM_STONE = 2,
    ITEM_TABLE = 3,
    ITEM_SWORD = 4,
    ITEM_PICK = 5,
    ITEM_CHEST = 6,
    ITEM_TORCH = 7,
    ITEM_DOOR = 8,
    ITEM_HOE = 9,
    ITEM_SEED = 10,
    ITEM_WHEAT = 11,
    ITEM_LADDER = 12,

    BLOCK_WOOD = 2,
    BLOCK_STONE = 3,
    BLOCK_TABLE = 4,
    BLOCK_CHEST = 5,
    BLOCK_TORCH = 6,
    BLOCK_DOOR_CLOSED = 7,
    BLOCK_DOOR_OPEN = 8,
    BLOCK_DIRT_TILLED = 10,
    BLOCK_CROP_1 = 11,
    BLOCK_CROP_2 = 12,
    BLOCK_CROP_3 = 13,
    BLOCK_LADDER_DOWN = 14,
    BLOCK_LADDER_UP = 15,

    ITEM_TO_BLOCK = {
        [1] = 2,
        [2] = 3,
        [3] = 4,
        [6] = 5,
        [7] = 6,
        [8] = 7,
        [12] = 14
    },

    ITEM_NAMES = {
        [1] = "Drewno",
        [2] = "Kamien",
        [3] = "Stol",
        [4] = "Miecz",
        [5] = "Kilof",
        [6] = "Skrzynia",
        [7] = "Pochodnia",
        [8] = "Drzwi",
        [9] = "Motyka",
        [10] = "Nasiona",
        [11] = "Zboze",
        [12] = "Drabina"
    },

    COLOR = {
        grass = {0, 20, 0},
        wood = {15, 7, 0},
        stone = {18, 18, 18},
        table = {20, 10, 2},
        chest = {22, 14, 5},
        torch = {31, 24, 6},
        door = {24, 16, 8},
        doorOpen = {20, 14, 10},
        player = {31, 31, 31},
        zombie = {12, 28, 12},
        zombieEye = {31, 0, 0},
        npcSkin = {31, 24, 18},
        npcCloth = {6, 12, 31},
        npcHair = {10, 6, 1},
        target = {31, 0, 0},
        panel = {3, 3, 3},
        panelLine = {9, 9, 9},
        text = {31, 31, 31},
        dim = {15, 15, 15},
        xp = {0, 28, 10},
        hp = {31, 0, 0},
        dark = {8, 8, 8},
        black = {0, 0, 0},
        lock = {31, 24, 0},
        chestBg = {8, 6, 2},
        craftBg = {10, 10, 10}
    },

    BLOCK_COLORS = {
        [2] = {15, 7, 0},
        [3] = {18, 18, 18},
        [4] = {20, 10, 2},
        [5] = {22, 14, 5},
        [6] = {31, 24, 6},
        [7] = {24, 16, 8},
        [8] = {20, 14, 10},
        [10] = {101, 67, 33},
        [11] = {120, 180, 50},
        [12] = {150, 200, 40},
        [13] = {200, 200, 20},
        [14] = {80, 50, 20},
        [15] = {120, 80, 40}
    },

    START_POS = {
        x = 16 * 32,
        y = 16 * 32,
        tx = 1,
        ty = 0
    },

    START_INV = {10, 10, 1, 0, 0, 0, 2, 1},

    STARTER_WOOD_NODES = {
        {29, 28}, {29, 29}, {29, 30}, {30, 29}, {28, 29},
        {27, 34}, {27, 35}, {27, 36}, {28, 35}, {29, 35},
        {34, 27}, {35, 27}, {36, 27}
    },

    STARTER_STONE_NODES = {
        {38, 29}, {39, 29}, {40, 29}, {39, 30}, {39, 31},
        {36, 35}, {37, 35}, {38, 35}, {37, 34}, {37, 36},
        {41, 33}, {42, 33}, {41, 34}
    },

    STARTER_ZOMBIES = {
        {x = 16 * 45, y = 16 * 31, hp = 10},
        {x = 16 * 44, y = 16 * 35, hp = 10},
        {x = 16 * 24, y = 16 * 28, hp = 10}
    },

    STARTER_NPCS = {
        {x = 16 * 26, y = 16 * 32, name = "Mila", text = "A otwiera drzwi i gada z NPC."},
        {x = 16 * 37, y = 16 * 32, name = "Niko", text = "Postaw pochodnie przed noca."}
    }
}