--- This Manager makes sure that terraformers on the same field
--- are not working on the same terraforming task
--- Uses the driver as the key to lock the terraform position
--- Also handles locating flatten tasks for the driver
--- maybe at some point use CpObject to time out the terraform positions..
---@class TerraformManager
---@field lockedTerraformPositions table
---@field fieldPolygonMapCache table
TerraformManager = CpObject()
TerraformManager.terraformPositionPrecision = 0
TerraformManager.defaultMaxDistance = 50
TerraformManager.terrafarmHeightLockPrecision = 2
TerraformManager.minTerraformPosFromEdge = 1

function TerraformManager:init()
	self.lockedTerraformPositions = {}
    self.fieldPolygonMapCache = {}
    -- 0 = 1, 1 = 0.1, 2 = 0.01, etc.
    self.posPrecisionIncrement = 1 / 10 ^ self.terraformPositionPrecision
end

function TerraformManager:update(dt)
end

function TerraformManager:draw()
end

---@param name string
---@param x number
---@param z number
---@return number
function TerraformManager:rawPointToFlattenNode(name, x, z)
    return CpUtil.createNode(name, x, z, 0)
end

--- Disables the flattening position until the driver releases it
---@param driver AIDriveStrategyTerraform
---@param flattenNode number
function TerraformManager:lockInTerraformTask(driver, flattenNode)
	self.lockedTerraformPositions[flattenNode] = driver:getName()
end

--- Releases the flattening position
---@param flattenNodeToUnlock number
function TerraformManager:unlockTerraformPosition(flattenNodeToUnlock)
	self.lockedTerraformPositions[flattenNodeToUnlock] = nil
end

--- Releases the flattening positions for the given driver
---@param driver AIDriveStrategyTerraform
function TerraformManager:unlockTerraformPositionsForDriver(driver)
    local driverName = driver:getName()
	for flattenNode, d in pairs(self.lockedTerraformPositions) do
		if driverName == d then
			self.lockedTerraformPositions[flattenNode] = nil
		end
	end
end

--- Gets the terraform positions for the given field polygon. Returns an array of State3D positions
---@param fieldPolygon Polygon
---@return table
function TerraformManager:getTerraformPositions(fieldPolygon)
    if self.fieldPolygonMapCache[fieldPolygon] == nil then
        local positions = {}

        local xMin, xMax, zMin, zMax = math.huge, -math.huge, math.huge, -math.huge

        for _, v in ipairs(fieldPolygon) do
            xMin = math.min(xMin, v.x)
            zMin = math.min(zMin, v.z)
            xMax = math.max(xMax, v.x)
            zMax = math.max(zMax, v.z)
        end

        -- makes a grid of equidistant points within the field polygon
        -- the precision of the points is determined by the posPrecisionIncrement
        -- more precise = more points = more performance impact
        -- also checks if the point is not too close to the edge of the polygon (terraforming has effects beyond the point)
        for x = xMin, xMax, 3 do --3 is a common work width
            for z = zMin, zMax, 3 do
                if CpMathUtil.isPointInPolygon(fieldPolygon, x, z) then
                    local dist = CpMathUtil.getClosestDistanceToPolygonEdge(fieldPolygon, x, z)
                    if dist >= self.minTerraformPosFromEdge then
                        local nodeName = "TerraformNode_" .. #positions + 1 --I have no idea why names are a thing but here we are
                        table.insert(positions, self:rawPointToFlattenNode(nodeName, x, z))
                    end
                end
            end
        end

        print("Terraform Positions Generated: " .. #positions)

        self.fieldPolygonMapCache[fieldPolygon] = positions
        return positions
    else
        return self.fieldPolygonMapCache[fieldPolygon]
    end
end

--- Gets the closest terraform task for the given vehicle
--- Returns the closest position and the height of the position
---@param driver AIDriveStrategyTerraform
---@return number | nil, number, number, boolean
function TerraformManager:getClosestFreeFlattenTask(driver, shovelNode)
    if driver == nil then
        return nil, 0, 0, false
    end

    local fieldPolygon = driver.fieldPolygon
    if fieldPolygon == nil then
        driver:debug("Terraform Manager: Field polygon is nil")
        return nil, 0, 0, false
    end

    local flattenHeight = driver.flattenHeight
    if flattenHeight == nil then
        driver:debug("Terraform Manager: flattenHeight is nil")
        return nil, 0, 0, false
    end

    local raiseOnly = driver.terraformController:hasEnoughMaterialToRaise()
    local lowerOnly = driver.terraformController:hasEnoughMaterialToLower()

    local positions = self:getTerraformPositions(fieldPolygon)

    -- Calculate the distance from the vehicle to each terraform position
    local distances = {}
    for _, flattenNode in ipairs(positions) do
        if self.lockedTerraformPositions[flattenNode] == nil then
            local distance = calcDistanceFrom(flattenNode, shovelNode)
            table.insert(distances, {node = flattenNode, distance = distance})
        end
    end

    -- Sort the positions by distance in ascending order
    table.sort(distances, function(a, b)
        return a.distance < b.distance
    end)

    -- Find the closest position that is within the max distance, adhering to raiseOnly and lowerOnly flags
    for _, d in ipairs(distances) do
        if d.distance <= self.defaultMaxDistance then
            local x, _, z = getWorldTranslation(d.node)
            local height = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
            height = self:getFixedPrecisionHeight(height)

            if height ~= flattenHeight then
                local foundPosition = false

                if raiseOnly and height < flattenHeight then
                    foundPosition = true
                elseif lowerOnly and height > flattenHeight then
                    foundPosition = true
                end

                if foundPosition then
                    return d.node, height, d.distance, raiseOnly
                end
            end
        end
    end

    return nil, 0, 0, false
end

---@param flattenNode number
---@return number
function TerraformManager:getNodeDistanceToFlattenNode(flattenNode, node)
    local xb, _, zb = getWorldTranslation(flattenNode)
	local x, _, z = getWorldTranslation(node)
	local dx, dz = xb - x, zb - z
	-- local yRot = MathUtil.getYRotationFromDirection(dx, dz)
	return math.sqrt(dx * dx + dz * dz)
end

-- I tried MathUtil, but rounding is not precise enough. I need to truncate the number to a fixed precision
function TerraformManager:getFixedPrecisionHeight(height)
    return tonumber(string.format("%.2f", height))
end

g_terraformManager = TerraformManager()