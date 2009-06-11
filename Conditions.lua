local function returnTrue() return true end

-- There should be a cleaner way to handle this
local hookenv = setmetatable({}, {__index = getfenv(0)})
function hookenv.LoadAddOn(name)
	return AddonLoader:LoadAddOn(name)
end

local delayFrame -- will be filled if needed with a frame for loading addons delayed.
local BZ -- will be a reference to babble-zone-3.0 if needed

function AddonLoader:RemoveInterfaceOptions(name)
	for k, f in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do
		if f == name or f.name == name then
			tremove(INTERFACEOPTIONS_ADDONCATEGORIES, k)
			break
		end
	end
end

local function optionsOnShow(self)
	if not IsAddOnLoaded(self.addon) then
		-- remove from options frame
		AddonLoader:RemoveInterfaceOptions(self)
		self:Hide()
		-- load addon
		AddonLoader:LoadAddOn(self.addon)
		-- refresh optionsframe
		InterfaceOptionsFrame_OpenToCategory(self.name)
	end
end

AddonLoader.conditions = {
	["X-LoadOn-Mailbox"] = {
		events = {"MAIL_SHOW"},
		handler = returnTrue
	},
	["X-LoadOn-AuctionHouse"] = {
		events = {"AUCTION_HOUSE_SHOW"},
		handler = returnTrue
	},
	["X-LoadOn-Bank"] = {
		events = {"BANKFRAME_OPENED"},
		handler = returnTrue
	},
	["X-LoadOn-Arena"] = {
		events = {"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD"},
		handler = function() return select(2, IsInInstance()) == "arena" end,
	},
	["X-LoadOn-Battleground"] = {
		events = {"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD"},
		handler = function() return select(2, IsInInstance()) == "pvp" end,
	},
	["X-LoadOn-Instance"] = {
		events = {"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD"},
		handler = function()
			local instanceType = select(2, IsInInstance())
			return instanceType == "party" or instanceType == "raid"
		end,
	},
	["X-LoadOn-Combat"] = {
		events = {"PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD"},
		handler = function( event, name, arg )
			if event == "PLAYER_REGEN_DISABLED" then return true end
			if event == "PLAYER_ENTERING_WORLD" then return InCombatLockdown() end
		end,
	},
	["X-LoadOn-Crafting"] = {
		events = {"TRADE_SKILL_SHOW", "CRAFT_SHOW"},
		handler = returnTrue,
	},
	["X-LoadOn-Group"] = {
		events = {"PARTY_MEMBERS_CHANGED","RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD"},
		handler = function() return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 end,
	},
	["X-LoadOn-Merchant"] = {
		events = {"MERCHANT_SHOW"},
		handler = returnTrue,
	},
	["X-LoadOn-PvPFlagged"] = {
		events = {"UNIT_FACTION", "PLAYER_ENTERING_WORLD"},
		handler = function() return UnitIsPVP("player") end,
	},
	["X-LoadOn-Raid"] = {
		events = {"RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD"},
		handler = function() return GetNumRaidMembers() > 0 end,
	},
	["X-LoadOn-Class"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg) return tostring(arg):upper() == select(2,UnitClass("player")) end,
	},
	["X-LoadOn-Realm"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg) return GetRealmName() == arg end,
	}, 
	["X-LoadOn-Guild"] = {
		events = {"PLAYER_LOGIN"},
		handler = function() return IsInGuild() end,
	},
	["X-LoadOn-Always"] = {
		events = {"PLAYER_LOGIN"},
		handler = function( event, name, arg )
			if not (arg or ""):lower():match("^delayed") then return true end
			-- delayed loading, one addon per second
			if not delayFrame then
				delayFrame = CreateFrame("Frame")
				delayFrame.addons = {}
				delayFrame.elapsed = 0
				delayFrame:SetScript("OnUpdate", function(self, elapsed)
					self.elapsed = self.elapsed + elapsed
					if self.elapsed >= 0.25 then
						self.elapsed = 0

						if next(self.addons) then
							for addon in pairs(self.addons) do
								AddonLoader:LoadAddOn(addon)
								self.addons[addon] = nil -- nuke from the list
								break
							end
						else
							self:Hide()
						end
					end
				end)
			end
			delayFrame.addons[name] = true
			delayFrame:Show()
		end,
	},
	["X-LoadOn-Resting"] = {
		events = {"PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD"},
		handler = function() return IsResting() end,
	},
	["X-LoadOn-NotResting"] = {
		events = {"PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD"},
		handler = function() return not IsResting() end,
	},
	["X-LoadOn-Level"] = {
		events = {"PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD"},
		handler = function(event, name, arg)
			local level = UnitLevel("player")
			for chunk in arg:gmatch('([%d%p^,]+)') do
				if tonumber(chunk) then -- '68'
					if level == tonumber(chunk) then return true end
				elseif chunk:match('%+') then -- '40+'
					if level >= tonumber(chunk:match('%d+')) then return true end
				elseif chunk:match('%-$') then -- '30-'
					if level <= tonumber(chunk:match('%d+')) then return true end
				elseif chunk:match('%d+%-%d+') then -- '20-47'
					local low, high = tonumber(chunk:match('(%d+)%-(%d+)'))
					if level >= low and level <= high then return true end
				end
			end
		end,
	},
	["X-LoadOn-Events"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg)
			for metaevent in arg:gmatch("[^ ,]+") do
				local meta
				local lookfor = "X-LoadOn-"..metaevent
				local conditiontext = AddonLoader.conditiontexts[name]
				for line in conditiontext:gmatch("[^\n]+") do
					local condname, text = string.match(line, "^([^:]*): (.*)$")
					if condname and text and condname == lookfor then
						meta = text
					end
				end
				if meta then
					local status, func, err = pcall(loadstring, meta)
					if func then
						setfenv(func, hookenv)
						if not AddonLoader.events[metaevent] then
							AddonLoader.events[metaevent] = {}
							AddonLoader.frame:RegisterEvent(metaevent)
						end
						if not AddonLoader.events[metaevent][name] then
							AddonLoader.events[metaevent][name] = {}
						end
						AddonLoader.events[metaevent][name][name..metaevent] = { -- name..metaevent to fake a unique condition name
							handler = func,
							arg = "",
						}
					else
						geterrorhandler()('## X-LoadOn-'..event..' ('..name..'): '..err)
					end
				end
			end
			-- We specifically DO NOT return true here, this handler just sets up the other conditions. And will remain dorment for the remainder
		end,
	},
	["X-LoadOn-Hooks"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg)
			for hook in arg:gmatch("[^ ,]+") do
				if type(_G[hook]) == "function" then
					local meta
					local lookfor = "X-LoadOn-"..hook
					local conditiontext = AddonLoader.conditiontexts[name]
					for line in conditiontext:gmatch("[^\n]+") do
						local condname, text = string.match(line, "^([^:]*): (.*)$")
						if condname and text and condname == lookfor then
							meta = text
						end
					end
					if meta then
						local status, func, err = pcall(loadstring, meta)
						if func then
							hooksecurefunc( hook, func )
						else
							geterrorhandler()('## X-LoadOn-'..hook..' ('..name..'): '..err)
						end
					end
				else
					geterrorhandler()('## X-LoadOn-Hooks: '..arg..' ('..hook..'): not a function')
				end
			end
			-- We specifically DO NOT return true here, this handler just sets up the other conditions. And will remain dorment for the remainder
		end,
	},
	["X-LoadOn-Slash"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg)
			local name_upper = name:upper():gsub('[^%w]','')
			local slashes = {}
			for slash in arg:gmatch('([^, ]+)') do
				if slash:sub(1,1) ~= '/' then
					slash = '/'..slash
				end
				-- below could be slightly optimized but my scoping skills fail me today, it works though :p
				_G['SLASH_'..string.sub(slash:upper(),2)..'1'] = slash
				slashes[#slashes+1] = string.sub(slash:upper(), 2)
				SlashCmdList[string.sub(slash:upper(),2)] = function(text)
					local new = _G['SLASH_'..string.sub(slash:upper(),2)..'1']
					for _, v in ipairs( slashes ) do
						_G['SLASH_'..v..'1'] = nil
						SlashCmdList[v] = nil
						hash_SlashCmdList['/'..v] = nil
					end
					AddonLoader:LoadAddOn(name)
					ChatFrame_OpenChat()
					ChatFrameEditBox:SetText(new..' '..text)
					ChatEdit_SendText(ChatFrameEditBox,1)
				end
			end
			-- We specifically DO NOT return true here, this handler just sets up the other conditions. And will remain dorment for the remainder
		end,
	},
	["X-LoadOn-LDB-Launcher"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg)
			local texture, brokername = string.split(" ", arg)
			brokername = brokername or name

			local OnClick, dataobj, OnTooltipShow
			OnClick = function(...)
				AddonLoader:LoadAddOn(name)
				if OnClick ~= dataobj.OnClick then dataobj.OnClick(...) end
			end
			OnTooltipShow = function(tt)
				tt:AddLine(brokername)
				tt:AddLine(AddonLoader.L.clicktoload, 0.2, 1, 0.2, 1)
			end
			dataobj = LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject(brokername, {type = "launcher", tocname = name, icon = texture, OnClick = OnClick, OnTooltipShow = OnTooltipShow})
			
			-- We specifically DO NOT return true here, this handler just sets up the other conditions. And will remain dorment for the remainder
		end,
	},
	["X-LoadOn-Zone"] = {
		events = {"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_ZONE_CHANGED"},
		handler = function(event, name, arg)
			if not BZ then
				BZ = LibStub and LibStub("Babble-Zone-3.0", true) -- silent check for BZ
			end
			local subzone = string.trim(GetSubZoneText()) -- yeah really...
			local realzone = GetRealZoneText()
			for zone in arg:gmatch('(%w[^,]+%w)') do
				if (BZ and (realzone == BZ[zone] or subzone == BZ[zone])) or 
					realzone == zone or subzone == zone then
					return true
				end
			end
		end,
	},
	["X-LoadOn-Execute"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg)
			for i = 2, 5 do
				local lookfor =  "X-LoadOn-Execute"..i
				local md
				local conditiontext = AddonLoader.conditiontexts[name]
				for line in conditiontext:gmatch("[^\n]+") do
					local condname, text = string.match(line, "^([^:]*): (.*)$")
					if condname and text and condname == lookfor then
						md = text
					end
				end
				if md then
					arg = arg..' '..md
				else
					break
				end
			end
			local status, func, err = pcall(loadstring, arg)
			if func then
				func()
			else
				geterrorhandler()('## X-LoadOn-Execute '..name..': '..err)
			end
		end,
	},
	["X-LoadOn-InterfaceOptions"] = {
		events = {"PLAYER_LOGIN"},
		handler = function(event, name, arg)
			local frame = CreateFrame("Frame", nil, UIParent)
			frame.name = arg
			frame.addon = name
			frame:Hide()
			frame:SetScript("OnShow", optionsOnShow)
			InterfaceOptions_AddCategory(frame)
			-- we do not return true here, the optionsOnShow function will actually load the addon
		end,
	}
}
