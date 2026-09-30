-- AltArmy TBC — Economy tab, Supply Chain view: what alt-army.com's crafting planner does (with a
-- carousel of its screens) and how to set up Alt Army Sync, which uploads this addon's saved data.
-- Screens: Textures/Economy/*.tga, made by scripts/convert-economy-screenshots.py.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Economy
if not frame or not frame.SupplyChainView then return end

local Theme = AltArmy.Theme
local panel = frame.SupplyChainView
local inner = Theme.CreatePanelInnerContent(panel)

local UI = {
    TEXTURE_ROOT = "Interface\\AddOns\\AltArmy_TBC\\Textures\\Economy\\",
    GAP = 10, -- between paragraphs
    SECTION_GAP = 22, -- before a heading
    BUTTON_WIDTH = 90,
    BUTTON_HEIGHT = 22,
    BOX_HEIGHT = 24,
    BOX_LABEL_WIDTH = 150,
    index = 1,
    blocks = {}, -- laid out top to bottom by Layout()
}

local TEXT = {
    title = "Plan your crafting on alt-army.com",
    intro = {
        "Alt Army's website finds the most profitable things your characters can craft right now. It prices "
            .. "every recipe from real auction house scans taken with this addon, then works out the cheapest way "
            .. "to make it: buy each material from a vendor or the auction house, or craft it on one of your alts "
            .. "and mail it over.",
        "Choose Make gold to rank recipes by profit per hour of play, or Skill up to find the cheapest skill "
            .. "points in a profession. Open any recipe to see its plan as a flow chart or as timed steps, down "
            .. "to who crafts what and where to run in town.",
    },
    syncTitle = "Upload automatically with Alt Army Sync",
    syncIntro = "Addons can't reach the internet, so Alt Army saves what it sees to AltArmy_TBC.lua in your WoW "
        .. "folder. Alt Army Sync is a small Windows app that watches that file. Each time the game saves it "
        .. "(when you log out, switch characters or /reload), it uploads your characters, their professions and "
        .. "recipes, and your latest auction house scans. Nothing to copy or paste.",
    steps = {
        { "1. Create an account", "Sign in or create an account on alt-army.com. Making it on the website keeps "
            .. "what you have already set up in your browser." },
        { "2. Download and run Alt Army Sync", "Windows only. It finds your WoW folder on its own. The app isn't "
            .. "signed yet, so Windows warns you once: choose More info, then Run anyway." },
        { "3. Sign in to the app", "It asks for your email and password the first time: use the account from "
            .. "step 1. It keeps only a sign-in token on your computer, never your password." },
    },
    outro = "Then log in to each of your characters once with Alt Army installed, and scan the auction house as "
        .. "usual. Your characters and prices show up on the website after each upload. Alt Army Sync only reads "
        .. "AltArmy_TBC.lua and never changes a game file.",
    copyHint = "Click a box and press Ctrl+C to copy the address.",
    links = {
        { "Website", "https://alt-army.com" },
        { "Alt Army Sync download",
            "https://github.com/ntower/altarmy-profit/releases/latest/download/altarmy-sync.exe" },
    },
}

-- Native pixel sizes (convert-economy-screenshots.py prints them); drawn at the page width.
local IMAGES = {
    { file = "SupplyChainSearchResults", w = 814, h = 467,
        caption = "Search results: recipes your characters know, ranked by profit, profit per hour and return "
            .. "on investment, with the best way to sell each." },
    { file = "SupplyChainFlowChart", w = 800, h = 436,
        caption = "Flow chart: every material in a plan and where it comes from. Each node's swap menu lists "
            .. "other sources, best first." },
    { file = "SupplyChainDetailedSteps", w = 921, h = 567,
        caption = "Detailed steps: the same plan as a timed checklist for each character, with a map of the city." },
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

-- 1. What the site does.
Theme.SetTitleColor(AddText(TEXT.title, Theme.FONTS.title, 0))
for _, p in ipairs(TEXT.intro) do
    AddText(p, Theme.FONTS.body, UI.GAP)
end

-- 2. Carousel: one screenshot at a time, Previous / Next, its caption below.
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
local prevBtn = CreateFrame("Button", nil, carousel, "UIPanelButtonTemplate")
prevBtn:SetSize(UI.BUTTON_WIDTH, UI.BUTTON_HEIGHT)
prevBtn:SetText("Previous")
Theme.SkinButton(prevBtn)
local nextBtn = CreateFrame("Button", nil, carousel, "UIPanelButtonTemplate")
nextBtn:SetSize(UI.BUTTON_WIDTH, UI.BUTTON_HEIGHT)
nextBtn:SetText("Next")
Theme.SkinButton(nextBtn)
local counter = carousel:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
counter:SetPoint("TOP", shot, "BOTTOM", 0, -UI.GAP)
counter:SetHeight(UI.BUTTON_HEIGHT)
prevBtn:SetPoint("RIGHT", counter, "LEFT", -12, 0)
nextBtn:SetPoint("LEFT", counter, "RIGHT", 12, 0)
local caption = carousel:CreateFontString(nil, "OVERLAY", Theme.FONTS.body)
caption:SetPoint("TOP", counter, "BOTTOM", 0, -6)
caption:SetJustifyH("CENTER")
caption:SetJustifyV("TOP")
caption:SetWordWrap(true)
caption:SetTextColor(0.85, 0.85, 0.85, 1)
UI.blocks[#UI.blocks + 1] = { kind = "carousel", region = carousel, gap = UI.SECTION_GAP }

-- 3. Alt Army Sync setup.
Theme.SetTitleColor(AddText(TEXT.syncTitle, Theme.FONTS.title, UI.SECTION_GAP))
AddText(TEXT.syncIntro, Theme.FONTS.body, UI.GAP)
for _, step in ipairs(TEXT.steps) do
    AddText(step[1], Theme.FONTS.heading, UI.GAP + 4)
    AddText(step[2], Theme.FONTS.body, 4)
end
AddText(TEXT.outro, Theme.FONTS.body, UI.GAP + 4)

-- 4. Read-only boxes to copy the addresses from (the game can't open links).
AddText(TEXT.copyHint, Theme.FONTS.muted, UI.SECTION_GAP)
for _, link in ipairs(TEXT.links) do
    local rowFrame = CreateFrame("Frame", nil, page)
    local label = rowFrame:CreateFontString(nil, "OVERLAY", Theme.FONTS.heading)
    label:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
    label:SetWidth(UI.BOX_LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(link[1])
    local box = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
    box:SetPoint("LEFT", rowFrame, "LEFT", UI.BOX_LABEL_WIDTH + 6, 0)
    box:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
    box:SetHeight(UI.BOX_HEIGHT)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box.url = link[2]
    box:SetText(link[2])
    box:SetCursorPosition(0)
    -- Read-only: typing puts the address back; clicking selects all of it.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.url)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    UI.blocks[#UI.blocks + 1] = { kind = "fixed", region = rowFrame, height = UI.BOX_HEIGHT, gap = UI.GAP }
end

--- Show screenshot `i` (wraps around) sized to `width`; returns the carousel's height.
local function ShowShot(i, width)
    UI.index = ((i - 1) % #IMAGES) + 1
    local img = IMAGES[UI.index]
    local w = math.min(width, img.w)
    local h = math.floor(w * img.h / img.w + 0.5)
    shot:SetTexture(UI.TEXTURE_ROOT .. img.file)
    shot:SetSize(w, h)
    counter:SetText(UI.index .. " / " .. #IMAGES)
    caption:SetWidth(width)
    caption:SetText(img.caption)
    return h + UI.GAP + UI.BUTTON_HEIGHT + 6 + caption:GetStringHeight()
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
