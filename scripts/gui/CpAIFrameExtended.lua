CpInGameMenuAIFrameExtended = {}
CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR = 10
CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER = 11
--- Adds the course generate button in the ai menu page.

CpInGameMenuAIFrameExtended.positionUvs = GuiUtils.getUVs({
	760,
	4,
	100,
	100
}, AITargetHotspot.FILE_RESOLUTION)

CpInGameMenuAIFrameExtended.curDrawPositions={}
CpInGameMenuAIFrameExtended.drawDelay = g_updateLoopIndex
CpInGameMenuAIFrameExtended.DELAY = 1 
CpInGameMenuAIFrameExtended.hotspotFilterState = {}
CpInGameMenuAIFrameExtended.validCustomFieldCreationHotspots = {
	--- Hotspots visible, while drawing a custom field border.
	MapHotspot.CATEGORY_FIELD,
--	MapHotspot.CATEGORY_UNLOADING,
--	MapHotspot.CATEGORY_LOADING,
--	MapHotspot.CATEGORY_PRODUCTION,
	MapHotspot.CATEGORY_AI,
	MapHotspot.CATEGORY_COMBINE,
	MapHotspot.CATEGORY_STEERABLE,
	MapHotspot.CATEGORY_PLAYER,
--	MapHotspot.CATEGORY_SHOP,
--	MapHotspot.CATEGORY_OTHER
	CustomFieldHotspot.CATEGORY
}

function CpInGameMenuAIFrameExtended:onAIFrameLoadMapFinished()

	CpInGameMenuAIFrameExtended.setupButtons(self)		

	self:registerControls({"multiTextOptionPrefab","subTitlePrefab","courseGeneratorLayoutElements",
							"courseGeneratorLayout","courseGeneratorHeader","drawingCustomFieldHeader",
							"vineCourseGeneratorLayoutElements"})

	--- TODO: Figure out the correct implementation for Issues #1015 & #1457.
	local element = self:getDescendantByName("ingameMenuAI")

	local xmlFile = loadXMLFile("Temp", Utils.getFilename("config/gui/CourseGeneratorSettingsFrame.xml",Courseplay.BASE_DIRECTORY))
	g_gui:loadGuiRec(xmlFile, "CourseGeneratorLayout", element, self)
	delete(xmlFile)
	self:exposeControlsAsFields()
	self.courseGeneratorLayout:onGuiSetupFinished()
--	element:applyScreenAlignment()
	element:updateAbsolutePosition()

	self.drawingCustomFieldHeader:setVisible(false)
	self.drawingCustomFieldHeader:setText(g_i18n:getText("CP_customFieldManager_draw_header"))

	self.subTitlePrefab:unlinkElement()
	FocusManager:removeElement(self.subTitlePrefab)
	self.multiTextOptionPrefab:unlinkElement()
	FocusManager:removeElement(self.multiTextOptionPrefab)

	--- Vine course generator layout
	local settingsBySubTitle = CpCourseGeneratorSettings.getVineSettingSetup()
	CpSettingsUtil.generateGuiElementsFromSettingsTable(settingsBySubTitle,
	self.vineCourseGeneratorLayoutElements,self.multiTextOptionPrefab, self.subTitlePrefab)
	self.vineCourseGeneratorLayoutElements:setVisible(false)
	self.vineCourseGeneratorLayoutElements:setDisabled(true)
	self.vineCourseGeneratorLayoutElements:invalidateLayout()
	--- Default course generator layout
	local settingsBySubTitle = CpCourseGeneratorSettings.getSettingSetup()
	CpSettingsUtil.generateGuiElementsFromSettingsTable(settingsBySubTitle,
	self.courseGeneratorLayoutElements,self.multiTextOptionPrefab, self.subTitlePrefab)
	self.courseGeneratorLayoutElements:setVisible(false)
	self.courseGeneratorLayoutElements:setDisabled(true)
	self.courseGeneratorLayoutElements:invalidateLayout()

	self.courseGeneratorLayout:setVisible(false)
	--- Makes the last selected hotspot is not sold before reopening.
	local function validateCurrentHotspot(currentMission,hotspot)
		local page = currentMission.inGameMenu.pageAI
		if page and hotspot then 
			if hotspot == page.currentHotspot or hotspot == page.lastHotspot then 
				page.currentHotspot = nil
				page.lastHotspot = nil
				page:setMapSelectionItem(nil)
				currentMission.inGameMenu:updatePages()
			end
		end
	end
	g_currentMission.removeMapHotspot = Utils.appendedFunction(g_currentMission.removeMapHotspot,validateCurrentHotspot)

	local function onCloseInGameMenu(inGameMenu)
		inGameMenu.pageAI.lastVehicle = nil
		inGameMenu.pageAI.hudVehicle = nil
		inGameMenu.pageAI.currentHotspot = nil
	end
	--- Reloads the current vehicle on opening the in game menu.
	local function onOpenInGameMenu(inGameMenu)
		local pageAI = inGameMenu.pageAI
		if CpInGameMenuAIFrameExtended.getVehicle() == nil then 
			pageAI.lastVehicle = g_currentMission.controlledVehicle
		end
	end
	g_messageCenter:subscribe(MessageType.GUI_AFTER_CLOSE, onCloseInGameMenu, g_currentMission.inGameMenu)
	g_messageCenter:subscribe(MessageType.GUI_BEFORE_OPEN, onOpenInGameMenu, g_currentMission.inGameMenu)
	--- Closes the course generator settings with the back button.
	local function onClickBack(pageAI,superFunc)
		if pageAI.mode == CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR then 
			pageAI:onClickOpenCloseCourseGenerator()
			return
		end
		if pageAI.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER then 
			pageAI:onClickCreateFieldBorder()
			return
		end
		CpInGameMenuAIFrameExtended.resetHotspots(self)
		return superFunc(pageAI)
	end 
	self.buttonBack.onClickCallback = Utils.overwrittenFunction(self.buttonBack.onClickCallback,onClickBack)
	self.ingameMapBase.drawHotspotsOnly = Utils.appendedFunction(self.ingameMapBase.drawHotspotsOnly , CpInGameMenuAIFrameExtended.draw)

	--- Adds a second map hotspot for field position.
	self.fieldSiloAiTargetMapHotspot = AITargetHotspot.new()
	self.fieldSiloAiTargetMapHotspot.icon:setUVs(CpInGameMenuAIFrameExtended.positionUvs) --- Without angle
	
	self.unloadAiTargetMapHotspot = AITargetHotspot.new()

	self.ingameMap.onClickHotspotCallback = Utils.appendedFunction(self.ingameMap.onClickHotspotCallback,
			CpInGameMenuAIFrameExtended.onClickHotspot)
	
	--- Draws the current progress, while creating a custom field.
	self.customFieldPlot = FieldPlot(true)
end
InGameMenuAIFrame.onLoadMapFinished = Utils.appendedFunction(InGameMenuAIFrame.onLoadMapFinished,
		CpInGameMenuAIFrameExtended.onAIFrameLoadMapFinished)

function CpInGameMenuAIFrameExtended:setupButtons()
	local function createBtn(prefab, text, callback)
		local btn = prefab:clone(prefab.parent)
		btn:setText(g_i18n:getText(text))
		btn:setVisible(false)
		btn:setCallback("onClickCallback", callback)
		btn.parent:invalidateLayout()
		return btn
	end

	self.buttonGenerateCourse = createBtn(self.buttonCreateJob,
											"CP_ai_page_generate_course",
											"onClickGenerateFieldWorkCourse")

	self.buttonOpenCourseGenerator = createBtn(self.buttonGotoJob,
											"CP_ai_page_open_course_generator",
											"onClickOpenCloseCourseGenerator")

	self.buttonDeleteCustomField = createBtn(self.buttonCreateJob,
											"CP_customFieldManager_delete",
											"onClickDeleteCustomField")	

	self.buttonRenameCustomField = createBtn(self.buttonGotoJob,
											"CP_customFieldManager_rename",
											"onClickRenameCustomField")	
											
	self.buttonEditCustomField = createBtn(self.buttonStartJob,
											"CP_customFieldManager_edit",
											"onClickEditCustomField")	

	self.buttonDrawFieldBorder = createBtn(self.buttonGotoJob,
											"CP_customFieldManager_draw",
											"onClickCreateFieldBorder")			
end

--- Updates the generate button visibility in the ai menu page.
function CpInGameMenuAIFrameExtended:updateContextInputBarVisibility()
	local isPaused = g_currentMission.paused
	
	if self.buttonGenerateCourse then
		self.buttonGenerateCourse:setVisible(CpInGameMenuAIFrameExtended.getCanGenerateCourse(self))
	end
	if self.buttonOpenCourseGenerator then
		self.buttonOpenCourseGenerator:setVisible(CpInGameMenuAIFrameExtended.getCanOpenCloseCourseGenerator(self))
	end
	self.buttonBack:setVisible(self:getCanGoBack() or 
								self.mode == CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR or 
								self.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER)
	
	self.buttonDeleteCustomField:setVisible(self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot))
	self.buttonRenameCustomField:setVisible(self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot))
	self.buttonEditCustomField:setVisible(self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot))

	self.buttonDrawFieldBorder:setVisible(CpInGameMenuAIFrameExtended.isCreateFieldBorderBtnVisible(self))
	self.buttonDrawFieldBorder:setText(
		self.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER and g_i18n:getText("CP_customFieldManager_save") or 
		g_i18n:getText("CP_customFieldManager_draw")
	)
	
	self.buttonGotoJob.parent:invalidateLayout()
end

InGameMenuAIFrame.updateContextInputBarVisibility = Utils.appendedFunction(InGameMenuAIFrame.updateContextInputBarVisibility,CpInGameMenuAIFrameExtended.updateContextInputBarVisibility)

function CpInGameMenuAIFrameExtended:isCreateFieldBorderBtnVisible()
	local visible = self.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER or 
					self.mode == InGameMenuAIFrame.MODE_OVERVIEW and self.currentHotspot == nil

	return visible
end

--- Button callback of the ai menu button.
function InGameMenuAIFrame:onClickGenerateFieldWorkCourse()
	if CpInGameMenuAIFrameExtended.getCanGenerateCourse(self) then 
		CpUtil.try(self.currentJob.onClickGenerateFieldWorkCourse, self.currentJob)
	end
end

--- Disables the start job button, if cp is active.
function CpInGameMenuAIFrameExtended:getCanStartJob(superFunc,...)
	local vehicle = InGameMenuMapUtil.getHotspotVehicle(self.currentHotspot)
	if vehicle and vehicle.getIsCpActive and vehicle:getIsCpActive() then
		return self.currentJob and self.currentJob.getCanStartJob and self.currentJob:getCanStartJob() and superFunc(self,...)
	end 
	return superFunc(self,...)
end
InGameMenuAIFrame.getCanStartJob = Utils.overwrittenFunction(InGameMenuAIFrame.getCanStartJob,CpInGameMenuAIFrameExtended.getCanStartJob)

function CpInGameMenuAIFrameExtended:getCanGenerateCourse()
	return self.mode == CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR and self.currentJob and self.currentJob.getCanGenerateFieldWorkCourse and self.currentJob:getCanGenerateFieldWorkCourse()
end

function CpInGameMenuAIFrameExtended:getCanOpenCloseCourseGenerator()
	local vehicle = InGameMenuMapUtil.getHotspotVehicle(self.currentHotspot)
	local visible = vehicle ~= nil and self.currentJob and self.currentJob.isCourseGenerationAllowed and self.currentJob:isCourseGenerationAllowed()
	return visible and self.mode ~= InGameMenuAIFrame.MODE_OVERVIEW and not self:getIsPicking()
end

function InGameMenuAIFrame:onClickOpenCloseCourseGenerator()
	if CpInGameMenuAIFrameExtended.getCanOpenCloseCourseGenerator(self) then 
		if self.mode == CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR then 
			self.courseGeneratorLayout:setVisible(false)
			self.contextBox:setVisible(true)
			self:toggleMapInput(true)
			self.ingameMap:onOpen()
			self.ingameMap:registerActionEvents()
			self.mode = InGameMenuAIFrame.MODE_CREATE
			self:setJobMenuVisible(true)
			self.currentJob:getCpJobParameters():validateSettings()
			CpSettingsUtil.updateAiParameters(self.currentJobElements)
			CpInGameMenuAIFrameExtended.unbindCourseGeneratorSettings(self)
			self:updateParameterValueTexts()
		else
			self.mode = CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR
			self.courseGeneratorLayout:setVisible(true)
			self:toggleMapInput(false)
			self:setJobMenuVisible(false)
			self.contextBox:setVisible(false)
			CpInGameMenuAIFrameExtended.updateCourseGeneratorSettings(self)
		end
	end
end

function CpInGameMenuAIFrameExtended:bindCourseGeneratorSettings()
	local vehicle = InGameMenuMapUtil.getHotspotVehicle(self.currentHotspot)
	if vehicle ~=nil and vehicle.getCourseGeneratorSettings then
		CpUtil.debugVehicle( CpUtil.DBG_HUD,vehicle, "binding course generator settings." ) 
		vehicle:validateCourseGeneratorSettings()
		self.settings = vehicle:getCourseGeneratorSettingsTable()
		local settingsBySubTitle, title = CpCourseGeneratorSettings.getSettingSetup(vehicle)
		CpSettingsUtil.linkGuiElementsAndSettings(self.settings,self.courseGeneratorLayoutElements,settingsBySubTitle,vehicle)
	
		self.vineSettings = vehicle:getCpVineSettingsTable()
		local settingsBySubTitle, vineTitle = CpCourseGeneratorSettings.getSettingSetup(vehicle)
		CpSettingsUtil.linkGuiElementsAndSettings(self.vineSettings,self.vineCourseGeneratorLayoutElements,settingsBySubTitle,vehicle)

		if self.currentJob:hasFoundVines() then 
			self.vineCourseGeneratorLayoutElements:setVisible(true)
			self.vineCourseGeneratorLayoutElements:setDisabled(false)
			self.courseGeneratorHeader:setText(vineTitle)
		else 
			self.courseGeneratorLayoutElements:setVisible(true)
			self.courseGeneratorLayoutElements:setDisabled(false)
			self.courseGeneratorHeader:setText(title)
		end
	end
end

function CpInGameMenuAIFrameExtended:updateCourseGeneratorSettings(unbind)
	if self.courseGeneratorLayout and self.courseGeneratorLayout:getIsVisible() then 
		if unbind then 
			CpInGameMenuAIFrameExtended.unbindCourseGeneratorSettings(self)
		end
		CpInGameMenuAIFrameExtended.bindCourseGeneratorSettings(self)
		local layout 
		if self.currentJob:hasFoundVines() then 
			layout = self.vineCourseGeneratorLayoutElements
		else 
			layout = self.courseGeneratorLayoutElements
		end
		FocusManager:loadElementFromCustomValues(layout)
		layout:invalidateLayout()
		if FocusManager:getFocusedElement() == nil then
			self:setSoundSuppressed(true)
			FocusManager:setFocus(layout)
			self:setSoundSuppressed(false)
		end
	end
end

function CpInGameMenuAIFrameExtended:unbindCourseGeneratorSettings()
	if self.settings then
		CpSettingsUtil.unlinkGuiElementsAndSettings(self.settings,self.courseGeneratorLayoutElements)
		self.courseGeneratorLayoutElements:invalidateLayout()
	end
	if self.vineSettings then
		CpSettingsUtil.unlinkGuiElementsAndSettings(self.vineSettings,self.vineCourseGeneratorLayoutElements)
		self.vineCourseGeneratorLayoutElements:invalidateLayout()
	end
	self.vineCourseGeneratorLayoutElements:setVisible(false)
	self.vineCourseGeneratorLayoutElements:setDisabled(true)
	self.courseGeneratorLayoutElements:setVisible(false)
	self.courseGeneratorLayoutElements:setDisabled(true)
end

--- Updates the visibility of the vehicle settings on select/unselect of a vehicle in the ai menu page.
--- Also updates the field position map hotspot.
function CpInGameMenuAIFrameExtended:setMapSelectionItem(hotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.aiTargetMapHotspot)
	if hotspot ~= nil then
		local vehicle = InGameMenuMapUtil.getHotspotVehicle(hotspot)
		self.lastVehicle = vehicle
		self.hudVehicle = nil
		if vehicle then 
			if vehicle.getJob ~= nil then
				local job = vehicle:getJob()

				if job ~= nil then
					if job.getCpJobParameters ~= nil then
						local parameters = job:getCpJobParameters():getAiTargetMapHotspotParameters()
						for i, param in pairs(parameters) do 
							if param:is_a(CpAIParameterPosition) then
								if param:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.DRIVE_TO then 
									if param:applyToMapHotspot(self.aiTargetMapHotspot) then 
										g_currentMission:addMapHotspot(self.aiTargetMapHotspot)
									end
								elseif param:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
									if param:applyToMapHotspot(self.fieldSiloAiTargetMapHotspot) then
										g_currentMission:addMapHotspot(self.fieldSiloAiTargetMapHotspot)
									end
								elseif param:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
									if param:applyToMapHotspot(self.unloadAiTargetMapHotspot) then
										g_currentMission:addMapHotspot(self.unloadAiTargetMapHotspot)
									end
								end
							elseif param:is_a(CpAIParameterUnloadingStation) then 
								g_currentMission:removeMapHotspot(self.aiUnloadingMarkerHotspot)
								if param:applyToMapHotspot(self.aiUnloadingMarkerHotspot) then 
									g_currentMission:addMapHotspot(self.aiUnloadingMarkerHotspot)
								end
							end
						end
					end
					if job.getTarget ~= nil then
						local x, z, rot = job:getTarget()

						self.aiTargetMapHotspot:setWorldPosition(x, z)

						if rot ~= nil then
							self.aiTargetMapHotspot:setWorldRotation(rot + math.pi)
						end

						g_currentMission:addMapHotspot(self.aiTargetMapHotspot)
					end
				end

			end
		end
	end
	g_currentMission.inGameMenu:updatePages()
end
InGameMenuAIFrame.setMapSelectionItem = Utils.appendedFunction(InGameMenuAIFrame.setMapSelectionItem, CpInGameMenuAIFrameExtended.setMapSelectionItem)


function CpInGameMenuAIFrameExtended:onAIFrameOpen()
	if self.mode == CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR then 
		self.contextBox:setVisible(false)
	end
	CpInGameMenuAIFrameExtended.addMapHotSpots(self)
	g_customFieldManager:refresh()
	self.drawingCustomFieldHeader:setVisible(false)
	local vehicle = InGameMenuMapUtil.getHotspotVehicle(self.currentHotspot)
	self.lastVehicle = vehicle
	g_currentMission.inGameMenu:updatePages()
end
InGameMenuAIFrame.onFrameOpen = Utils.appendedFunction(InGameMenuAIFrame.onFrameOpen, CpInGameMenuAIFrameExtended.onAIFrameOpen)

function CpInGameMenuAIFrameExtended:addMapHotSpots()
	self.ingameMapBase:setHotspotFilter(CustomFieldHotspot.CATEGORY, true)
end
InGameMenuMapFrame.onFrameOpen = Utils.appendedFunction(InGameMenuMapFrame.onFrameOpen, CpInGameMenuAIFrameExtended.addMapHotSpots)

function CpInGameMenuAIFrameExtended:onAIFrameClose()
	self.courseGeneratorLayout:setVisible(false)
	self.contextBox:setVisible(true)
	self.lastHotspot = self.currentHotspot
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	CpInGameMenuAIFrameExtended.unbindCourseGeneratorSettings(self)
	g_currentMission.inGameMenu:updatePages()
end
InGameMenuAIFrame.onFrameClose = Utils.appendedFunction(InGameMenuAIFrame.onFrameClose,CpInGameMenuAIFrameExtended.onAIFrameClose)

function CpInGameMenuAIFrameExtended:onCreateJob()
	if not g_currentMission.paused then
		if CpInGameMenuAIFrameExtended.getCanGenerateCourse(self) then 
			self:onClickGenerateFieldWorkCourse()
		end
	end
end
InGameMenuAIFrame.onCreateJob = Utils.appendedFunction(InGameMenuAIFrame.onCreateJob,CpInGameMenuAIFrameExtended.onCreateJob)

function CpInGameMenuAIFrameExtended:onStartGoToJob()
	if not g_currentMission.paused then
		if CpInGameMenuAIFrameExtended.getCanOpenCloseCourseGenerator(self) then
			self:onClickOpenCloseCourseGenerator()
		end
	end
end
InGameMenuAIFrame.onStartGoToJob = Utils.appendedFunction(InGameMenuAIFrame.onStartGoToJob,CpInGameMenuAIFrameExtended.onStartGoToJob)

-- this is appended to ingameMapBase.drawHotspotsOnly so self is the ingameMapBase!
function CpInGameMenuAIFrameExtended:draw()	
	local areCursePlotsAlwaysVisible = g_Courseplay.globalSettings:getSettings().showsAllActiveCourses:getValue()
	local vehicle = InGameMenuMapUtil.getHotspotVehicle(self.selectedHotspot)
	if areCursePlotsAlwaysVisible then
		local vehicles = g_assignedCoursesManager:getRegisteredVehicles()
		for _, v in pairs(vehicles) do
			if g_currentMission.accessHandler:canPlayerAccess(v) then
				v:drawCpCoursePlot(self)
			end
		end
	elseif vehicle and vehicle.drawCpCoursePlot  then 
		vehicle:drawCpCoursePlot(self)
	end
	-- show the custom fields on the AI map
	g_customFieldManager:draw(self)
	-- show the selected field on the AI screen map when creating a job
	local pageAI = g_currentMission.inGameMenu.pageAI
	local job = pageAI.currentJob
	if pageAI.mode == InGameMenuAIFrame.MODE_CREATE or 
		   pageAI.mode == CpInGameMenuAIFrameExtended.MODE_COURSE_GENERATOR then
		if job and job.drawSelectedField then
			job:drawSelectedField(self)
		end
		if job and job.drawSilos then 
			job:drawSilos(self)
		end
	end

	--- Draws the current progress, while creating a custom field.
	if pageAI.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER and next(CpInGameMenuAIFrameExtended.curDrawPositions) then
		pageAI.customFieldPlot:setWaypoints(CpInGameMenuAIFrameExtended.curDrawPositions)
		pageAI.customFieldPlot:draw(self,true)
		pageAI.customFieldPlot:setVisible(true)
	end
end

function CpInGameMenuAIFrameExtended:delete()
	if self.fieldSiloAiTargetMapHotspot ~= nil then
		self.fieldSiloAiTargetMapHotspot:delete()

		self.fieldSiloAiTargetMapHotspot = nil
	end

	if self.unloadAiTargetMapHotspot ~= nil then
		self.unloadAiTargetMapHotspot:delete()

		self.unloadAiTargetMapHotspot = nil
	end
end
InGameMenuAIFrame.delete = Utils.appendedFunction(InGameMenuAIFrame.delete,CpInGameMenuAIFrameExtended.delete)

--- Ugly hack to swap the main AI hotspot with the field position hotspot,
--- as only the main hotspot can be moved by the player.
function CpInGameMenuAIFrameExtended:startPickingPosition(superFunc, parameter, callback, ...)
	
	if parameter and parameter.getPositionType then
		CpInGameMenuAIFrameExtended.resetHotspots(self)
		if parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
			local mapHotspot = self.aiTargetMapHotspot
			self.aiTargetMapHotspot = self.fieldSiloAiTargetMapHotspot
			self.fieldSiloAiTargetMapHotspot = mapHotspot
			self.currentPickingMapHotspotType = CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO
		elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
			local mapHotspot = self.aiTargetMapHotspot
			self.aiTargetMapHotspot = self.unloadAiTargetMapHotspot
			self.unloadAiTargetMapHotspot = mapHotspot
			self.currentPickingMapHotspotType = CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD
		end
	end
	callback = Utils.appendedFunction(callback,function (finished, x, z)
		CpInGameMenuAIFrameExtended.resetHotspots(self)
	end)

	superFunc(self, parameter, callback, ...)
end
InGameMenuAIFrame.startPickPosition = Utils.overwrittenFunction(InGameMenuAIFrame.startPickPosition,CpInGameMenuAIFrameExtended.startPickingPosition)
InGameMenuAIFrame.startPickPositionAndRotation = Utils.overwrittenFunction(InGameMenuAIFrame.startPickPositionAndRotation,CpInGameMenuAIFrameExtended.startPickingPosition)

function CpInGameMenuAIFrameExtended:resetHotspots()
	if self.currentPickingMapHotspotType == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
		local mapHotspot = self.aiTargetMapHotspot
		self.aiTargetMapHotspot = self.fieldSiloAiTargetMapHotspot
		self.fieldSiloAiTargetMapHotspot = mapHotspot
		self.currentPickingMapHotspotType = nil
	elseif self.currentPickingMapHotspotType == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
		local mapHotspot = self.aiTargetMapHotspot
		self.aiTargetMapHotspot = self.unloadAiTargetMapHotspot
		self.unloadAiTargetMapHotspot = mapHotspot
		self.currentPickingMapHotspotType = nil
	end
end


--- Added support for the cp field target position.
function CpInGameMenuAIFrameExtended:updateParameterValueTexts(superFunc, ...)
	if self.currentJobElements == nil then 
		return
	end
	g_currentMission:removeMapHotspot(self.aiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.aiLoadingMarkerHotspot)
	g_currentMission:removeMapHotspot(self.aiUnloadingMarkerHotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	for _, element in ipairs(self.currentJobElements) do
		local parameter = element.aiParameter
		local parameterType = parameter:getType()

		if parameterType == AIParameterType.TEXT then
			local title = element:getDescendantByName("title")

			title:setText(parameter:getString())
		elseif parameter.is_a and parameter:is_a(CpAIParameterPosition) then 
			element:setText(parameter:getString())
			if parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.DRIVE_TO then 
				if parameter:applyToMapHotspot(self.aiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.aiTargetMapHotspot)
				end
			elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
				if parameter:applyToMapHotspot(self.fieldSiloAiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.fieldSiloAiTargetMapHotspot)
				end
			elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
				if parameter:applyToMapHotspot(self.unloadAiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.unloadAiTargetMapHotspot)
				end
			end
		elseif parameterType == AIParameterType.POSITION or parameterType == AIParameterType.POSITION_ANGLE then
			element:setText(parameter:getString())

			g_currentMission:addMapHotspot(self.aiTargetMapHotspot)

			local x, z = parameter:getPosition()

			self.aiTargetMapHotspot:setWorldPosition(x, z)

			if parameterType == AIParameterType.POSITION_ANGLE then
				local angle = parameter:getAngle() + math.pi

				self.aiTargetMapHotspot:setWorldRotation(angle)
			end
		else
			element:updateTitle()

			if parameterType == AIParameterType.UNLOADING_STATION then
				if parameter:applyToMapHotspot(self.aiUnloadingMarkerHotspot) then 
					g_currentMission:addMapHotspot(self.aiUnloadingMarkerHotspot)
				end
			elseif parameterType == AIParameterType.LOADING_STATION then
				local loadingStation = parameter:getLoadingStation()

				if loadingStation ~= nil and parameter:getCanBeChanged() then
					local placeable = loadingStation.owningPlaceable

					if placeable ~= nil and placeable.getHotspot ~= nil then
						local hotspot = placeable:getHotspot(1)

						if hotspot ~= nil then
							local x, z = hotspot:getWorldPosition()

							self.aiLoadingMarkerHotspot:setWorldPosition(x, z)
							g_currentMission:addMapHotspot(self.aiLoadingMarkerHotspot)
						end
					end
				end
			end
		end

		element:setDisabled(not parameter:getCanBeChanged())
	end
end
InGameMenuAIFrame.updateParameterValueTexts = Utils.overwrittenFunction(InGameMenuAIFrame.updateParameterValueTexts,
															CpInGameMenuAIFrameExtended.updateParameterValueTexts)

--- Enables clickable field hotspots.
function CpInGameMenuAIFrameExtended:onClickHotspot(element,hotspot)
	if hotspot then 
		local pageAI = g_currentMission.inGameMenu.pageAI
		if hotspot:isa(FieldHotspot) and pageAI.mode == InGameMenuAIFrame.MODE_OVERVIEW then 
			InGameMenuMapUtil.showContextBox(pageAI.contextBox, hotspot, hotspot:getAreaText())
			self.currentHotspot = hotspot
		end
	end
end

function InGameMenuAIFrame:onClickDeleteCustomField()
	local hotspot = self.currentHotspot
	if hotspot and hotspot:isa(CustomFieldHotspot) then 
		hotspot:onClickDelete()
	end
end

function InGameMenuAIFrame:onClickRenameCustomField()
	local hotspot = self.currentHotspot
	if hotspot and hotspot:isa(CustomFieldHotspot) then 
		hotspot:onClickRename()
	end
end

function InGameMenuAIFrame:onClickEditCustomField()
	local hotspot = self.currentHotspot
	if hotspot and hotspot:isa(CustomFieldHotspot) then 
		hotspot:onClickEdit()
	end
end

--- Activate/deactivate the custom field drawing mode.
function InGameMenuAIFrame:onClickCreateFieldBorder()
	if self.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER then 
		self.mode = InGameMenuAIFrame.MODE_OVERVIEW
		self.drawingCustomFieldHeader:setVisible(false)
		g_customFieldManager:addField(CpInGameMenuAIFrameExtended.curDrawPositions)
		CpInGameMenuAIFrameExtended.curDrawPositions = {}
		--- Restore hotspot filters here:
		for k, v in pairs(self.ingameMapBase.filter) do
			self.ingameMapBase:setHotspotFilter(k, CpInGameMenuAIFrameExtended.hotspotFilterState[k])
		end

	else
		CpInGameMenuAIFrameExtended.curDrawPositions = {}
		self.drawingCustomFieldHeader:setVisible(true)
		self.mode = CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER 
		CpInGameMenuAIFrameExtended.hotspotFilterState = {}
		--- Change the hotspot filter here:
		for k, v in pairs(self.ingameMapBase.filter) do
			CpInGameMenuAIFrameExtended.hotspotFilterState[k] = v

			self.ingameMapBase:setHotspotFilter(k, false)
		end
		for _,v in ipairs(CpInGameMenuAIFrameExtended.validCustomFieldCreationHotspots) do
			self.ingameMapBase:setHotspotFilter(v, true)
		end
	end
end

--- Enables drawing custom field borders in the in game menu with the right mouse btn.
function CpInGameMenuAIFrameExtended:mouseEvent(superFunc,posX, posY, isDown, isUp, button, eventUsed)
	if self.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER then
		local localX, localY = self.ingameMap:getLocalPosition(posX, posY)
		local worldX, worldZ = self.ingameMap:localToWorldPos(localX, localY)
		if button == Input.MOUSE_BUTTON_RIGHT then 
			if isUp and g_updateLoopIndex > CpInGameMenuAIFrameExtended.drawDelay then 
				if #CpInGameMenuAIFrameExtended.curDrawPositions > 0 then
					--- Makes sure that waypoints are inserted between long lines,
					--- as the coursegenerator depends on these.
					local pos = CpInGameMenuAIFrameExtended.curDrawPositions[#CpInGameMenuAIFrameExtended.curDrawPositions]
					local dx,dz,length = CpMathUtil.getPointDirection( pos, {x = worldX, z = worldZ})
					for i=3, length-3, 3 do 
						table.insert(CpInGameMenuAIFrameExtended.curDrawPositions, 
						{x = pos.x + dx * i,
							z =  pos.z + dz * i})
					end
				end
				table.insert(CpInGameMenuAIFrameExtended.curDrawPositions, {x = worldX, z = worldZ})
				CpInGameMenuAIFrameExtended.drawDelay = g_updateLoopIndex + CpInGameMenuAIFrameExtended.DELAY
			end
		end
	end
	return superFunc(self,posX, posY, isDown, isUp, button, eventUsed)
end
InGameMenuAIFrame.mouseEvent = Utils.overwrittenFunction(InGameMenuAIFrame.mouseEvent,CpInGameMenuAIFrameExtended.mouseEvent)

function CpInGameMenuAIFrameExtended.getVehicle()
	local pageAI = g_currentMission.inGameMenu.pageAI
	local vehicle = InGameMenuMapUtil.getHotspotVehicle(pageAI.currentHotspot) or pageAI.lastVehicle or pageAI.hudVehicle
	if vehicle ~=nil and vehicle:isa(Vehicle) then 
		return vehicle
	end
end