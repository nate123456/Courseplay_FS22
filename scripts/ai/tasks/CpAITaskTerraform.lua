---@class CpAITaskTerraform : CpAITask
CpAITaskTerraform = CpObject(CpAITask)

function CpAITaskTerraform:start()
	if self.isServer then
		self:debug("CP terraform task started.")
		local strategy = AIDriveStrategyTerraform(self, self.job)
		strategy:setFieldPolygon(self.job:getFieldPolygon())
		strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
		self.vehicle:startCpWithStrategy(strategy)
	end
	CpAITask.start(self)
end

function CpAITaskTerraform:stop(wasJobStopped)
	if self.isServer then
		self:debug("CP terraform task stopped.")
		self.vehicle:stopCpDriver(wasJobStopped)
	end
	CpAITask.stop(self)
end
