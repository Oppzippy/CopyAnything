local addon = select(2, ...).addon
local L = addon.L

local MouseIsOver, EnumerateFrames = MouseIsOver, EnumerateFrames

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

local MAX_FONTSTRINGS = 5000
local MAX_FONTSTRINGS_FAST = 10000 -- fast path (GetMouseFoci) can afford more since scope is limited

-- Shared helper: recursive children iterator (file scope so both GetChildFontStrings and fast paths can use it)
local function GetChildrenRecursive(frame)
	if not frame or not frame.GetChildren then
		return coroutine.wrap(function() end)
	end
	return coroutine.wrap(function()
		local ok, children = pcall(function() return { frame:GetChildren() } end)
		if not ok or not children then return end
		local count = #children
		for i = 1, count do
			local child = children[i]
			if child then
				coroutine.yield(child)
				for subChild in GetChildrenRecursive(child) do
					coroutine.yield(subChild)
				end
			end
		end
	end)
end

-- Returns iterator over frame + all descendants
local function IterateFrameAndChildren(frame)
	if not frame then
		return coroutine.wrap(function() end)
	end
	return coroutine.wrap(function()
		coroutine.yield(frame)
		for child in GetChildrenRecursive(frame) do
			coroutine.yield(child)
		end
	end)
end

--------------------------------------------------------------------------------
-- Search by font string
--

---@return string mouseoverText all text under the cursor.
function addon:GetMouseoverText()
	-- Retail fast path: use GetMouseFoci to limit scope (avoids EnumerateFrames freeze)
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if foci and #foci > 0 then
					-- Build iterator over foci + their descendants
			-- also include parent's other children for cases like ChatFrame1Background where text is sibling
			local function fociExpandedIter()
				return coroutine.wrap(function()
					local seen = {}
					for _, focus in ipairs(foci) do
						local ok, isSecret = pcall(function()
							return hasAnySecretAspectCompat(focus) or isAnchoringSecretCompat(focus)
						end)
						if not ok then isSecret = true end
						if not isSecret then
							-- focus itself + descendants
							for f in IterateFrameAndChildren(focus) do
								if not seen[f] then seen[f]=true; coroutine.yield(f) end
							end
											-- parent chain expansion for background sibling case (e.g., NineSlice.Center -> ObjectiveTrackerFrame)
							local cur = focus
							for depth = 1, 5 do
								local okP, parent = pcall(function() return cur:GetParent() end)
								if not okP or not parent or parent == UIParent or parent == WorldFrame or seen[parent] then break end
								local okN, parentName = pcall(function() return parent:GetName() end)
								if okN and parentName and parentName:find("UIParent") then break end
								for f in IterateFrameAndChildren(parent) do
									if not seen[f] then seen[f]=true; coroutine.yield(f) end
								end
								cur = parent
							end
						end
					end
				end)
			end
			local fontStringsIter = addon:GetDirectChildFontStrings(fociExpandedIter())
			local function mouseoverFontStringsIter()
				local count = 0
				local fontString = fontStringsIter()
				while fontString do
					local isVisible = fontString:IsVisible()
					if canAccessValueCompat(isVisible) and isVisible then
						count = count + 1
						if count > MAX_FONTSTRINGS_FAST then
							addon:Print(L.tooManyFontStrings:format(MAX_FONTSTRINGS_FAST))
							return nil
						end
						local status, isMouseOver = pcall(function()
							return MouseIsOver(fontString)
						end)
						if status and canAccessValueCompat(isMouseOver) and isMouseOver then
							return fontString
						end
					end
					fontString = fontStringsIter()
				end
			end
			local result = self:FontStringsToString(mouseoverFontStringsIter)
			if result then return result end
			-- on retail, fast path covers 99% of cases; fallback full scan would always hit MAX and spam, so return nil directly
			return nil
		end
		-- retail but no focus under mouse -> no text
		return nil
	end
	-- fallback: full EnumerateFrames scan (classic or edge case)
	local fontStringsIter = addon:GetDirectChildFontStrings(self:IterateFrames())
	local function mouseoverFontStringsIter()
		local count = 0
		local fontString = fontStringsIter()
		while fontString do
			local isVisible = fontString:IsVisible()
			if canAccessValueCompat(isVisible) and isVisible then
				count = count + 1
				if count > MAX_FONTSTRINGS then
					addon:Print(L.tooManyFontStrings:format(MAX_FONTSTRINGS))
					return nil
				end
				local status, isMouseOver = pcall(function()
					return MouseIsOver(fontString)
				end)
				if status and canAccessValueCompat(isMouseOver) and isMouseOver then
					return fontString
				end
			end
			fontString = fontStringsIter()
		end
	end
	return self:FontStringsToString(mouseoverFontStringsIter)
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
		-- Retail fast path: filter GetMouseFoci results instead of EnumerateFrames, walk up ancestry to find top-level
		if GetMouseFoci then
			local foci = GetMouseFoci()
			if foci and #foci > 0 then
				-- build expanded list: foci + ancestors up to UIParent
				local expanded = {}
				local seen = {}
				for _, f in ipairs(foci) do
					local cur = f
					for d=1,6 do
						if not cur or seen[cur] then break end
						seen[cur]=true
						expanded[#expanded+1]=cur
						local okP, parent = pcall(function() return cur:GetParent() end)
						if not okP or not parent or parent==UIParent or parent==WorldFrame then break end
						cur = parent
					end
				end
				local i = 0
				return function()
					while true do
						i = i + 1
						local frame = expanded[i]
						if not frame then return nil end
						local status, ok = pcall(function()
							local parent = frame:GetParent()
							local isVisible = frame:IsVisible()
							local isMouseOver = not isAnchoringSecretCompat(frame)
								and not hasAnySecretAspectCompat(frame)
								and MouseIsOver(frame)
							local parentName = parent and parent:GetName()
							local name = frame:GetName()
							if canAccessAllValuesCompat(isVisible, isMouseOver, parentName, name) then
								return isVisible
									and isMouseOver
									and (parentName and blacklist[parentName] or parent == nil)
									and not blacklist[name]
							end
						end)
						if status and ok then
							return frame
						end
						-- also check if any ancestor qualifies as top level (GetMouseFoci returns deepest first)
						-- walk up parent chain for additional candidates
					end
				end
			end
		end
		-- fallback classic path
		local frameIter = self:IterateFrames()
		return function()
			local frame = frameIter()
			while frame do
				local status, isMouseOver = pcall(function()
					local parent = frame:GetParent()
					local isVisible = frame:IsVisible()
					local isMouseOver = not isAnchoringSecretCompat(frame)
						and not hasAnySecretAspectCompat(frame)
						and MouseIsOver(frame)
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
---@return string? containing all text from frames under the cursor.
function addon:GetMouseoverFramesText()
	local texts = {}
	for frame in self:GetMouseoverFrames() do
		local t = self:GetSpecificFrameText(frame)
		if t then texts[#texts + 1] = t end
	end
	return texts[1] and table.concat(texts, "\n") or nil
end

--------------------------------------------------------------------------------
-- Search by mouse focus
--

---@return string?
function addon:GetMouseFocusText()
	local frames
	if GetMouseFoci then
		local ok, foci = pcall(GetMouseFoci)
		frames = ok and foci or {}
	else
		local ok, focus = pcall(GetMouseFocus)
		frames = ok and focus and { focus } or {}
	end
	-- expand to ancestors for cases like NineSlice.Center -> ObjectiveTrackerFrame
	local expanded = {}
	local seen = {}
	for _, f in ipairs(frames) do
		local cur = f
		for d=1,6 do
			if not cur or seen[cur] then break end
			seen[cur]=true
			expanded[#expanded+1]=cur
			local okP, parent = pcall(function() return cur:GetParent() end)
			if not okP or not parent or parent==UIParent or parent==WorldFrame then break end
			cur = parent
		end
	end
	local lines = {}
	for _, frame in next, expanded do
		if frame and frame ~= WorldFrame and frame.GetChildren and frame.GetRegions then
			local ok, t = pcall(function() return self:GetSpecificFrameText(frame) end)
			if ok and t and t~="" then
				-- avoid duplicating same text from multiple ancestors (prefer deepest non-empty)
				if not lines[1] or t ~= lines[#lines] then
					lines[#lines + 1] = t
					-- for focus mode, return first non-empty ancestor is enough (deepest has priority)
					break
				end
			end
		end
	end
	-- chat sibling fallback: ChatFrame1Background is sibling of ChatFrame1 under UIParent, ancestry walk stops at UIParent so not covered
	if not lines[1] then
		for i=1,10 do
			local cf = _G["ChatFrame"..i]
			if cf and not seen[cf] then
				local okM, isOver = pcall(function() return MouseIsOver(cf) end)
				if okM and canAccessValueCompat(isOver) and isOver then
					local ok, t = pcall(function() return self:GetSpecificFrameText(cf) end)
					if ok and t and t~="" then
						lines[1]=t; break
					end
				end
			end
		end
	end
	return lines[1] and table.concat(lines, "\n") or nil
end

--------------------------------------------------------------------------------
-- Search tooltip
--

---@return string?
function addon:GetTooltipText()
	-- Retail fast path: directly check GetMouseFoci + known tooltip globals before full scan
	if GameTooltip and GameTooltip:IsShown() then
		local ok, text = pcall(function() return self:GetSpecificFrameText(GameTooltip) end)
		if ok and text then return text end
	end
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if foci then
			for _, frame in ipairs(foci) do
				local okType, objType = pcall(function() return frame:GetObjectType() end)
				if okType and objType == "GameTooltip" then
					local okShown, isShown = pcall(function() return frame:IsShown() end)
					if okShown and isShown then
						local okText, text = pcall(function() return self:GetSpecificFrameText(frame) end)
						if okText and text then return text end
					end
				end
			end
		end
	end
	-- fallback: scan all frames for any visible GameTooltip
	for frame in self:IterateFrames() do
		local okType, objType = pcall(function() return frame.GetObjectType and frame:GetObjectType() end)
		if okType and objType == "GameTooltip" then
			local okShown, isShown = pcall(function() return frame:IsShown() end)
			if okShown and isShown then
				local okText, text = pcall(function() return self:GetSpecificFrameText(frame) end)
				if okText and text then return text end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Specific frame
--

-- Returns text from a specific frame and its children.
---@param frame Frame
---@return string?
function addon:GetSpecificFrameText(frame)
	if not frame or not frame.GetChildren or not frame.GetRegions then return nil end
	local okIter, fontStringIter = pcall(function() return addon:GetChildFontStrings(frame) end)
	if not okIter or type(fontStringIter) ~= "function" then return nil end
	local function visibleFontStrings()
		local fontString = fontStringIter()
		while fontString do
			local ok, isVisible = pcall(function() return fontString:IsVisible() end)
			if ok and canAccessValueCompat(isVisible) and isVisible then
				return fontString
			end
			fontString = fontStringIter()
		end
	end
	local ok, result = pcall(function() return addon:FontStringsToString(visibleFontStrings) end)
	if ok then return result end
	return nil
end

--------------------------------------------------------------------------------
-- Helper functions
--

-- Concatenates the text of a table of font strings into one string.
-- font strings are separated with \n.
---@param fontStringsIter fun(): FontString?
---@return string?
function addon:FontStringsToString(fontStringsIter)
	local texts = {}
	local count = 0
	for fontString in fontStringsIter do
		count = count + 1
		if count > MAX_FONTSTRINGS then
			addon:Print(L.tooManyFontStrings:format(MAX_FONTSTRINGS))
			break
		end
		local ok, text = pcall(function() return fontString:GetText() end)
		if ok and canAccessValueCompat(text) and text and text ~= "" then
			texts[#texts + 1] = text
		end
	end
	return texts[1] and table.concat(texts, "\n") or nil
end

do
	---@param frame Frame to scan for font strings.
	---@return fun(): FontString? iter Iterator of FontStrings
	function addon:GetChildFontStrings(frame)
		if not frame or not frame.GetChildren or not frame.GetRegions then
			return coroutine.wrap(function() end)
		end
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
			local ok, regions = pcall(function() return { frame:GetRegions() } end)
			if ok and regions then
				for _, region in next, regions do
					if region and region.GetText then
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
