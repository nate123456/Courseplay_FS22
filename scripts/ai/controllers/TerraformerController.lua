---@class TerraformerController : ShovelController
TerraformerController = CpObject(ShovelController)
TerraformerController.acceptableRaiseFillPercentage = 50
TerraformerController.TERRAFORM_MODES = { -- These map to the TerraFarm mode enum values
    LOADING_MODES = {
        NORMAL = 1,
        TERRAFORM = 5
    },
    UNLOADING_MODES = {
        NORMAL = 1,
        TERRAFORM = 5
    }
}

function TerraformerController:init(vehicle, implement, isConsoleCommand)
    ShovelController.init(self, vehicle, implement, isConsoleCommand)
    self.terraFarm = FS22_TerraFarm_MCE and FS22_TerraFarm_MCE.TerraFarm
    self.terraFarmMachine = self.terraFarm.getMachineManager():getMachineByObject(vehicle)
    self.lastShovelPositionOrder = nil

    -- This is a hack- tested vehicles seem to have valid shovel spec but are not initialized properly,
    -- so actions fail. This is a workaround to ensure the shovel is initialized properly.
    -- it would seem that this is only normally called when the given vehicle has a detachable implement added,
    -- so for vehicles with fixed shovels, this setup method is never called.
    -- this validation is the same as in CpShovelPositions.lua
    if not self.implement.spec_cpShovelPositions.hasValidShovel then
        local shovelSpec = self.implement.spec_shovel
        if self.implement.spec_cpShovelPositions and #shovelSpec.shovelNodes > 0 then
            CpShovelPositions.cpSetupShovelPositions(self.implement)
        end
    end

    if not self.terraFarm.enabled then
        self.terraFarm:setIsEnabled(true)
    end
end

--the shovel position class does not track its own state enough to validate that the shovel is in the correct position.
--so repeated calls to make to the right position result in at least one calc which immediately decides that it is in the right position
--however, the single calc sets the state to something else, so a single tick will find the state as not deactivated. 
--if the underlying class was refactored to validate that was already in the position it should be before changing state, that would be better
-- but for now, we check for the deactivated state to see if the shovel is moving
-- and store the last order. If it is not moving, we can assume that the last order is the current state. 
function TerraformerController:ensureUniquePositionCommand(shovelPos)
    if not self:isShovelMoving() then
        if self.lastShovelPositionOrder == shovelPos then
            self:debug("Shovel already in position")
            return
        end
    end
    self:moveShovelToPosition(shovelPos)
    self.lastShovelPositionOrder = shovelPos
end

function TerraformerController:moveShovelToLoadingPosition()
    self:debug("Moving shovel to loading position")
    self:ensureUniquePositionCommand(ShovelController.POSITIONS.LOADING)
end

function TerraformerController:moveShovelToTransportPosition()
    self:debug("Moving shovel to loading position")
    self:ensureUniquePositionCommand(ShovelController.POSITIONS.TRANSPORT)
end

function TerraformerController:moveShovelToUnloadPosition()
    self:debug("Moving shovel to loading position")
    self:ensureUniquePositionCommand(ShovelController.POSITIONS.PRE_UNLOADING)
end

function TerraformerController:beginUnloading()
    self:debug("Beginning unloading")
    self:ensureUniquePositionCommand(ShovelController.POSITIONS.UNLOADING)
end

function TerraformerController:isShovelMoving()
    return self.implement.spec_cpShovelPositions.state ~= CpShovelPositions.DEACTIVATED
end

function TerraformerController:isShovelInLoadPosition()
    local isShovelLoading = self.lastShovelPositionOrder == ShovelController.POSITIONS.LOADING
    -- self:debug("Checking if shovel is in loading position: %s | %2.f | moving: %s", isShovelLoading,
    --     self.implement:getShovelTipFactor(), self:isShovelMoving())
    return isShovelLoading and not self:isShovelMoving()
end

function TerraformerController:isShovelInTransportPosition()
    local isShovelLoading = self.lastShovelPositionOrder == ShovelController.POSITIONS.TRANSPORT
    -- self:debug("Checking if shovel is in loading position: %s | %2.f | moving: %s", isShovelLoading,
    --     self.implement:getShovelTipFactor(), self:isShovelMoving())
    return isShovelLoading and not self:isShovelMoving()
end

function TerraformerController:isShovelInUnloadPosition()
    local isShovelLoading = self.lastShovelPositionOrder == ShovelController.POSITIONS.PRE_UNLOADING
    -- self:debug("Checking if shovel is in loading position: %s | %2.f | moving: %s", isShovelLoading,
    --     self.implement:getShovelTipFactor(), self:isShovelMoving())
    return isShovelLoading and not self:isShovelMoving()
end

--Returns whether or not the shovel contents have enough for a reasonable size flatten task that would cost material to perform (i.e., raise the land)
function TerraformerController:hasEnoughMaterialToRaise()
    return self:getFillLevelPercentage() > self.acceptableRaiseFillPercentage
end

--Returns whether or not the shovel contents have enough for a reasonable size flatten task that would gain material to perform (i.e., lowering the land)
function TerraformerController:hasEnoughMaterialToLower()
    return self:getFillLevelPercentage() < self.acceptableRaiseFillPercentage
end

function TerraformerController:lockInFlattenHeight(flattenHeight)
    self.terraFarmMachine:setStateValue('heightLockHeight', flattenHeight)
    self.terraFarmMachine:setStateValue('heightLockEnabled', true)
end

--Will allow loading and unloading to potentially terraform the land instead of behaving like a normal shovel.
--Loading and unloading states must still be set to determine what occurs in those states.
function TerraformerController:enableTerraforming()
    self:debug("Enabling machine terraforming")
    self.terraFarmMachine:setIsEnabled(true)
end

--Will prevent loading and unloading from terraforming the land, behaving like a normal shovel.
function TerraformerController:disableTerraforming()
    if self.terraFarmMachine.enabled == false then
        return
    end

    self:debug("Disabling machine terraforming")
    self.terraFarmMachine:setIsEnabled(false)
end

--When the vehicle is in the loading position, this will allow it to terraform; i.e, lower the land and load material.
function TerraformerController:enableLoadingTerraforming()
    if self.terraFarmMachine.terraformMode == self.TERRAFORM_MODES.LOADING_MODES.TERRAFORM then
        return
    end

    self:debug("Enabling machine loading for terraforming")
    self.terraFarmMachine:setTerraformMode(self.TERRAFORM_MODES.LOADING_MODES.TERRAFORM)
end

--When the vehicle is in the loading position, this will prevent it from terraforming; it will only load material as normal.
function TerraformerController:disableLoadingTerraforming()
    if self.terraFarmMachine.terraformMode == self.TERRAFORM_MODES.LOADING_MODES.NORMAL then
        return
    end

    self:debug("Disabling machine loading for terraforming")
    self.terraFarmMachine:setTerraformMode(self.TERRAFORM_MODES.LOADING_MODES.NORMAL)
end

--When the vehicle is in the unloading position, this will allow it to terraform; i.e, raise the land and unload material to pay for it.
function TerraformerController:enableUnloadingTerraforming()
    if self.terraFarmMachine.dischargeMode == self.TERRAFORM_MODES.UNLOADING_MODES.TERRAFORM then
        return
    end

    self:debug("Enabling machine unloading for terraforming")
    self.terraFarmMachine:setDischargeMode(self.TERRAFORM_MODES.UNLOADING_MODES.TERRAFORM)
end

--When the vehicle is in the unloading position, this will prevent it from terraforming; it will only unload material as normal.
function TerraformerController:disableUnloadingTerraforming()
    if self.terraFarmMachine.dischargeMode == self.TERRAFORM_MODES.UNLOADING_MODES.NORMAL then
        return
    end

    self:debug("Disabling machine unloading for terraforming")
    self.terraFarmMachine:setDischargeMode(self.TERRAFORM_MODES.UNLOADING_MODES.NORMAL)
end
