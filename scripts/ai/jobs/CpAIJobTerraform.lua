--- Combine unloader job.
---@class CpAIJobTerraform : CpAIJob
---@field selectedFieldPlot FieldPlot
CpAIJobTerraform = {
	name = "TERRAFORM_CP",
	jobName = "CP_job_terraform",
	minStartDistanceToField = 20,
}

local AIJobTerraformCp_mt = Class(CpAIJobTerraform, CpAIJob)

function CpAIJobTerraform.new(isServer, customMt)
	local self = CpAIJob.new(isServer, customMt or AIJobTerraformCp_mt)
	self.selectedFieldPlot = FieldPlot(true)
	self.selectedFieldPlot:setVisible(false)
	self.selectedFieldPlot:setBrightColor(true)

	return self
end

function CpAIJobTerraform:setupTasks(isServer)
	CpAIJob.setupTasks(self, isServer)
	self.terraformingTask = CpAITaskTerraform(isServer, self)
	self:addTask(self.terraformingTask)
end

function CpAIJobTerraform:setupJobParameters()
	CpAIJob.setupJobParameters(self)
	self:setupCpJobParameters(CpTerraformingJobParameters(self))
end

function CpAIJobTerraform:getIsAvailableForVehicle(vehicle)
	return vehicle.getCanStartCpTerraformer and vehicle:getCanStartCpTerraformer()
end

function CpAIJobTerraform:getCanStartJob()
	return self:getFieldPolygon() ~= nil
end

function CpAIJobTerraform:applyCurrentState(vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	CpAIJobTerraform:superClass().applyCurrentState(self, vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	self.cpJobParameters:validateSettings()

	self:copyFrom(vehicle:getCpTerraformerJob())
	local x, z = self.cpJobParameters.fieldPosition:getPosition()
	-- no field position from the previous job, use the vehicle's current position
	if x == nil or z == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
		self.cpJobParameters.fieldPosition:setPosition(x, z)
	end
end

function CpAIJobTerraform:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.terraformingTask:setVehicle(vehicle)
end

--- Called when parameters change, scan field
function CpAIJobTerraform:validate(farmId)
	local isValid, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then
		vehicle:applyCpTerraformerJobParameters(self)
	end
	--------------------------------------------------------------
	--- Validate field setup
	--------------------------------------------------------------

	isValid, errorMessage = self:validateFieldPosition(isValid, errorMessage)
	local fieldPolygon = self:getFieldPolygon()
	--------------------------------------------------------------
	--- Validate start distance to field, if started with the hud
	--------------------------------------------------------------
	if isValid and self.isDirectStart and fieldPolygon then
		--- Checks the distance for starting with the hud, as a safety check.
		--- Firstly check, if the vehicle is near the field.
		local x, _, z = getWorldTranslation(vehicle.rootNode)
		isValid = CpMathUtil.isPointInPolygon(fieldPolygon, x, z) or
			CpMathUtil.getClosestDistanceToPolygonEdge(fieldPolygon, x, z) < self.minStartDistanceToField
		if not isValid then
			return false, g_i18n:getText("CP_error_vehicle_too_far_away_from_field")
		end
	end


	return isValid, errorMessage
end

function CpAIJobTerraform:validateFieldPosition(isValid, errorMessage)
	local tx, tz = self.cpJobParameters.fieldPosition:getPosition()
	if tx == nil or tz == nil then
		return false, g_i18n:getText("CP_error_not_on_field")
	end
	local fieldPolygon, _ = CpFieldUtil.getFieldPolygonAtWorldPosition(tx, tz)
	self:setFieldPolygon(fieldPolygon)
	if fieldPolygon then
		self.selectedFieldPlot:setWaypoints(fieldPolygon)
		self.selectedFieldPlot:setVisible(true)
	else
		return false, g_i18n:getText("CP_error_not_on_field")
	end
	return isValid, errorMessage
end

function CpAIJobTerraform:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
	if not isOverviewMap then
		self.selectedFieldPlot:draw(map)
	end
end

--- Gets the additional task description shown.
function CpAIJobTerraform:getDescription()
	local desc = CpAIJob:superClass().getDescription(self)
	local currentTask = self:getTaskByIndex(self.currentTaskIndex)
	if currentTask == self.driveToTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	elseif currentTask == self.terraformingTask then
		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionTerraforms")
	end
	return desc
end
