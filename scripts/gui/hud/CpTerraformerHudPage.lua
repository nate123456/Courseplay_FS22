--- Terraforming Hud Page
---@class CpTerraformerHudPageElement : CpHudPageElement
CpTerraformerHudPageElement = {}
local CpTerraformerHudPageElement_mt = Class(CpTerraformerHudPageElement, CpHudPageElement)

function CpTerraformerHudPageElement.new(overlay, parentHudElement, customMt)
    ---@class CpTerraformerHudPageElement : CpHudPageElement
    ---@field copyButton CpHudButtonElement
    ---@field pasteButton CpHudButtonElement
    ---@field clearCacheBtn CpHudButtonElement
    ---@field copyCacheText CpTextHudElement
    local self = CpHudPageElement.new(overlay, parentHudElement, customMt or CpTerraformerHudPageElement_mt)
        
    return self
end
function CpTerraformingHudPageElement:setupElements(baseHud, vehicle, lines, wMargin, hMargin)
    self.flattenHeightXBtn = baseHud:addLineTextButtonWithIncrementalButtons(self, 2, CpBaseHud.defaultFontSize,
    vehicle:getCpSettings().flattenHeight)

    CpGuiUtil.addCopyCourseBtn(self, baseHud, vehicle, lines, wMargin, hMargin, 1)
end

function CpTerraformingHudPageElement:update(dt)
    CpTerraformingHudPageElement:superClass().update(self, dt)
end

function CpTerraformingHudPageElement:updateContent(vehicle, status)
    local flattenheight = vehicle:getCpSettings().flattenHeight
    self.flattenHeightXBtn:setTextDetails(flattenheight:getTitle(), flattenheight:getString())
    self.flattenHeightXBtn:setDisabled(flattenheight:getIsDisabled())

    CpGuiUtil.updateCopyBtn(self, vehicle, status)
end
