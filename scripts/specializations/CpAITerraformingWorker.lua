local modName = CpAITerraformingWorker and CpAITerraformingWorker.MOD_NAME -- for reload

--- Specialization for the silo loader job
--- Used for shovel loader and big silo loader, like the Ropa NarwaRo.
---@class CpAITerraformingWorker
CpAITerraformingWorker = {}

CpAITerraformingWorker.flattenHeightText = g_i18n:getText("CP_fieldWorkJobParameters_flattenHeight")

CpAITerraformingWorker.MOD_NAME = g_currentModName or modName
CpAITerraformingWorker.NAME = ".cpAITerraformingWorker"
CpAITerraformingWorker.SPEC_NAME = CpAITerraformingWorker.MOD_NAME .. CpAITerraformingWorker.NAME
CpAITerraformingWorker.KEY = "." .. CpAITerraformingWorker.MOD_NAME .. CpAITerraformingWorker.NAME

function CpAITerraformingWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAITerraformingWorker.KEY
    CpJobParameters.registerXmlSchema(schema, key .. ".cpJob")
end

function CpAITerraformingWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations)
end

function CpAITerraformingWorker.register(typeManager, typeName, specializations)
    if CpAITerraformingWorker.prerequisitesPresent(specializations) then
        typeManager:addSpecialization(typeName, CpAITerraformingWorker.SPEC_NAME)
    end
end

function CpAITerraformingWorker.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAITerraformingWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onUpdate', CpAITerraformingWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAITerraformingWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAITerraformingWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAITerraformingWorker)
end

function CpAITerraformingWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpTerraformingWorker",
        CpAITerraformingWorker.getCanStartCpTerraformingWorker)
    SpecializationUtil.registerFunction(vehicleType, "getCpTerraformingWorkerJobParameters",
        CpAITerraformingWorker.getCpTerraformingWorkerJobParameters)

    SpecializationUtil.registerFunction(vehicleType, "applyCpTerraformingWorkerJobParameters",
        CpAITerraformingWorker.applyCpTerraformingWorkerJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpTerraformingWorkerJob",
        CpAITerraformingWorker.getCpTerraformingWorkerJob)
end

function CpAITerraformingWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAITerraformingWorker.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob',
        CpAITerraformingWorker.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp',
        CpAITerraformingWorker.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAITerraformingWorker
    .startCpAtLastWp)
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAITerraformingWorker:onLoad(savegame)
    self.spec_cpAITerraformingWorker = self["spec_" .. CpAITerraformingWorker.SPEC_NAME]
    local spec = self.spec_cpAITerraformingWorker
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.TERRAFORM_CP)
    spec.cpJob:setVehicle(self, true)
end

function CpAITerraformingWorker:onLoadFinished(savegame)
    local spec = self.spec_cpAITerraformingWorker
    if savegame ~= nil then
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key .. CpAITerraformingWorker.KEY .. ".cpJob")
    end
end

function CpAITerraformingWorker:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAITerraformingWorker
    spec.cpJob:saveToXMLFile(xmlFile, baseKey .. ".cpJob")
end

function CpAITerraformingWorker:onReadStream(streamId, connection)
    local spec = self.spec_cpAITerraformingWorker
    spec.cpJob:readStream(streamId, connection)
end

function CpAITerraformingWorker:onWriteStream(streamId, connection)
    local spec = self.spec_cpAITerraformingWorker
    spec.cpJob:writeStream(streamId, connection)
end

function CpAITerraformingWorker:onUpdate(dt)
    local spec = self.spec_cpAITerraformingWorker
end

function CpAITerraformingWorker:getCanStartCpTerraformingWorker()
    local machine = g_machineManager:getMachineByObject(self)
    return machine and machine.enabled
end

function CpAITerraformingWorker:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpTerraformingWorker()
end

function CpAITerraformingWorker:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAITerraformingWorker
    if isStartedByHud and self:cpIsHudTerraformingJobSelected() then
        return self:getCanStartCpTerraformingWorker() and spec.cpJob
    end
    return superFunc(self, isStartedByHud) or
    not isStartedByHud and self:getCanStartCpTerraformingWorker() and spec.cpJob
end

function CpAITerraformingWorker:getCpTerraformingWorkerJobParameters()
    local spec = self.spec_cpAITerraformingWorker
    return spec.cpJob:getCpJobParameters()
end

function CpAITerraformingWorker:applyCpTerraformingWorkerJobParameters(job)
    local spec = self.spec_cpAITerraformingWorker
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

function CpAITerraformingWorker:getCpTerraformingWorkerJob()
    local spec = self.spec_cpAITerraformingWorker
    return spec.cpJob
end

--- Starts the cp driver at the first waypoint.
function CpAITerraformingWorker:startCpAtFirstWp(superFunc, ...)
    if not superFunc(self, ...) then
        if self:getCanStartCpTerraformingWorker() then
            local spec = self.spec_cpAITerraformingWorker
            spec.cpJob:applyCurrentState(self, g_currentMission, g_currentMission.player.farmId, true)
            spec.cpJob:setValues()
            local success = spec.cpJob:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJob, self:getOwnerFarmId()))
                return true
            end
        end
    else
        return true
    end
end

--- Starts the cp driver at the last driven waypoint.
function CpAITerraformingWorker:startCpAtLastWp(superFunc, ...)
    if not superFunc(self, ...) then
        if self:getCanStartCpTerraformingWorker() then
            local spec = self.spec_cpAITerraformingWorker
            spec.cpJob:applyCurrentState(self, g_currentMission, g_currentMission.player.farmId, true)
            spec.cpJob:setValues()
            local success = spec.cpJob:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJob, self:getOwnerFarmId()))
                return true
            end
        end
    else
        return true
    end
end
