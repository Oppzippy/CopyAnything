local _, addon = ...

function addon.TableMap(t, transform)
	local newTable = {}
	for k, v in next, t do
		newTable[k] = transform(v)
	end
	return newTable
end

function addon.TableFilter(t, condition)
	local newTable = {}
	for _, value in ipairs(t) do
		if condition(value) then
			newTable[#newTable+1] = value
		end
	end
	return newTable
end

function addon.TableFlatten(t, depth)
	local newTable = {}
	for _, value in ipairs(t) do
		if type(value) == "table" and depth ~= 0 then
			local subValues = addon.TableFlatten(value, depth - 1)
			for _, subValue in ipairs(subValues) do
				newTable[#newTable+1] = subValue
			end
		else
			newTable[#newTable+1] = value
		end
	end
	return newTable
end
