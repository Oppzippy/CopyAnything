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
				searchType = {
					name = L.searchType,
					desc = L.searchTypeDesc,
					type = "select",
					values = {
						filterFontStrings = L.filterFontStrings,
						filterFrames = L.filterFrames,
						mouseFocus = L.mouseFocus,
					},
				},
			},
		},
	},
}

local defaultDB = {
	profile = {
		searchType = "filterFontStrings",
	},
}

function addon:OnInitialize()
	addon.db = AceDB:New("CopyAnythingDB", defaultDB, true)
	AceConfig:RegisterOptionsTable("CopyAnything", options)
	options.args.profiles = AceDBOptions:GetOptionsTable(self.db)
	AceConfigDialog:AddToBlizOptions("CopyAnything", L.copyAnything, nil, "general")
	AceConfigDialog:AddToBlizOptions("CopyAnything", L.profiles, L.copyAnything, "profiles")
end
