local RARITY_CHANCE = {
    Normal = 0.7,
    Rare = 0.2,
    Epic = 0.08,
    Legendary = 0.02
}

local RARITY_COLOR_SEQUENCE  = {
    Normal = {
        {Color3.fromRGB(43, 253, 88),
        Color3.fromRGB(182, 252, 77),
        Color3.fromRGB(38, 255, 164)}
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

local function chooseRarity()
    local roll = math.random()
    if roll <= RARITY_CHANCE.Legendary then return "Legendary" end
    if roll <= RARITY_CHANCE.Legendary + RARITY_CHANCE.Epic then return "Epic" end
    if roll <= RARITY_CHANCE.Legendary + RARITY_CHANCE.Epic + RARITY_CHANCE.Rare then return "Rare" end
    return "Normal"
end

return {
    chooseRarity = chooseRarity,
    getColorSequence = chooseColorFromPool,
    RARITY_COLOR_SEQUENCE = RARITY_COLOR_SEQUENCE,
}