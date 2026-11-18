-- Auto Admin: our GUI image sheet (gui/autoAdmin_ui.dds, drawn by tools/make_textures.py) and the screen's colours.
-- Every fill, tile and icon on the admin screen is a white cell of the sheet, tinted. A Bitmap without an image of
-- its own draws the game's whole GUI atlas, so every Bitmap in our XML gets a cell: static ones are named
-- "aaImg_<cell>", the others are set in AutoAdminDialog.lua.
-- Author: Fennell

AutoAdminGui = {}

AutoAdminGui.FILENAME = "gui/autoAdmin_ui.dds"
AutoAdminGui.SIZE = 512
AutoAdminGui.CELL = 64
AutoAdminGui.INSET = 2      -- keeps the neighbouring cells out of the filtered edge
-- cell order of the sheet (8 per row), the same as CELLS in tools/make_textures.py
AutoAdminGui.CELLS = {"solid", "circle", "tile", "shield", "user", "key", "clock", "pause",
    "play", "trash", "plus", "refresh", "check", "power", "ring", "chevron",
    "crown", "lock", "up", "down"}

AutoAdminGui.COLOR = {
    gold = {0.851, 0.643, 0.255, 1},
    straw = {0.914, 0.780, 0.478, 1},
    night = {0.078, 0.200, 0.149, 1},
    green = {0.435, 0.749, 0.541, 1},
    online = {0.373, 0.816, 0.478, 1},
    offline = {0.345, 0.357, 0.337, 1},
    member = {0.659, 0.671, 0.639, 1},
    tile = {0.157, 0.169, 0.149, 1},
    white = {0.957, 0.945, 0.910, 1},
    dim = {0.600, 0.612, 0.588, 1},
    red = {0.902, 0.412, 0.333, 1},
    off = {0.290, 0.298, 0.282, 1}
}

AutoAdminGui.ROLE_COLOR = {[0] = "member", [1] = "green", [2] = "gold"}
AutoAdminGui.ROLE_ICON = {[0] = "user", [1] = "shield", [2] = "crown"}
AutoAdminGui.ROLE_TEXT = {[0] = "aa_role_member", [1] = "aa_role_admin", [2] = "aa_role_super"}

local function getCellUVs(name)
    for i, cellName in ipairs(AutoAdminGui.CELLS) do
        if cellName == name then
            local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
            local c, inset = AutoAdminGui.CELL, AutoAdminGui.INSET
            return GuiUtils.getUVs({col * c + inset, row * c + inset, c - 2 * inset, c - 2 * inset},
                {AutoAdminGui.SIZE, AutoAdminGui.SIZE})
        end
    end
    return nil
end

-- shows a cell of the sheet on a Bitmap; only reloads when the cell changes
function AutoAdminGui.setIcon(element, name)
    if element == nil or element.setImageFilename == nil or element.aaIcon == name then
        return
    end
    local uvs = getCellUVs(name)
    if uvs == nil then
        return
    end
    element:setImageFilename(AutoAdmin.modDirectory .. AutoAdminGui.FILENAME)
    if element.setImageUVs ~= nil then
        element:setImageUVs(nil, unpack(uvs))
    end
    element.aaIcon = name
end

function AutoAdminGui.getColor(colorName, alpha)
    local c = AutoAdminGui.COLOR[colorName] or AutoAdminGui.COLOR.white
    return c[1], c[2], c[3], alpha or c[4]
end

function AutoAdminGui.setColor(element, colorName, alpha)
    if element ~= nil and element.setImageColor ~= nil then
        local r, g, b, a = AutoAdminGui.getColor(colorName, alpha)
        element:setImageColor(nil, r, g, b, a)
    end
end

function AutoAdminGui.setTextColor(element, colorName, alpha)
    if element ~= nil and element.setTextColor ~= nil then
        element:setTextColor(AutoAdminGui.getColor(colorName, alpha))
    end
end

-- every element below `root` whose name / id starts with "aaImg_<cell>" gets that cell
function AutoAdminGui.applyStaticImages(root)
    if root == nil then
        return
    end
    local function walk(element)
        local key = element.name or element.id
        if type(key) == "string" then
            local cell = key:match("^aaImg_(%a+)")
            if cell ~= nil then
                AutoAdminGui.setIcon(element, cell)
            end
        end
        for _, child in ipairs(element.elements or {}) do
            walk(child)
        end
    end
    walk(root)
end
