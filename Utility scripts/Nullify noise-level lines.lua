-- Lua script for Fityk.
-- Sorts output by groups and sums the intensities

-- This script is meant to be used with output session from Fityk analyze_and_plot.lua script.
-- Compares the lines of the session with the noise level and writes the line height of weak lines 
-- as 0.


-- The line has to be at least this many times stronger than the noise
noise_multiplier = 2

function main()
	
	-- Iterate over lines
	local functions = F:all_functions()
	for idx = 0, #functions - 1 do
		local fn = functions[idx]
		
		-- Check if the function has height parameter 
		local height
		local status, err = pcall(function() height = fn:get_param_value("height") end)
		
		if height then
			
			local location = fn:get_param_value("center")
			local noise = get_noise_estimate(location)
			
			if height < (noise * noise_multiplier) then
				local height_var = "$" .. fn:var_name("height")
				F:execute(height_var .. " = 0")
			end
		end
	end
	
	print("Lines nullified")
end


function get_noise_estimate(location)
	bg_local_fn = F:get_function("bg_local")
	local local_constant = bg_local_fn:value_at(location)
	
	return local_constant
end


function sum_table(table)
    local sum = 0
    for _, value in pairs(table) do
        sum = sum + value
    end
    return sum
end

function average_table(table)
    local sum = 0
	local count = 0
    for _, value in pairs(table) do
        sum = sum + value
		count = count + 1
    end
	
	if count == 0 then return 0
	else return sum / count
    end
end

-- Get the median of a table.
-- From: http://lua-users.org/wiki/SimpleStats
function median( t )
  local temp={}

  -- deep copy table so that when we sort it, the original is unchanged
  -- also weed out any non numbers
  for k,v in pairs(t) do
    if type(v) == 'number' then
      table.insert( temp, v )
    end
  end

  table.sort( temp )

  -- If we have an even number of table elements or odd.
  if math.fmod(#temp,2) == 0 then
    -- return mean value of middle two elements
    return ( temp[#temp/2] + temp[(#temp/2)+1] ) / 2
  else
    -- return middle element
    return temp[math.ceil(#temp/2)]
  end
end

main()