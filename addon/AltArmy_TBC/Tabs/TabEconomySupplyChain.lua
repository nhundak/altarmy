-- AltArmy TBC — Economy tab, Supply Chain view: what alt-army.com's crafting planner does, with its
-- address to copy and a carousel of its screens.
-- Screens: Textures/Economy/*.tga, made by scripts/convert-economy-screenshots.py.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Economy
if not frame or not frame.SupplyChainView then return end

local Theme = AltArmy.Theme
local panel = frame.SupplyChainView
local inner = Theme.CreatePanelInnerContent(panel)

local UI = {
    TEXTURE_ROOT = "Interface\\AddOns\\AltArmy_TBC\\Textures\\Economy\\",
    GAP = 10, -- between paragraphs
    SECTION_GAP = 22, -- before the carousel
    ARROW_SIZE = 24, -- carousel arrows, at the page's left and right edges
    BOX_HEIGHT = 24,
    BOX_WIDTH = 260,
    IMAGE_HEIGHT = 280, -- every screenshot is drawn this tall (less if the page is too narrow)
    index = 1,
    blocks = {}, -- laid out top to bottom by Layout()
}

local TEXT = {
    title = "Put your army to work",
    url = "https://alt-army.com/profit",
    intro = {
        "Alt Army's website combines your character data, the latest auction house prices, and its database of "
            .. "items and vendors to help you plan the best way to make money or increase your skills.",
    },
}

-- Native pixel sizes (convert-economy-screenshots.py prints them); each is scaled to UI.IMAGE_HEIGHT.
local IMAGES = {
    { file = "SupplyChainFlowChart", w = 800, h = 436 },
    { file = "SupplyChainDetailedSteps", w = 921, h = 567 },
    { file = "SupplyChainSearchResults", w = 814, h = 467 },
}

local viewport = Theme.CreateVerticalScrollViewport({
    parent = inner,
    gutterEdge = panel,
    anchorTop = { "TOPLEFT", inner, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -Theme.VerticalScrollBarGutter(), Theme.TAB_CONTENT_PADDING },
    valueStep = 20,
    wheelStep = 60,
    enableMouseWheel = true,
})
local page = viewport.child

--- A word-wrapped paragraph block.
local function AddText(text, font, gap, color)
    local fs = page:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetText(text)
    if color then fs:SetTextColor(color[1], color[2], color[3], 1) end
    UI.blocks[#UI.blocks + 1] = { kind = "text", region = fs, gap = gap }
    return fs
end

-- 1. Title with a read-only box to copy the address from (the game can't open links).
local titleRow = CreateFrame("Frame", nil, page)
local titleText = titleRow:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
titleText:SetPoint("LEFT", titleRow, "LEFT", 0, 0)
titleText:SetText(TEXT.title)
Theme.SetTitleColor(titleText)
local urlBox = CreateFrame("EditBox", nil, titleRow, "InputBoxTemplate")
urlBox:SetPoint("LEFT", titleText, "RIGHT", 14, 0)
urlBox:SetSize(UI.BOX_WIDTH, UI.BOX_HEIGHT)
urlBox:SetAutoFocus(false)
urlBox:SetMaxLetters(0)
urlBox:SetText(TEXT.url)
urlBox:SetCursorPosition(0)
-- Read-only: typing puts the address back; clicking selects all of it.
urlBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        self:SetText(TEXT.url)
        self:HighlightText()
    end
end)
urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
urlBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
urlBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
UI.blocks[#UI.blocks + 1] = { kind = "fixed", region = titleRow, height = UI.BOX_HEIGHT + 4, gap = 0 }

for _, p in ipairs(TEXT.intro) do
    AddText(p, Theme.FONTS.body, UI.GAP)
end

-- 2. Carousel: one screenshot at a time, with arrows at the page edges.
local carousel = CreateFrame("Frame", nil, page)
local shot = carousel:CreateTexture(nil, "ARTWORK")
shot:SetPoint("TOP", carousel, "TOP", 0, 0)
local shotBorder = CreateFrame("Frame", nil, carousel, "BackdropTemplate")
shotBorder:SetPoint("TOPLEFT", shot, "TOPLEFT", -1, 1)
shotBorder:SetPoint("BOTTOMRIGHT", shot, "BOTTOMRIGHT", 1, -1)
if shotBorder.SetBackdrop then
    shotBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    shotBorder:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.9)
end
--- A small skinned arrow button at one side edge of the page, level with the screenshot's middle.
local function CreateArrow(label, point)
    local btn = CreateFrame("Button", nil, carousel, "UIPanelButtonTemplate")
    btn:SetSize(UI.ARROW_SIZE, UI.ARROW_SIZE)
    btn:SetFrameLevel(shotBorder:GetFrameLevel() + 2)
    btn:SetPoint(point, carousel, point, 0, 0)
    btn:SetText(label)
    Theme.SkinButton(btn)
    return btn
end
local prevBtn = CreateArrow("<", "LEFT")
local nextBtn = CreateArrow(">", "RIGHT")
UI.blocks[#UI.blocks + 1] = { kind = "carousel", region = carousel, gap = UI.SECTION_GAP }

--- Show screenshot `i` (wraps around) sized to `width`; returns the carousel's height.
local function ShowShot(i, width)
    UI.index = ((i - 1) % #IMAGES) + 1
    local img = IMAGES[UI.index]
    -- One height for all, lowered only if the widest screenshot wouldn't fit between the arrows.
    local maxW = width - 2 * (UI.ARROW_SIZE + UI.GAP)
    local h = UI.IMAGE_HEIGHT
    for _, other in ipairs(IMAGES) do
        h = math.min(h, math.floor(maxW * other.h / other.w))
    end
    local w = math.floor(h * img.w / img.h + 0.5)
    shot:SetTexture(UI.TEXTURE_ROOT .. img.file)
    shot:SetSize(w, h)
    return h
end

--- Stack the blocks down the page at its current width and size the scroll range to fit.
local function Layout()
    local width = page:GetWidth()
    if not width or width < 100 then
        width = (inner:GetWidth() or 600) - Theme.VerticalScrollBarGutter()
    end
    local y = 0
    for _, block in ipairs(UI.blocks) do
        y = y + block.gap
        local region = block.region
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        region:SetWidth(width)
        local h
        if block.kind == "text" then
            h = region:GetStringHeight()
        elseif block.kind == "carousel" then
            h = ShowShot(UI.index, width)
        else
            h = block.height
        end
        region:SetHeight(h)
        y = y + h
    end
    page:SetHeight(y + UI.GAP)
    viewport.UpdateRange()
end
frame.LayoutSupplyChain = Layout

prevBtn:SetScript("OnClick", function()
    UI.index = UI.index - 1
    Layout()
end)
nextBtn:SetScript("OnClick", function()
    UI.index = UI.index + 1
    Layout()
end)

panel:HookScript("OnShow", Layout)
panel:HookScript("OnSizeChanged", function()
    if panel:IsShown() then Layout() end
end)
