---@class CopyAnything
local addon = select(2, ...).addon

-- Restore of the pre-iterator guard (see ab1e041 refactor which dropped the
-- old "#fontStrings > 500" check): cap collected font strings so one hotkey
-- can't freeze the client. Matches Locales/enUS.lua tooManyFontStrings.
local MAX_FONT_STRINGS = 500
-- Safety net for the full EnumerateFrames() scan itself: the quest UI in
-- 12.x can create tens of thousands of frames; abort the scan before it
-- freezes the client.
local MAX_SCANNED_REGIONS = 5000

---@return boolean
local function canAccessValueCompat(value)
	return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE or canaccessvalue(value)
end

---@return boolean
local function canAccessAllValuesCompat(...)
	return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE or canaccessallvalues(...)
end

---@param value Frame
---@return boolean
local function isAnchoringSecretCompat(value)
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and value:IsAnchoringSecret()
end

---@param value Frame
---@return boolean
local function hasAnySecretAspectCompat(value)
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and value:HasAnySecretAspect()
end

-- Single-pcall prefilter + region fetch for one frame. One pcall and zero
-- closures per frame: the previous version built 2-3 closures per frame
-- (~90k allocs over a 30k-frame scan) which itself cost seconds.
-- Returns regions table, or nil + skip reason ("hidden"/"empty").
local function GetVisibleFrameRegions(frame)
	local vis = frame:IsVisible()
	if not canAccessValueCompat(vis) or not vis then
		return nil, "hidden"
	end
	local n = frame:GetNumRegions()
	if not canAccessValueCompat(n) or type(n) ~= "number" or n <= 0 then
		return nil, "empty"
	end
	return { frame:GetRegions() }, nil
end


--------------------------------------------------------------------------------
-- Search by font string
--

---@return string mouseoverText all text under the cursor.
function addon:GetMouseoverFontStringsText()
	-- Fast path: only scan the subtrees under the mouse focus stack
	-- (a handful of frames) instead of all ~30k enumerated frames.
	-- Falls back to the full scan when nothing is found there.
	local foci
	if GetMouseFoci then
		foci = GetMouseFoci()
	else
		local f = GetMouseFocus()
		foci = f and { f } or {}
	end
	local fastCo = coroutine.wrap(function()
		-- (a) focus subtrees (existing behaviour)
		for _, focusFrame in ipairs(foci) do
			if focusFrame ~= WorldFrame and focusFrame.GetChildren then
				local ok, iter = pcall(function()
					return addon:GetChildFontStrings(focusFrame)
				end)
				if ok and iter then
					for region in iter do
						coroutine.yield(region)
					end
				end
			end
		end
		-- (b) direct regions of each focus frame and its ancestors, walking
		-- up. Covers panels whose GetChildren is forbidden (subtree scan
		-- above then yields nothing) but whose own GetRegions still works.
		for _, focusFrame in ipairs(foci) do
			local depth = 0
			local frame = focusFrame
			while frame and depth < 8 do
				local okR, regions = pcall(GetVisibleFrameRegions, frame)
				if okR and regions then
					for _, region in next, regions do
						if region.GetText then
							coroutine.yield(region)
						end
					end
				end
				local okP, parent = pcall(function()
					return frame:GetParent()
				end)
				if not okP then
					break
				end
				frame = parent
				depth = depth + 1
			end
		end
	end)
	local text = self:FontStringsToString(self:FilterMouseoverFontStrings(fastCo))
	if text then
		return text
	end
	local fontStringsIter = addon:GetDirectChildFontStrings(self:IterateFrames())
	return self:FontStringsToString(self:FilterMouseoverFontStrings(fontStringsIter))
end

-- Shared IsVisible + IsMouseOver filter, extracted so the fast path and the
-- full scan use identical logic.
---@param fontStringsIter fun(): FontString?
---@return fun(): FontString? iter
function addon:FilterMouseoverFontStrings(fontStringsIter)
	return function()
		local fontString = fontStringsIter()
		while fontString do
			local okVis, isVisible = pcall(function()
				return fontString:IsVisible()
			end)
			if okVis and canAccessValueCompat(isVisible) and isVisible then
				-- TODO determine if the comment below is still accurate, and if so, log
				-- errors that aren't due to restricted regions

				-- No way of knowing if the region is restricted, so just skip this one
				-- if it is restricted or has any other error.
				local status, isMouseOver = pcall(function()
					return fontString:IsMouseOver()
				end)
				if status and canAccessValueCompat(isMouseOver) and isMouseOver then
					return fontString
				end
			end
			fontString = fontStringsIter()
		end
	end
end

--------------------------------------------------------------------------------
-- Search by frame
--

do
	-- Parent frame names that don't contain the word parent
	local blacklist = {
		UIParent = true,
		WorldFrame = true,
		WeakAurasFrame = true,
		DetailsAuraPanel = true,
		ElvUF_PetBattleFrameHider = true,
		TimerTracker = true,
		PetFrame = true,
	}

	setmetatable(blacklist, {
		__index = function(t, key)
			return type(key) == "string" and key:lower():find("parent")
		end,
	})

	---Returns all top level frames under the cursor.
	---@return fun(): Frame? iter
	function addon:GetMouseoverFrames()
		local frameIter = self:IterateFrames()
		return function()
			local frame = frameIter()
			while frame do
				-- No way of knowing if the region is restricted, so just skip this one
				-- if it is restricted or has any other error.
				local status, isMouseOver = pcall(function()
					local parent = frame:GetParent()
					local isVisible = frame:IsVisible()
					local isMouseOver = not isAnchoringSecretCompat(frame)
						and not hasAnySecretAspectCompat(frame)
						and frame:IsMouseOver()
					local parentName = parent and parent:GetName()
					local name = frame:GetName()

					if canAccessAllValuesCompat(isVisible, isMouseOver, parentName, name) then
						return isVisible
							and isMouseOver
							and (parentName and blacklist[parentName] or parent == nil)
							and not blacklist[name]
					end
				end)
				if status and isMouseOver then
					return frame
				end
				frame = frameIter()
			end
		end
	end
end

---Returns all text from all frames under the cursor.
---@return string containing all text from frames under the cursor.
function addon:GetMouseoverFramesText()
	local texts = {}
	for frame in self:GetMouseoverFrames() do
		texts[#texts + 1] = self:GetSpecificFrameText(frame)
	end
	local result = table.concat(texts, "\n")
	-- "" is truthy in Lua: without this, Core.lua SlashCopy would call
	-- Copy("") and show an empty popup instead of "No text found."
	if result == "" then
		return nil
	end
	return result
end

--------------------------------------------------------------------------------
-- Search by mouse focus
--

---@return string
function addon:GetMouseFocusText()
	local frames
	if GetMouseFoci then
		frames = GetMouseFoci()
	else
		frames = { GetMouseFocus() }
	end
	local lines = {}
	for _, frame in next, frames do
		if frame ~= WorldFrame then
			lines[#lines + 1] = self:GetSpecificFrameText(frame)
		end
	end
	local result = table.concat(lines, "\n")
	if result == "" then
		return nil
	end
	return result
end

--------------------------------------------------------------------------------
-- Search tooltip
--

---@return string?
function addon:GetTooltipText()
	-- attempt to copy any visible GameTooltip-derived frame
	for frame in self:IterateFrames() do
		if frame.GetObjectType and frame:GetObjectType() == "GameTooltip" and frame:IsShown() then
			local text = self:GetSpecificFrameText(frame)
			if text then
				return text
			end
		end
	end
	-- fall back to global GameTooltip if iterate missed it
	if GameTooltip and GameTooltip:IsShown() then
		return self:GetSpecificFrameText(GameTooltip)
	end
end

--------------------------------------------------------------------------------
-- Specific frame
--

-- Returns text from a specific frame and its children.
---@param frame Frame
---@return string
function addon:GetSpecificFrameText(frame)
	local fontStringIter = addon:GetChildFontStrings(frame)
	local function visibleFontStrings()
		local fontString = fontStringIter()
		while fontString do
			local isVisible = fontString:IsVisible()
			if canAccessValueCompat(isVisible) and isVisible then
				return fontString
			end

			fontString = fontStringIter()
		end
	end
	return addon:FontStringsToString(visibleFontStrings)
end

--------------------------------------------------------------------------------
-- Helper functions
--

-- Concatenates the text of a table of font strings into one string.
-- font strings are separated with \n.
---@param fontStringsIter fun(): FontString?
---@return string
function addon:FontStringsToString(fontStringsIter)
	local texts = {}
	local scanned = 0
	for fontString in fontStringsIter do
		scanned = scanned + 1
		if scanned > MAX_SCANNED_REGIONS then
			self:Print((self.L and self.L.tooManyFontStrings or "More than %d font strings were found. The copy was cancelled to prevent the game from freezing for an excessive amount of time."):format(MAX_FONT_STRINGS))
			return nil
		end
		local text = fontString:GetText()
		if canAccessValueCompat(text) and text then
			texts[#texts + 1] = text
			if #texts > MAX_FONT_STRINGS then
				self:Print((self.L and self.L.tooManyFontStrings or "More than %d font strings were found. The copy was cancelled to prevent the game from freezing for an excessive amount of time."):format(MAX_FONT_STRINGS))
				return nil
			end
		end
	end
	return texts[1] and table.concat(texts, "\n")
end

do
	---Iterator of all children, grandchildren, etc. Does not include the frame itself.
	---@param frame Frame Frame to scan recirsively for children.
	---@return fun(): Frame? iter
	local function GetChildrenRecursive(frame)
		return coroutine.wrap(function()
			-- 12.x/Midnight: EnumerateFrames() can yield forbidden frames;
			-- calling GetChildren on one throws "Attempt to access forbidden
			-- object" and aborts the whole copy, so skip it instead.
			local ok, children = pcall(function()
				return { frame:GetChildren() }
			end)
			if not ok or type(children) ~= "table" then
				return
			end
			local count = #children
			for i = 1, count do
				local child = children[i]
				coroutine.yield(child)
				for subChild in GetChildrenRecursive(child) do
					coroutine.yield(subChild)
				end
			end
		end)
	end

	---@param frame Frame to scan for font strings.
	---@return fun(): FontString? iter Iterator of FontStrings
	function addon:GetChildFontStrings(frame)
		local childFramesIter = GetChildrenRecursive(frame)
		local framesIter = coroutine.wrap(function()
			coroutine.yield(frame)
			for childFrame in childFramesIter do
				coroutine.yield(childFrame)
			end
		end)
		local fontStrings = self:GetDirectChildFontStrings(framesIter)
		return fontStrings
	end
end

-- Returns font strings that are a direct child of any of the supplied frames.
---@param framesIter fun(): Frame? frames to search.
---@return fun(): FontString? iter FontStrings that are direct children of the supplied frames.
function addon:GetDirectChildFontStrings(framesIter)
	return coroutine.wrap(function()
		for frame in framesIter do
			-- One pcall, zero closures per frame (see GetVisibleFrameRegions).
			-- Forbidden frames land here and are skipped instead of aborting
			-- the whole copy (GetRegions taint error).
			local ok, regions = pcall(GetVisibleFrameRegions, frame)
			if ok and regions then
				for _, region in next, regions do
					if region.GetText then
						coroutine.yield(region)
					end
				end
			end
		end
	end)
end

---@return fun(): Frame? iter
function addon:IterateFrames()
	local frame = nil
	return function()
		frame = EnumerateFrames(frame)
		return frame
	end
end
