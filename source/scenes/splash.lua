import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/ui" -- (for optional crank indicator)

local gfx <const> = playdate.graphics

SplashMenu = {}
SplashMenu.__index = SplashMenu

function SplashMenu.new()
    local self = setmetatable({}, SplashMenu)

    self.items = {
        { label = "New Game",    id = "new",     requiresCrank = true  },
        { label = "Resume Game", id = "resume",  requiresCrank = true  },
        { label = "Settings",    id = "settings",requiresCrank = false },
    }
    self.selected = 1

    -- Background sprite (centered). Expect 400x240, but will draw whatever you supply.
    local bg = gfx.image.new("images/BGImage")
    assert(bg, "images/card.png not found or failed to load")
    self.bgSprite = gfx.sprite.new(bg)
    self.bgSprite:moveTo(200, 120)
    self.bgSprite:setZIndex(0)
    self.bgSprite:add()

    -- Pre-calc menu layout
    self.centerX = 200
    self.centerY = 120
    self.spacing = 24

    -- If crank is docked on start, default to first selectable item
    self:fixSelectionForCrankState()

    return self
end

function SplashMenu:update()
    local crankDocked = playdate.isCrankDocked()

    -- Navigation (skip disabled items)
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        self:moveSelection(-1, crankDocked)
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        self:moveSelection(1, crankDocked)
    end

    -- Select
    if playdate.buttonJustPressed(playdate.kButtonA) then
        local item = self.items[self.selected]

        print("Selected: " .. item.id)
    end
end

function SplashMenu:moveSelection(delta, crankDocked)
    local count = #self.items
    local i = self.selected

    for _ = 1, count do
        i = ((i - 1 + delta) % count) + 1
        local item = self.items[i]
        local disabled = item.requiresCrank and crankDocked
        if not disabled then
            self.selected = i
            return
        end
    end
end

function SplashMenu:fixSelectionForCrankState()
    local docked = playdate.isCrankDocked()
    if self.items[self.selected].requiresCrank and docked then
        self:moveSelection(1, docked)
    end
end

function SplashMenu:draw()
    local startY = self.centerY - self.spacing

    for idx, item in ipairs(self.items) do
        local y = startY + (idx - 1) * self.spacing

        gfx.setImageDrawMode(gfx.kDrawModeFillBlack)

        -- Highlight selected row
        if idx == self.selected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(100, y - 12, 200, 22, 6)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        end

        local w, h = gfx.getTextSize(item.label)
        gfx.drawText(item.label, math.floor((400 - w) / 2), y - math.floor(h / 2))
    end

    -- Clean up global state for other drawing
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setDitherPattern(1.0)
end


