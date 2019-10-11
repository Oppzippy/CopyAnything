local _, addon = ...
local ADDON_NAME = "Copy Anything"

local LibCopyPaste = LibStub("LibCopyPaste-1.0")

_G["SLASH_COPYANYTHING1"] = "/copyanything"
_G["SLASH_COPYANYTHING2"] = "/copy"

local EnumerateFrames, MouseIsOver = EnumerateFrames, MouseIsOver

local function GetGlobalFontStrings(condition)
    local fontStrings = {}
    local frame = EnumerateFrames()
    while frame do
        local regions = { frame:GetRegions() }
        for i, region in next, regions do
            -- much faster to check if GetText than to use GetObjectType and check if FontString
            if region.GetText and condition(region) then
                fontStrings[#fontStrings+1] = region
            end
        end
        frame = EnumerateFrames(frame)
    end
    return fontStrings
end

local function CopyFontStrings(fontStrings)
    local texts = {}
    for i, f in ipairs(fontStrings) do
		local text = f:GetText()
		if text then
        	texts[#texts+1] = text
		end
    end
    LibCopyPaste:Copy(ADDON_NAME, table.concat(texts, "\n"))
end

local function GetAllChildren(frame)
	local children = { frame:GetChildren() }
	local count = #children
	if count > 0 then
		for i = 1, count do
			local child = children[i]
			local subChildren = GetAllChildren(child)
			if type(subChildren) == "table" then
				for _, subChild in ipairs(subChildren) do
					children[#children+1] = subChild
				end
			else
				children[#children+1] = subChildren
			end
		end
		return children
	end
	return frame
end

do
	-- Filters and transforms
	local function GetRegions(frame)
		return { frame:GetRegions() }
	end

	local function FilterMouseOver(fontString)
	    return fontString:IsVisible() and MouseIsOver(fontString)
	end

	local function FilterIsFontString(region)
		return region.GetText
	end

	-- Cases are tried in order until one returns true
	local cases = {
		function(frame) -- Chat frame
			if frame.GetMessageInfo then -- chat frame
				local messages = {}
				for i = 1, frame:GetNumMessages() do
					messages[i] = frame:GetMessageInfo(i)
				end
				LibCopyPaste:Copy(ADDON_NAME, table.concat(messages, "\n"))
				return true
			end
		end,
		function(frame) -- Default
			local frames = GetAllChildren(frame)
			table.insert(frames, 1, frame)
			local fontStrings = addon.TableMap(frames, GetRegions)
			fontStrings = addon.TableFlatten(fontStrings, 1)
			fontStrings = addon.TableFilter(fontStrings, FilterIsFontString)
			if #fontStrings > 100 then return end
			CopyFontStrings(fontStrings)
			return true
		end,
	}

	SlashCmdList["COPYANYTHING"] = function(msg)
		local frame = #msg > 0 and _G[msg]
		if frame and frame.GetChildren then
			for _, case in ipairs(cases) do
				if case(frame) then
					break
				end
			end
		else
			local fontStrings = GetGlobalFontStrings(FilterMouseOver)
			CopyFontStrings(fontStrings)
		end
	end
end
