-- Lua script for Fityk.
-- Sorts output by groups and sums the intensities

-- This script is meant to be used with output file from Fityk analyze_and_plot.lua script.
-- Takes data from the output file and analyzes predefined lines from the file.
-- The code reads all of the input into memory so very old computers might not have enough RAM.

work_folder = "D:/Research_analysis/Projects/2024_DIFFER/Stage_1/"
output_folder = work_folder .. "Output/"
input_filepath = output_folder .. "Output_1.csv"
output_filepath = output_folder .. "Output_organized.csv"
separator = ','

elements_dict = {}
elements_dict["H"] = {"H_656280"}
elements_dict["D"] = {"D_656101"}
elements_dict["W"] = {"W1_653238", "W1_657390"}
elements_dict["Mo"] = {"Mo1_651983", "Mo_655345", "Mo_655621", "Mo_655861"}

observable_parameters = {"local constant", "Area", "FWHM"}

min_continuum_header = "Global constant (min intensity)"
local_continuum_header =  "local constant"
noise_header = "Global noise stdev"
series_header = "Filename"
experiment_header = "Experiment nr"



-- Hack for noise_stdev comparison with Area. TODO: fix and delete
apparatus_fn_fwhm = 0.044e-9


function main()
	print("Starting organization process. This might take awhile depending on amount of data.")
	
	local data_tbl = load_data()
	
	process_data(data_tbl)
	
	print("Output organized")
end

-- Returns data_tbl which has structure:  
-- ["series"] = {values_list},
-- ["experiment"] = {values_list}, 
-- ["min value"] = {values_list}, 
-- ["noise"] = {values_list}, 
-- ["all local consts"] = {all_values_list}, 
-- [parameter1] = {[element1] = {values_list}, [element2] = {values_list}...}, 
-- [parameter2] = {[element1] = {values_list}, [element2] = {values_list}...},...
function load_data()
	
	-- Generate table to hold input data
	local data_tbl = {}
	data_tbl["series"] = {}
	data_tbl["experiment"] = {}
	data_tbl["min value"] = {}
	data_tbl["noise"] = {}
	data_tbl["local const median"] = {}
	data_tbl["local const average"] = {}
	data_tbl["data"] = {}
	
	local all_local_consts = {}
	
	for idx, val in ipairs(observable_parameters) do
		data_tbl[val] = {}
		
		for element, list in pairs(elements_dict) do
			data_tbl[val][element] = {}
		end
	end
	
	-- Iterate over lines
	local row_index = 1
	local headers1, headers2
	for line in io.lines(input_filepath) do
                
		-- Generate sub-table that holds all the line info of that experiment
		local sub_table = {}
		local values, local_const_median, local_const_avg -- create variables before goto
		
		-- skip empty lines
		local non_empty = string.match(line, "([^" .. separator .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then -- empty line or only commas
			goto load_data_continue -- skip line in file
		end
		
		values = split(line, separator) -- table of csv values
                
		-- Save headers
		if row_index == 1 then -- first line with headers
			headers1 = values -- first line has titles
			
			-- Cut out the line identificator ("line_index line_id line_function")
			local id_pattern = "^%d+ ([%a%d_]+) [%a%d_]+$" -- digits (1 or more), space, [extracted] alphanumeric and _ characters (1 or more), space, alphanumeric and _ characters (1 or more)
			for idx_val, str in ipairs(values) do
				local line_id = string.match(str, id_pattern) or ""
				
				-- overwrite values with extracted line_id-s
				headers1[idx_val] = line_id
			end
			
			goto load_data_continue2 -- skip calculations
		end
		
		if row_index == 2 then -- second line with headers
			headers2 = values -- first line has titles
			goto load_data_continue2 -- skip calculations
		end
		
		-- Iterate over csv values in line
		for idx=1, tableLength(values) do
			local line_id = headers1[idx]
			local parameter = headers2[idx]
			local value = tonumber(values[idx])
			
			-- Save relevant values
			if (parameter == series_header) then table.insert(data_tbl["series"], values[idx]) -- keep string
			elseif (parameter == experiment_header) then table.insert(data_tbl["experiment"], value)
			elseif (parameter == min_continuum_header) then table.insert(data_tbl["min value"], value)
			elseif (parameter == noise_header) then table.insert(data_tbl["noise"], value) 
			else
				-- The parameter is relevant
				if is_in_table(observable_parameters, parameter) then
					
					-- Iterate over elements
					for element, line_list in pairs(elements_dict) do
						
						-- The line is relevant
						if is_in_table(line_list, line_id) then
							
							-- initialize
							if not sub_table[parameter] then sub_table[parameter] = {} end
							if not sub_table[parameter][element] then sub_table[parameter][element] = {} end
							
							-- Save the value
							table.insert(sub_table[parameter][element], value)
						end
					end
				end
			end
			if (parameter == local_continuum_header) then table.insert(all_local_consts, value) end
		end
		table.insert(data_tbl["data"], sub_table)
		
		-- median and average of local constants (also gives noise estimate)
		local_const_median = median(all_local_consts)
		local_const_avg = average_table(all_local_consts)
		table.insert(data_tbl["local const median"], local_const_median)
		table.insert(data_tbl["local const average"], local_const_avg)
		
		if math.fmod(row_index, 200) == 0 then
			print("Row " .. row_index .. " done.")
		end
		
		::load_data_continue2::
		
		row_index = row_index + 1
                
		::load_data_continue::
	end
	
	return data_tbl
end

function process_data(data_tbl)
	
	-- Sort tables
	table.sort(observable_parameters)
	local elements = get_sorted_keys(elements_dict)
	
	for idx,_ in ipairs(data_tbl["data"]) do
		-- sum lines area
		parameter_operation(data_tbl["data"][idx], elements, "Area", sum_table)
		
		-- average lines FWHM
		parameter_operation(data_tbl["data"][idx], elements, "FWHM", average_table)
		
		-- average local constants
		parameter_operation(data_tbl["data"][idx], elements, "local constant", average_table)
	end
	
	-- Save organized data
	write_output(observable_parameters, elements, data_tbl)
end

-- Does some operation inline with the values in parameter sub-table
function parameter_operation(data_tbl, elements, parameter, fn)
	if is_in_table(observable_parameters, parameter) then
		
		-- Iterate over elements and average the content of sub-tables
		for idx, element in ipairs(elements) do
			data_tbl[parameter][element] = fn(data_tbl[parameter][element])
		end
	end
end

function write_output(parameters, elements, data_tbl)
	local file = io.open(output_filepath,"w")
	io.output(file)
	
	-- Write headers
	io.write(series_header)
	io.write(separator .. experiment_header)
	io.write(separator .. min_continuum_header)
	io.write(separator .. noise_header)
	io.write(separator .. "Local const median")
	io.write(separator .. "Local const average")
	
	-- Iterate over parameters
	for idx_param, parameter in ipairs(parameters) do
		
		-- Iterate over elements
		for idx_elem, element in ipairs(elements) do
			io.write(separator .. parameter .. " " .. element)
		end
	end
	
	-- Write data
	for idx=1, tableLength(data_tbl["series"]) do
		io.write("\n")
		io.write(tostring(data_tbl["series"][idx]))
		io.write(separator .. tostring(data_tbl["experiment"][idx]))
		io.write(separator .. tostring(data_tbl["min value"][idx]))
		io.write(separator .. tostring(data_tbl["noise"][idx]))
		io.write(separator .. tostring(data_tbl["local const median"][idx]))
		io.write(separator .. tostring(data_tbl["local const average"][idx]))
		
		-- Iterate over parameters
		for idx_param, parameter in ipairs(parameters) do
			
			-- Iterate over elements
			for idx_elem, element in ipairs(elements) do
				io.write(separator ..  tostring(data_tbl["data"][idx][parameter][element]))
			end
		end
	end
	
	io.close(file)
end

-- Split string in a robust way and return a table
function split(inputstr, sep)
	local t = {} -- output table
	
	local is_string = false -- boolean to write string field into one element in table. If this is true then ignores separators
	
	
	local outputstr = "" -- string for adding characters in one element
	
	
	local str_len = string.len(inputstr) -- length of the string
	
	-- Iterate over all characters
	for i=1, (str_len + 1)  do
		local char = string.sub(inputstr, i, i) -- read single character
		
		if (char == csv_string_char) then -- flip is_string, skip character
			is_string = not is_string
		
		elseif (i == (str_len + 1)) or ((not is_string) and (char == sep)) then -- end of string or csv separator (and not meant as string), skip character and save outputstr to table
			table.insert(t, outputstr)
			outputstr = "" -- reset field value string
			
		else -- ordinary character, add to outputstr
			outputstr = outputstr .. char
		end
	end
	
	return t
end

-- Iterate over table values and if value is in table values return true
function is_in_table(table, value)
	for _,val in pairs(table) do
		if (value == val) then return true end
	end
	return false
end

-- Gets real table length
function tableLength(table, ignore_empty_string)
	local count = 0
	if type(table) == "table" then
		for _,v in pairs(table) do
			if (not ignore_empty_string) or (v ~= "") then 
				count = count + 1 
			end
		end
	end
	return count
end

-- Get keys in table and sort them
function get_sorted_keys(tbl)
	local keys = {}
	for key,_ in pairs(tbl) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
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

-- Prints every key and value of table
function printTable(table)
	if type(table) == "table" then
		for key,value in pairs(table) do
			print("Key:" .. tostring(key) .. " ; Value:" .. tostring(value))
		end
	else
		print(tostring(table))
	end
end


main()