local modName = CpAITerraformer and CpAITerraformer.MOD_NAME -- for reload

--- Specialization for the silo loader job
--- Used for shovel loader and big silo loader, like the Ropa NarwaRo.
---@class CpAITerraformer
CpAITerraformer = {}

CpAITerraformer.flattenHeightText = g_i18n:getText("CP_fieldWorkJobParameters_flattenHeight")

CpAITerraformer.MOD_NAME = g_currentModName or modName
CpAITerraformer.NAME = ".cpAITerraformer"
CpAITerraformer.SPEC_NAME = CpAITerraformer.MOD_NAME .. CpAITerraformer.NAME
CpAITerraformer.KEY = "." .. CpAITerraformer.MOD_NAME .. CpAITerraformer.NAME

function CpAITerraformer.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAITerraformer.KEY
    CpJobParameters.registerXmlSchema(schema, key .. ".cpJob")
end

function CpAITerraformer.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations)
end

function CpAITerraformer.register(typeManager, typeName, specializations)
    if CpAITerraformer.prerequisitesPresent(specializations) then
        typeManager:addSpecialization(typeName, CpAITerraformer.SPEC_NAME)
    end
end

function CpAITerraformer.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAITerraformer)
    SpecializationUtil.registerEventListener(vehicleType, 'onUpdate', CpAITerraformer)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAITerraformer)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAITerraformer)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAITerraformer)
end

function CpAITerraformer.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpTerraformer",
        CpAITerraformer.getCanStartCpTerraformer)
    SpecializationUtil.registerFunction(vehicleType, "getCpTerraformerJobParameters",
        CpAITerraformer.getCpTerraformerJobParameters)

    SpecializationUtil.registerFunction(vehicleType, "applyCpTerraformerJobParameters",
        CpAITerraformer.applyCpTerraformerJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpTerraformerJob",
        CpAITerraformer.getCpTerraformerJob)
end

function CpAITerraformer.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAITerraformer.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob',
        CpAITerraformer.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp',
        CpAITerraformer.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAITerraformer
    .startCpAtLastWp)
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAITerraformer:onLoad(savegame)
    self.spec_cpAITerraformer = self["spec_" .. CpAITerraformer.SPEC_NAME]
    local spec = self.spec_cpAITerraformer
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.TERRAFORM_CP)
    spec.cpJob:setVehicle(self, true)
end

function CpAITerraformer:onLoadFinished(savegame)
    local spec = self.spec_cpAITerraformer
    if savegame ~= nil then
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key .. CpAITerraformer.KEY .. ".cpJob")
    end
end

function CpAITerraformer:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAITerraformer
    spec.cpJob:saveToXMLFile(xmlFile, baseKey .. ".cpJob")
end

function CpAITerraformer:onReadStream(streamId, connection)
    local spec = self.spec_cpAITerraformer
    spec.cpJob:readStream(streamId, connection)
end

function CpAITerraformer:onWriteStream(streamId, connection)
    local spec = self.spec_cpAITerraformer
    spec.cpJob:writeStream(streamId, connection)
end

function CpAITerraformer:onUpdate(dt)
    local spec = self.spec_cpAITerraformer
end

function CpAITerraformer:getCanStartCpTerraformer()
    local terraFarm = FS22_TerraFarm_MCE and FS22_TerraFarm_MCE.TerraFarm

    if terraFarm == nil then
        print("TerraFarm is nil")
        return false
    end

    if terraFarm.getMachineManager() == nil then
        print("TerraFarm.getMachineManager() is nil")
        return false
    end

    local machine = terraFarm.getMachineManager():getMachineByObject(self)
    return machine ~= nil
end

function CpAITerraformer:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpTerraformer()
end

function CpAITerraformer:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAITerraformer
    if isStartedByHud and self:cpIsHudTerraformingJobSelected() then
        return self:getCanStartCpTerraformer() and spec.cpJob
    end
    return superFunc(self, isStartedByHud) or
    not isStartedByHud and self:getCanStartCpTerraformer() and spec.cpJob
end

function CpAITerraformer:getCpTerraformerJobParameters()
    local spec = self.spec_cpAITerraformer
    return spec.cpJob:getCpJobParameters()
end

function CpAITerraformer:applyCpTerraformerJobParameters(job)
    local spec = self.spec_cpAITerraformer
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

function CpAITerraformer:getCpTerraformerJob()
    local spec = self.spec_cpAITerraformer
    return spec.cpJob
end

--- Starts the cp driver at the first waypoint.
function CpAITerraformer:startCpAtFirstWp(superFunc, ...)
    if not superFunc(self, ...) then
        if self:getCanStartCpTerraformer() then
            local spec = self.spec_cpAITerraformer
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
function CpAITerraformer:startCpAtLastWp(superFunc, ...)
    if not superFunc(self, ...) then
        if self:getCanStartCpTerraformer() then
            local spec = self.spec_cpAITerraformer
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
