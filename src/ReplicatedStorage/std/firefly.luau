local RARITY_CHANCE = {
    Normal   = 0.5,
    Common   = 0.3,
    Uncommon = 0.2,
    Rare     = 0.1,
    Epic     = 0.05,
    Legendary= 0.02,
}

local RARITY_COLOR_SEQUENCE  = {
    Normal = {
        {Color3.fromRGB(43, 253, 88),
        Color3.fromRGB(182, 252, 77),
        Color3.fromRGB(38, 255, 164)}
    },
    Common = {
        {Color3.fromRGB(253, 102, 43),
        Color3.fromRGB(252, 220, 77),
        Color3.fromRGB(255, 152, 84)}
    },
    Uncommon = {
        {Color3.fromRGB(255, 0, 0),
        Color3.fromRGB(255, 90, 99),
        Color3.fromRGB(175, 15, 68)}
    },
    Rare = {
        {Color3.fromRGB(44, 30, 247),
        Color3.fromRGB(160, 200, 255),
        Color3.fromRGB(120, 180, 255)}
    },
    Epic = {
        {Color3.fromRGB(217, 64, 255),
        Color3.fromRGB(255, 31, 199),
        Color3.fromRGB(255, 32, 99)}
    },
    Legendary = {
        {Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(255, 255, 255),}
    } -- still rainbow
}

local function chooseColorFromPool(rarity)
    local pool = RARITY_COLOR_SEQUENCE[rarity]
    if pool then
        return pool[1]
    end
    return nil
end

local RARITY_ORDER = { "Legendary", "Epic", "Rare", "Uncommon", "Common", "Normal" }

-- precompute total weight
local TOTAL_WEIGHT = 0
for _, rarity in ipairs(RARITY_ORDER) do
    TOTAL_WEIGHT += RARITY_CHANCE[rarity]
end

local function chooseRarity(): string
    -- roll in [0, TOTAL_WEIGHT)
    local roll = math.random() * TOTAL_WEIGHT
    local acc = 0

    for _, rarity in ipairs(RARITY_ORDER) do
        acc += RARITY_CHANCE[rarity]
        if roll <= acc then
            return rarity
        end
    end

    -- fallback (should never hit)
    return "Normal"
end

local function rarityToIndex(rarity: string): number
    if rarity == "Normal" then
        return 0
    elseif rarity == "Common" then
        return 1
    elseif rarity == "Uncommon" then
        return 2
    elseif rarity == "Rare" then
        return 3
    elseif rarity == "Epic" then
        return 4
    elseif rarity == "Legendary" then
        return 5
    end
    return 0
end

return {
    chooseRarity = chooseRarity,
    chooseColorFromPool = chooseColorFromPool,
    RARITY_COLOR_SEQUENCE = RARITY_COLOR_SEQUENCE,
    rarityToIndex = rarityToIndex,
}