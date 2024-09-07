--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2022

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]


---@class AIDriveStrategyTerraform : AIDriveStrategyCourse
---@field terraformController TerraformerController
---@field flattenNode number
---@field pendingFlattenPos State3D
---@field flattenHeight number
---@field terraformManager TerraformManager
AIDriveStrategyTerraform = CpObject(AIDriveStrategyCourse)

AIDriveStrategyTerraform.myStates = {
    PREPARING_TO_UNLOAD = {},
    PREPARING_TO_LOAD = {},
    MOVING_FORWARD_FLATTENING = {},
    MOVING_FORWARD_TO_UNLOAD = {},
    UNLOADING_MATERIAL = {},
    UNLOADING_TERRAFORM = {},
    LOADING_MATERIAL = {},
    LOADING_TERRAFORM = {},
    DRIVING_TO_FLATTEN_TASK = {},
    MOVING_AWAY_FROM_OTHER_VEHICLE = {},
    IDLE = { fuelSaveAllowed = true },
    REVERSING_AFTER_PATHFINDER_FAILURE = {},
    MOVING_BACK_BEFORE_PATHFINDING = { pathfinderController = nil, pathfinderContext = nil }, -- there is an obstacle ahead, move back a bit so the pathfinder can succeed
}

AIDriveStrategyTerraform.closeEnoughFlattenNodeDistance = .5

function AIDriveStrategyTerraform:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyTerraform.myStates)
    self:setNewState(self.states.INITIAL)
    self.debugChannel = CpDebug.DBG_TERRAFORM
    self.flattenNode = nil
    self.pendingFlattenPos = nil
    self.flattenHeight = 0
    self.lastFillPerc = 0
    self.terraformManager = g_terraformManager
    self.drawColor = { 0, 0.8, 0.9, 1 }
end

function AIDriveStrategyTerraform:delete()
    AIDriveStrategyCourse.delete(self)
    self.terraformManager:unlockTerraformPositionsForDriver(self)
end

function AIDriveStrategyTerraform:getGeneratedCourse(jobParameters)
    return nil
end

function AIDriveStrategyTerraform:startWithoutCourse(jobParameters)
    -- to always have a valid course (for the traffic conflict detector mainly)
    self.course = Course.createStraightForwardCourse(self.vehicle, 5)
    self:startCourse(self.course, 1)

    self:debug('Starting terraforming initial course.')

    for _, implement in pairs(self.vehicle:getAttachedImplements()) do
        self:info(' - %s', CpUtil.getName(implement.object))
    end

    self:setNewState(self.states.IDLE)

    self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyTerraform:initializeImplementControllers(vehicle)
    self:addImplementController(vehicle, MotorController, Motorized, {}, nil)
    self:addImplementController(vehicle, WearableController, Wearable, {}, nil)
    self.levelImpl, self.leveler = self:addImplementController(vehicle, LevelerController, Leveler, {})
    self.foldableImpl, self.foldable = self:addImplementController(vehicle, FoldableController, Foldable, {})
    self.shovelImpl, self.terraformController = self:addImplementController(vehicle, TerraformerController, Shovel, {})
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyTerraform:setAllStaticParameters()
    -- make sure we have a good turning radius set
    self.turningRadius = AIUtil.getTurningRadius(self.vehicle, true)
    -- Set the offset to 0, we'll take care of getting the grabber to the right place
    self.settings.toolOffsetX:setFloatValue(0)
    self.reverser = AIReverseDriver(self.vehicle, self.ppc)
end

function AIDriveStrategyTerraform:setFieldPolygon(fieldPolygon)
    self.fieldPolygon = fieldPolygon
end

function AIDriveStrategyTerraform:setAIVehicle(vehicle, jobParameters)
    AIDriveStrategyCourse.setAIVehicle(self, vehicle, jobParameters)
    self.flattenHeight = self.terraformManager:getFixedPrecisionHeight(jobParameters.flattenHeight:getValue())

    self.terraformController:lockInFlattenHeight(self.flattenHeight)

    self:debug("Terraform goal height selected: %s", tostring(self.flattenHeight))
end

function AIDriveStrategyTerraform:getDubinsPathLengthToFlattenPos(flattenPos)
    local start = PathfinderUtil.getVehiclePositionAsState3D(self.vehicle)
    -- need to verify the lack of the angle is not an issue
    local solution = PathfinderUtil.dubinsSolver:solve(start, State3D(flattenPos.x, flattenPos.y, 0), self.turningRadius)
    return solution:getLength(self.turningRadius)
end

--- Sets the driver as finished, so either a path
--- to the start marker as a park position can be used
--- or the driver stops directly.
function AIDriveStrategyTerraform:setFinished()
    self.vehicle:prepareForAIDriving()
    if self.invertedStartPositionMarkerNode then
        self:debug("A valid start position is found, so the driver tries to finish at the inverted goal node")
        self:startPathfindingToStartMarker()
    else
        self:finishJob()
    end
end

function AIDriveStrategyTerraform:finishJob()
    self:debug('No more positions to flatten, finishing job')
    self:resetTerraforming()
    self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
end

-----------------------------------------------------------------------------------------------------------------------
--- Pathfinding
-----------------------------------------------------------------------------------------------------------------------

function AIDriveStrategyTerraform:initiatePathfindingToFlattenTaskNode()
    self:setNewState(self.states.WAITING_FOR_PATHFINDER)
    self:debug('Start pathfinding to flatten position %s', tostring(self.flattenNode))

    local context = PathfinderContext(self.vehicle)
    context:allowReverse(false):maxFruitPercent(self.settings.avoidFruit:getValue() and 10 or math.huge)
    self.pathfinderController:registerListeners(self, self.onPathfindingFinished, nil,
        self.onPathfindingObstacleAtStart)
    self.pathfinderController:findPathToNode(context, self.flattenNode)
end

function AIDriveStrategyTerraform:getPositionInfoFromVehicle()
    local xb, _, zb = getWorldTranslation(self.flattenNode)
    local x, _, z = getWorldTranslation(self.vehicle:getAIDirectionNode())
    local dx, dz = xb - x, zb - z
    local yRot = MathUtil.getYRotationFromDirection(dx, dz)
    return xb, zb, yRot, math.sqrt(dx * dx + dz * dz)
end

function AIDriveStrategyTerraform:findBestFlattenApproachAngle(needsToRaise)
    local fx, fy, fz = getWorldTranslation(self.flattenNode)
    local vx, vy, vz = getWorldTranslation(self.vehicle.rootNode)
    local minDistanceFromFlattenNode = calcDistanceFrom(self.vehicle.rootNode, self.terraformController:getShovelNode())
    local precision = 1 -- precision of iteration
    local radius = 20   -- search radius
    local positions = {}

    -- Function to calculate the distance between two points
    local getDistanceAndRotation = function(x1, z1, x2, z2)
        local dx, dz = x2 - x1, z2 - z1
        local yRot = MathUtil.getYRotationFromDirection(dx, dz)
        return yRot, math.sqrt(dx * dx + dz * dz)
    end

    -- Iterate over the area within the given radius to find the best angle to approach the flatten node
    for x = -radius, radius, precision do
        for z = -radius, radius, precision do
            local worldX = fx + x
            local worldZ = fz + z
            local height = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, worldX, 0, worldZ)
            local distance, rotation = getDistanceAndRotation(fx, fz, worldX, worldZ)

            -- we want to allow enough room to make a clean approach
            if CpMathUtil.isPointInPolygon(self.fieldPolygon, worldX, worldZ) then
                -- best way to raise is to be lower than the flatten node so the shovel intersects with the ground on approach
                -- opposite for lowering
                local shouldAddPosition = (needsToRaise and height < fy) or (not needsToRaise and height > fy)
                if shouldAddPosition then
                    local vDist = getDistanceAndRotation(vx, vz, worldX, worldZ)
                    table.insert(positions,
                        { rot = rotation, distance = vDist, diff = math.abs(height - fy), pos = { x = worldX, z = worldZ } })
                end
            end
        end
    end

    -- We want to use the position closest to the vehicle
    table.sort(positions, function(a, b) return a.distance < b.distance end)

    local maxDiff = 0
    local bestPosition = nil

    -- more height difference means more productivity
    for i = 1, math.min(#positions, 10) do
        local diff = positions[i].diff
        if diff > maxDiff then
            maxDiff = diff
            bestPosition = positions[i]
        end
    end

    if bestPosition == nil then
        self:debug('Could not find a good approach angle to flatten task!' .. tostring(#positions))
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end

    self.idealAnglePos = bestPosition.pos

    return bestPosition.rot
end

---@param needsToRaise boolean
function AIDriveStrategyTerraform:pathfindToNewFlattenTask(needsToRaise)
    --local bestYRotation = self:findBestFlattenApproachAngle(needsToRaise)
    local course = self:getAnalyticsCourseToNode(self.flattenNode)

    if course == nil then
        self:debug("Could not find a path to approach position for new flatten task!")
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end

    self:setNewState(self.states.DRIVING_TO_FLATTEN_TASK)
    self:startCourse(course, 1)
    self:debug("Started driving to new flatten task.")
end

---Generate a path to position the vehicle where the shovel node is placed right at the goal node, with a given offset and rotation goal.
---Will reset rotation to zero if no provided.
---@param goalNode number
---@param goalNodeYRotation number | nil
---@param distOffset number | nil
---@return Course | nil
function AIDriveStrategyTerraform:getAnalyticsCourseToNode(goalNode, goalNodeYRotation, distOffset)
    setRotation(goalNode, 0, goalNodeYRotation or 0, 0)
    distOffset = distOffset or 2
    distOffset = calcDistanceFrom(self.vehicle.rootNode, self.terraformController:getShovelNode()) + distOffset

    local path = PathfinderUtil.findAnalyticPath(ReedsSheppSolver(), self.vehicle:getAIDirectionNode(), 0,
        goalNode, 0, -distOffset, self.turningRadius)

    local course = Course.createFromAnalyticPath(self.vehicle, path, true)
    return course
end

---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategyTerraform:onPathfindingFinished(controller, success, course, goalNodeInvalid)
    if not success then
        self:debug('Pathfinding failed, giving up!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        self.terraformManager:unlockTerraformPosition(self.flattenNode)
        return
    end

    if course == nil then
        self:debug('Pathfinding failed, no course found!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end

    if self.state == self.states.WAITING_FOR_PATHFINDER then
        self:debug('Pathfinding finished, starting course to new flatten task.')
        self:setNewState(self.states.DRIVING_TO_FLATTEN_TASK)
        self:startCourse(course, 1)
    else
        self:debug('Pathfinding finished but state is not WAITING_FOR_PATHFINDER')
    end
end

--- Searches for a path to the start marker in the inverted direction.
function AIDriveStrategyTerraform:startPathfindingToStartMarker()
    self:setNewState(self.states.DRIVING_TO_START_MARKER)
    local context = PathfinderContext(self.vehicle)
    context:allowReverse(false):maxFruitPercent(self.settings.avoidFruit:getValue() and 10 or math.huge)
    self.pathfinderController:findPathToNode(context, self.invertedStartPositionMarkerNode, 0,
        -1.5 * AIUtil.getLength(self.vehicle), 2)
end

function AIDriveStrategyTerraform:onPathfindingObstacleAtStart(controller, lastContext, maxDistance,
                                                               trailerCollisionsOnly)
    g_baleToCollectManager:unlockBalesByDriver(self)
    self.balesTried = {}
    self:debug('Pathfinding detected obstacle at start, back up and retry')
    self:startReversing(self.states.REVERSING_DUE_TO_OBSTACLE_AHEAD)
end

function AIDriveStrategyTerraform:startReversing(state)
    self:setNewState(state)
    self:startCourse(Course.createStraightReverseCourse(self.vehicle, 10), 1)
end

function AIDriveStrategyTerraform:isNearFieldEdge()
    local x, _, z = localToWorld(self.vehicle:getAIDirectionNode(), 0, 0, 0)
    local vehicleIsOnField = CpFieldUtil.isOnField(x, z)
    x, _, z = localToWorld(self.vehicle:getAIDirectionNode(), 0, 0, 1.2 * self.turningRadius)
    local isFieldInFrontOfVehicle = CpFieldUtil.isOnFieldArea(x, z)
    self:debug('vehicle is on field: %s, field in front of vehicle: %s',
        tostring(vehicleIsOnField), tostring(isFieldInFrontOfVehicle))
    return vehicleIsOnField and not isFieldInFrontOfVehicle
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyTerraform:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_TO_FLATTEN_TASK then
            self:debug('Finished driving to flatten task position')
            self:onFlattenTaskArrival()
        elseif self.state == self.states.REVERSING_AFTER_PATHFINDER_FAILURE then
            self:debug('last waypoint reached after reversing due to pathfinder failure')
            self:initiatePathfindingToFlattenTaskNode()
        elseif self.state == self.states.DRIVING_TO_START_MARKER then
            self:debug("Inverted start marker position is reached.") -- not sure why we'd want to finish the job if we are just driving to the starting marker
            self:finishJob()
        elseif self.state == self.states.LOADING_TERRAFORM then
            self:debug('last waypoint reached while flattening in loading mode. Resetting.')
            self:setNewState(self.states.IDLE)
        elseif self.state == self.states.MOVING_FORWARD_TO_UNLOAD then
            self:debug('last waypoint reached while approaching to raise.')
            self:onRaiseTaskArrival()
        else
            self:debug('last waypoint reached but state is not actionable...')
        end
    end
end

function AIDriveStrategyTerraform:onRaiseTaskArrival()
    self.terraformController:beginUnloading()
    self:setNewState(self.states.UNLOADING_TERRAFORM)
end

function AIDriveStrategyTerraform:onFlattenTaskArrival()
    -- determine if we need to raise or lower.
    local x, y, z = getWorldTranslation(self.flattenNode)
    local needToRaise = y < self.flattenHeight

    if needToRaise then
        self:debug('Need to raise the land to %s', tostring(self.flattenHeight))
        self.terraformController:moveShovelToUnloadPosition()
        self.terraformController:enableUnloadingTerraforming()
        self.terraformController:enableTerraforming()
        self:setNewState(self.states.PREPARING_TO_UNLOAD)
    else
        self:debug('Need to lower the land to %s', tostring(self.flattenHeight))
        self.terraformController:moveShovelToLoadingPosition()
        self.terraformController:enableLoadingTerraforming()
        self.terraformController:enableTerraforming()
        self:setNewState(self.states.PREPARING_TO_LOAD)
    end
end

function AIDriveStrategyTerraform:onReadyToUnloadTerraform()
    local shovelDistanceFromFlattenNode = self:getShovelDistanceFromFlattenNode()

    if shovelDistanceFromFlattenNode > self.closeEnoughFlattenNodeDistance then
        self:debug('Approaching flatten node to slowly raise. Distance: %2.f', shovelDistanceFromFlattenNode)
        local course = self:getAnalyticsCourseToNode(self.flattenNode, nil, -1)
        if course == nil then
            self:debug('Could not find a path to approach position for new flatten task!')
            self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
            return
        end
        self:startCourse(course, 1)
    end

    -- when we want to raise, we want to drive all the way up to the flatten node before dumping
    self:setNewState(self.states.MOVING_FORWARD_TO_UNLOAD)
end

function AIDriveStrategyTerraform:onReadyToLoadTerraform()
    local shovelDistanceFromFlattenNode = self:getShovelDistanceFromFlattenNode()

    if shovelDistanceFromFlattenNode > self.closeEnoughFlattenNodeDistance then
        local course = self:getAnalyticsCourseToNode(self.flattenNode, nil, 0)
        if course == nil then
            self:debug('Could not find a path to approach position for new flatten task!')
            self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
            return
        end
        self:startCourse(course, 1)
    end

    -- when we want to flatten, we want to flatten on the way to the node.
    self:setNewState(self.states.LOADING_TERRAFORM)
end

--- apparently this is the main logic loop
function AIDriveStrategyTerraform:getDriveData(dt, vX, vY, vZ)
    self:updateLowFrequencyImplementControllers()
    self:updateLowFrequencyPathfinder()

    local moveForwards = not self.ppc:isReversing()
    local gx, gz
    if not moveForwards then
        local maxSpeed
        gx, gz, maxSpeed = self:getReverseDriveData()
        self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end

    local fieldSpeed = self.settings.fieldWorkSpeed:getValue()
    local reverseSpeed = self.settings.reverseSpeed:getValue()

    if self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setMaxSpeed(0)
    elseif self.state == self.states.DRIVING_TO_FLATTEN_TASK then
        self:setMaxSpeed(fieldSpeed)
    elseif self.state == self.states.UNLOADING_MATERIAL then
        if self.terraformController:isEmpty() then
            self:debug('Shovel is empty, finishing unload')
            self:setNewState(self.states.IDLE)
        end
        self:setMaxSpeed(0)
    elseif self.state == self.states.UNLOADING_TERRAFORM then
        if self.terraformController:isEmpty() then
            self:debug('Shovel is empty, finishing unload')
            self:setNewState(self.states.IDLE)
        end
        self:setMaxSpeed(0)
    elseif self.state == self.states.LOADING_MATERIAL then
        if self.terraformController:isFull() then
            self:debug('Shovel is full, finishing load')
            self:setNewState(self.states.IDLE)
        end
        self:setMaxSpeed(0)
    elseif self.state == self.states.LOADING_TERRAFORM then
        if self.terraformController:isFull() then
            self:debug('Shovel is full, finishing load early.')
            self:setNewState(self.states.IDLE)
        end
        local newFillPerc = self.terraformController:getFillLevelPercentage()
        if self.lastFillPerc == newFillPerc then
            self:setMaxSpeed(1)
        else
            self:setMaxSpeed(0)
        end
        self.lastFillPerc = newFillPerc
    elseif self.state == self.states.PREPARING_TO_UNLOAD then
        self:setMaxSpeed(0)
        if self.terraformController:isShovelInUnloadPosition() then
            self:onReadyToUnloadTerraform()
        end
    elseif self.state == self.states.PREPARING_TO_LOAD then
        self:setMaxSpeed(0)
        if self.terraformController:isShovelInLoadPosition() then
            self:onReadyToLoadTerraform()
        end
    elseif self.state == self.states.MOVING_AWAY_FROM_OTHER_VEHICLE then
        self:setMaxSpeed(reverseSpeed)
    elseif self.state == self.states.MOVING_FORWARD_TO_UNLOAD then
        self:setMaxSpeed(fieldSpeed / 2)
    elseif self.state == self.states.IDLE then
        self:setMaxSpeed(0)
        self.lastFillPerc = 0
        self:resetTerraforming()
        if not self.terraformController:isShovelInTransportPosition() then
            if not self.terraformController:isShovelMoving() then
                self:debug('Vehicle is idle and not in transport position. Moving shovel to transport position.')
                self.terraformController:moveShovelToTransportPosition()
            end
        else
            self:debug('Vehicle is idle and in transport position. Beginning first flatten task search.')
            self.flattenNode = nil

            local newFlattenNode, height, taskDist, needsToRaise = self.terraformManager:getClosestFreeFlattenTask(self,
                self.terraformController:getShovelNode())

            if newFlattenNode then
                self:debug('New flatten task found, starting pathfinding to flatten position with height ' ..
                    height .. ' and distance ' .. taskDist)
                self:setFlattenTaskNode(newFlattenNode)
                self:pathfindToNewFlattenTask(needsToRaise)
            else
                self:debug('No more flatten tasks found, finishing job')
                self:finishJob()
            end
        end
    elseif self.state == self.states.REVERSING_AFTER_PATHFINDER_FAILURE then
        self:setMaxSpeed(reverseSpeed)
    elseif self.state == self.states.MOVING_BACK_BEFORE_PATHFINDING then
        self:setMaxSpeed(reverseSpeed)
    end

    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyTerraform:calculateTightTurnOffset()
    self.tightTurnOffset = 0
end

function AIDriveStrategyTerraform:update(dt)
    AIDriveStrategyCourse.update(self, dt)
    self:updateImplementControllers(dt)

    if CpDebug:isChannelActive(self.debugChannel, self.vehicle) then
        if self.course then
            self.course:draw()
        elseif self.ppc:getCourse() then
            self.ppc:getCourse():draw()
        end
        if self.flattenNode then
            local x, y, z = getWorldTranslation(self.flattenNode)
            Utils.renderTextAtWorldPosition(x, y + 2, z, 'o', getCorrectTextSize(0.02), 0, self.drawColor)
        end
        if self.idealAnglePos then
            Utils.renderTextAtWorldPosition(self.idealAnglePos.x, self.flattenHeight + 2, self.idealAnglePos.z, 'p',
                getCorrectTextSize(0.02), 0, self.drawColor)
        end
        local x, y, z = getWorldTranslation(self.terraformController:getShovelNode())
        Utils.renderTextAtWorldPosition(x, y, z, 'u', getCorrectTextSize(0.02), 0, self.drawColor)
        self:drawNearbyHeights()
    end
end

function AIDriveStrategyTerraform:drawNearbyHeights()
    if self.flattenNode == nil then
        return
    end

    local fx, _, fz = getWorldTranslation(self.flattenNode)
    local precision = .5 -- precision of iteration
    local radius = 5

    for x = -radius, radius, precision do
        for z = -radius, radius, precision do
            local worldX = fx + x
            local worldZ = fz + z
            local height = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, worldX, 0, worldZ)
            height = self.terraformManager:getFixedPrecisionHeight(height)
            if CpMathUtil.isPointInPolygon(self.fieldPolygon, worldX, worldZ) then
                local drawColor = self.drawColor
                
                if height == self.flattenHeight then
                    drawColor = { 0, 0.8, 0.9, 1 }
                end
                if height > self.flattenHeight then
                    drawColor = { 1, 0, 0, 1 }
                end
                if height < self.flattenHeight then
                    drawColor = { 0, 1, 0, 1 }
                end

                Utils.renderTextAtWorldPosition(worldX, height + 2, worldZ, '.', getCorrectTextSize(0.02), 0, drawColor)
            end
        end
    end
end

function AIDriveStrategyTerraform:setNewState(newState)
    self.lastState = self.state
    self.state = newState
    self:debug('setNewState: %s', self.state.name)
end

function AIDriveStrategyTerraform:setFlattenTaskNode(flattenNode)
    self.flattenNode = flattenNode
    self.terraformManager:lockInTerraformTask(self, self.flattenNode)
end

function AIDriveStrategyTerraform:resetTerraforming()
    self.terraformController:disableTerraforming()
    self.terraformController:disableLoadingTerraforming()
    self.terraformController:disableUnloadingTerraforming()
end

function AIDriveStrategyTerraform:getShovelDistanceFromFlattenNode()
    return calcDistanceFrom(self.terraformController:getShovelNode(), self.flattenNode)
end
