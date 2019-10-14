local _, namespace = ...

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

local addon = namespace.addon
local L = addon.L

local options = {
	name = L.copyAnything,
	type = "group",
	set = function(info, value)
		addon.db.profile[info[#info]] = value
	end,
	get = function(info)
		return addon.db.profile[info[#info]]
	end,
	args = {
		general = {
			name = L.general,
			type = "group",
			args = {
				searchTypeDescExtended = {
					name = L.searchTypeDescExtended,
					type = "description",
					order = 1,
				},
				searchType = {
					name = L.searchType,
					desc = L.searchTypeDesc,
					type = "select",
					order = 2,
					values = {
						fontStrings = L.fontStrings,
						parentFrames = L.parentFrames,
						mouseFocus = L.mouseFocus,
					},
				},
			},
		},
	},
}

local defaultDB = {
	profile = {
		searchType = "fontStrings",
	},
}

function addon:OnInitialize()
	addon.db = AceDB:New("CopyAnythingDB", defaultDB, true)
	AceConfig:RegisterOptionsTable("CopyAnything", options)
	options.args.profiles = AceDBOptions:GetOptionsTable(self.db)
	AceConfigDialog:AddToBlizOptions("CopyAnything", L.copyAnything, nil, "general")
	AceConfigDialog:AddToBlizOptions("CopyAnything", L.profiles, L.copyAnything, "profiles")
end
