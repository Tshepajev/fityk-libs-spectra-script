-- Lua script for Fityk GUI version.
-- Script version: 3.11
-- Author: Jasper Ristkok

--[[
Written for use with LIBS (atomic) spectra gained from SOLIS and Sophi nXt software
with Andor iStar340T ICCD camera.
The script could possibly be used for other applications but some
adjustments to the code might be needed. Note that the script is
written for Fityk default settings (Fityk v 1.3.1).
There are comments to simplify understanding the code but
I assume assume that you have read the Fityk manual 
(http://fityk.nieto.pl/fityk-manual.html).
The script should work with Windows and Unix (Mac and Linux).

This script uses a hack to output the GUI image of the fit.
In Fityk the dataset to be plotted needs to be selected, 
however, selecting dataset for plotting is a GUI feature and is unavailable 
for scripts. Still, @0 is selected by default. Plotting uses this feature.
In case you can't get images drawn the right way, try to click 
dataset @0 in the data tab(so that it highlighted).

However, plotting uses the appearance that you have in the GUI.
Therefore, e.g. if you want datapoints to be connected with lines
you have to check "line" box in the GUI. Also if you make 1 dataset and
add a bunch of functions, you can colour them. These colours will
remain the same on drawn images. In other words: make 1 dataset the
way you want it to look, click on the dataset @0 and then run the script.

MAKE SURE THAT INPUT IS UTF-8! Lua can't handle unicode characters like no break space that e.g. excel sometimes outputs.
]]



----------------------------------------------------------------------
-- CHANGE CONSTANTS BELOW!
-- Also change user constants in user_constants.lua in info_folder
----------------------------------------------------------------------
-- What is system path for input folder?
-- Input folders and files in them have to exist beforehand. Fityk really doesn't like special characters anywhere.
-- Leave / or \ at the end of the string, so that a filename can be concatenated directly.
-- Windows path can be both with \ or /. However, \ is special in LUA strings, so it needs to be \\.
work_folder = "D:/Research_analysis/Projects/2024_JET/Lab_comparison_test/Data_processing/Stage_1/"
info_folder = work_folder .. "Input_info/" -- has to contain user_constants.lua
----------------------------------------------------------------------
-- CHANGE CONSTANTS ABOVE!




-------------------------------------------------------------------------------------------------------------
-- Global constants
-------------------------------------------------------------------------------------------------------------
-- Math constants
infinity = 1.79769e308 -- Fityk doesn't like math.huge
infinitesimal = 1e-18 -- a very small value but still in the ballpark of other Fityk variables

-- Constants from user_constants.lua in info_folder
--[[
	input_path
	output_path
	corrected_path
	sessions_path
	output_data_name
	output_data_end
	stopscript_name
	file_end
	separator
	input_data_separator
	csv_string_char
	noise_stdevs_file
	
	transform
	function transform_line_positions(lines_info_filename)
	
	start_experiment_nr
	end_experiment_nr
	cut_start
	cut_end
	noise_estimate_start
	noise_estimate_end
	noise_before_sensitivity_correction
	
	moving_average_experiment_radius
	moving_average_pixels_radius
	process_nr_spectra
	gain_functions
	
	forbid_lines_outside_range
	apparatus_fn_fwhm
	min_FWHM
	max_line_influence_diameter
	high_constant_bound_percentile
	max_Voigt_shape
	min_Voigt_shape
	nullify_weak_lines_data
	nullify_weak_lines_visual
	noise_level_check_multiplier
	
	only_correct_spectra
	save_sessions
	narrower_polyline_step
	plot
	pad_x_min
	pad_x_max
	pad_y_min
	pad_y_max
	
	debug_mode
	stop
	stop_before_lines
	
--]]


-------------------------------------------------------------------------------------------------------------
-- Global variables
-------------------------------------------------------------------------------------------------------------
-- TODO: noise with input info
-- TODO: integrate Fityk output organizer script

-- Hack to stop frozen script safely
stopscript = false

-- boundaries for the spectrum
startpoint = nil
endpoint = nil

-- Noise amplitudes for current file. Lines smaller than this are written as 0 intensity.
noise_stdevs = nil -- read from noise_stdevs file in Input_data_corrected/ folder
noise_stdev = 0

-- Output text file name (compiled automatically from output_data_name and output_data_end)
output_data_name_nr = nil

-- Check previous error message, so that there wouldn't be 100 identical errors in a row.
last_error_msg = nil

-- Initialize table for holding input_info folder data
spectra_info, pixel_info, lines_info = {},{},{}


-------------------------------------------------------------------------------------------------------------
-- MAIN PROGRAM
-------------------------------------------------------------------------------------------------------------
-- Loads data from files into memory, finds defined peaks, fits them, exports the data and plots the graphs.
function main_program()
	-- Read in user constants from separate script (separate for reproducibility of analysis)
	F:execute("exec \'" .. info_folder .. "user_constants.lua\'")
	
	-- Create stopscript in info_folder if it doesn't exist, empty it if it does.
	initialize_stopscript()
	
	-- Initialize variables defined at the start and/or re-order them
	initialize_variables()
	
	-- Reset and initialize Fityk (keeps LUA variables and Fityk GUI formatting, but e.g. user defined functions are deleted)
	reset()
	
	-- Load info from info files to LUA tables
	load_info()
	
	-- resets Fityk and asks user for run parameters
	local file_check, experiment_check, continue = initialize_program()
	
	-- Error in initialization phase
	if continue == nil then return end
	
	if not continue then -- stop the script
		print("You stopped the script")
		return 
	end
	
	-- Iterates over files, fits lines and outputs data
	process_data(file_check, experiment_check)
	
	print("Script finished")
end


-------------------------------------------------------------------------------------------------------------
-- Function declarations in the order they are called (Utility functions are at the end)
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------
-- Initialization phase
----------------------------------------------------------------------
-- Create stopscript in info_folder if it doesn't exist, empty it if it does.
function initialize_stopscript()
	local file = io.open(info_folder..stopscript_name,"w")
	io.close(file)
end

-- Initialize variables defined at the start and/or re-order them 
function initialize_variables()
	db("initialize_variables",6)
	
	if noise_estimate_start or noise_estimate_end then -- at least one is defined
		noise_estimate_start = noise_estimate_start or -infinity
		noise_estimate_end = noise_estimate_end or infinity
	end
end

-- Set up Fityk instance (settings user defined functions etc)
function initialize_fityk()
	
	--F:execute("set default_sigma = one") -- The camera is accurate so stdev of points are equal
	F:execute("set max_wssr_evaluations = 1500")
	F:execute("set verbosity = -1") -- for less spam
	F:execute("set lm_stop_rel_change = 1e-016") -- otherwise sometimes with many functions the fit is awful (no fit basically)
	F:execute("set lm_max_lambda = 1e+020")
	
	-- VoigtFWHM declaration
	pcall(function() -- Try to undefine existing function definition
		F:execute("undefine VoigtFWHM")
	end)
	-- Create Voigt profile which takes FWHM as its argument, Fityk can't handle non-continuous functions due to ternary operator ("?") not supported.
	-- The function is gained by brute force fitting polynomial to FWHM vs shape vs gwidth data and then doing linear fit to the polynomials. This requires shape to remain under 20 (!!). Also it's more volatile than ordinary Voigt
	-- Analytical fn: gwidth = 2500 (50 sqrt((fwhm^2 (2169 * shape^2 + 6931.47))/(1.72243e6 * shape^2 - 1.73287e7)^2) + (2673 * fwhm * shape)/(1.72243e6 * shape^2 - 1.73287e7)) if shape > 0 and shape < 3.17185 and fwhm > 0
	-- The command has to be on one line for opening Fityk session from history
	F:execute("define VoigtFWHM(height, center, fwhm = hwhm*2, shape = 0.3[0:18]) = Voigt(height, center, fwhm*(-3.66354460031617E-10 * abs(shape)^9 + 3.69496435533307E-08 * shape^8 - 1.59975065392683E-06 * abs(shape)^7 + 0.0000389329719949874 * shape^6 - 0.000586382340638549 * abs(shape)^5 + 0.00568217176507484 * shape^4 - 0.0358091432488762 * abs(shape)^3 + 0.145909575579559 * shape^2 - 0.377843804199813 * abs(shape) + 0.599045873823219), abs(shape))")
	
	
	-- VoigtApparatus declaration
	pcall(function() -- Try to undefine existing function definition
		F:execute("undefine VoigtApparatus")
	end)
	-- Create Voigt profile which locks the Gaussian part width as the apparatus function.
	-- gwidth = (gauss_fwhm / 2)
	-- w_G = 2 * sqrt(ln(2)) * gwidth
	local gwidth = apparatus_fn_fwhm / 2 / math.sqrt(math.log(2)) -- from Fityk manual at Voigt function
	F:execute("define VoigtApparatus(height, center, shape = 0.3[0:18]) = Voigt(height, center, " ..tostring(gwidth).. ", shape)")
	
	
	-- Rectangle function declaration. The start and end parameters need to be locked, otherwise Fityk throws 
	-- "Error: Trying to reverse singular matrix. Column 1 is zeroed."
	pcall(function() -- Try to undefine existing function definition
		F:execute("undefine Rectangle")
	end)
	F:execute("define Rectangle(height=avgy, start, end) = Sigmoid(0, height, start, 1e-300) + Sigmoid(0, -height, end, 1e-300)")
end

-- Resets data in Fityk and sets the settings again because Fityk also resets it's settings to default
function reset()
	db("reset",2)
	-- Selects the first dataset
	F:execute("use @0")
	
	-- Resets all Fityk-side info (not LUA-side, that holds all necessary info)
	F:execute("reset")
	
	-- Define VoigtFWHM and VoigtApparatus functions and relevant settings
	initialize_fityk()
end

-- Deletes all variables
function delete_variables()
	db("delete_variables",4)
	variables = F:all_variables()
	for i = #variables-1,0,-1 do
		F:execute("delete $"..variables[i].name)
	end
end
------------------------------------------

-- Deletes all functions for dataset
function delete_functions(dataset_i)
	db("delete_functions",4)
	functions = F:get_components(dataset_i)
	for function_index = #functions-1,0,-1 do
		F:execute("delete %"..functions[function_index].name)
	end
end
------------------------------------------

-- Deletes dataset with given index, does NOT delete variables
function delete_dataset(dataset_i)
	db("delete_dataset",4)
	delete_functions(dataset_i)
	-- Deletes the dataset
	F:execute("delete @"..dataset_i)
end
------------------------------------------

-- Deletes all datasets, functions and variables for clean sheet
-- equivalent to F:execute("reset")
function delete_all()
	db("delete_all",4)
	-- Deletes datasets
	series_length = F:get_dataset_count()
	for dataset_i = series_length-1,0,-1 do
		F:execute("use @"..dataset_i)
		delete_dataset(dataset_i)
	end
	delete_variables()
end


-- Read data from input_info folder into LUA variables in experiments_info
function load_info()
	db("load_info",1)
	-- Change / into \ for windows CMD
	--local info_folder_win = string.gsub(info_folder, "/", "\\")
	
	-- Get files for spectrum_wise, pixel_wise and lines info
	local spectrum_files,pixel_files,lines_files = {},{},{}
	for filename in io.popen("dir \"" .. info_folder .. "\" /b"):lines() do
		if string.match(filename, "^Spectra_info.+csv") then -- Spectra_info*.csv (.+ means any character as much as possible)
			table.insert(spectrum_files, filename)
		elseif string.match(filename, "^Pixel_info.+csv") then -- Pixel_info*.csv
			table.insert(pixel_files, filename)
		elseif string.match(filename, "^Lines_info.+csv") then -- Lines_info*.csv
			table.insert(lines_files, filename)
		end
	end
	
	-- Iterate over files containing pixel info
	for i,filename in ipairs(pixel_files) do
		load_pixel_info(filename) -- Load all info from that file
	end
	
	-- Fill in fields which didn't have a cloumn in input info
	validate_pixel_info()
	
	-- Iterate over files containing pixel info
	for i,filename in ipairs(lines_files) do
		load_lines_info(filename) -- Load all info from that file
	end
	
	-- Fill in fields which didn't have a cloumn in input info
	validate_lines_info()
	
	-- Iterate over files containing spectra info
	for i,filename in ipairs(spectrum_files) do
		load_spectra_info(filename,pixel_files,lines_files) -- Load all info from that file
	end
	
	-- Fill in fields which didn't have a cloumn in input info
	validate_spectra_info()
end

-- Read data from Pixel_info*.csv file into LUA pixel_info table
-- Columns: Measured unit,Wavelength (m),Sensitivity,Additional multiplier,Additional additive
function load_pixel_info(filename)
	db("load_pixel_info",4)
	-- Iterate over lines
	local titles
	pixel_info[filename] = {} -- initialize table for that filename
	local pixel_index = 1
	for line in io.lines(info_folder .. filename) do
		
		local non_empty = string.match(line, "([^" .. separator .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then -- empty line or only commas
			printe("load_pixel_info() | Empty line " .. tostring(pixel_index))
			goto load_pixel_info_continue -- skip line in file
		end 
		
		local values = split(line,separator) -- table of csv values
		
		if not titles then -- first line
			titles = values -- first line has titles
			
			-- initialize the tables for each title
			for i,title in ipairs(titles) do
				if title and (title ~= "") then -- ignore empty field (e.g. line end)
					pixel_info[filename][title] = {}
				else
					printe("load_pixel_info() | Empty title field " .. tostring(i))
				end
			end
			
			-- skip file if there isn't Measured unit column
			if not pixel_info[filename]["Measured unit"] then 
				pixel_info[filename] = nil
				printe("load_pixel_info() | No Measured unit column in file " .. filename)
				return 
			end
			
			-- Add 2 keys that combine experiment/camera settings for pixel-wise correction
			pixel_info[filename]["pixel_multipliers"] = {}
			pixel_info[filename]["pixel_additives"] = {}
		else
			-- Iterate over csv values in line
			for i=1, tableLength(values) do
				local title = titles[i]
				local has_title = title and (title ~= "")
				
				-- Has value but no title
				if values[i] and (values[i] ~= "") and (not has_title) then
					printe("load_pixel_info() | Empty title field " .. tostring(i) .. " but has content at line " .. tostring(pixel_index) .. " content: " .. tostring(values[i]))
				end
				
				-- Remove pixel if missing critical data, ignore columns without title; needs to be before check_pixel_info_value()
				if (title == "Measured unit") and (not tonumber(values[i])) then
					printe("load_pixel_info() | " .. filename .. " doesn't have " .. title .. " value at line " .. tostring(pixel_index))
					
					pixel_info[filename][title][pixel_index] = pixel_info[filename][title][pixel_index - 1] -- try to get data for it from last line
					
					if not pixel_info[filename][title][pixel_index] then -- hopeless case (first value missing), skip this file for pixel info
						pixel_info[filename] = nil
						
						printe("load_pixel_info() | file " .. filename .. " line " .. tostring(pixel_index) .. " column " .. tostring(i) .. " broken and file dismissed")
						return 
					end
				end
				
				-- save data in table with the key being the title
				if has_title then -- ignore empty field (e.g. line end)
					pixel_info[filename][title][pixel_index] = check_pixel_info_value(title, values[i], filename, pixel_index)
				end
			end
			
			-- Add 2 keys that combine experiment/camera settings for pixel-wise correction
			local multiplier = pixel_info[filename]["Sensitivity"][pixel_index] * pixel_info[filename]["Additional multiplier"][pixel_index]
			local additive = pixel_info[filename]["Additional additive"][pixel_index]
			pixel_info[filename]["pixel_multipliers"][pixel_index] = multiplier
			pixel_info[filename]["pixel_additives"][pixel_index] = additive
			
			pixel_index = pixel_index + 1 -- increment only if pixel had necessary info
		end
		::load_pixel_info_continue::
	end
	
	-- Write missing values as default values
	--correct_pixel_info()
end

-- In case of missing value return default value
function check_pixel_info_value(title, value, filename, pixel_index)
	db("check_pixel_info_value",5)
	local default_values = {
		["Measured unit"] = nil, -- important, needs to be first column in input file, is already checked before
		["Wavelength (m)"] = pixel_info[filename]["Measured unit"][pixel_index], -- defaults to measured unit
		["Sensitivity"] = 1,
		["Additional multiplier"] = 1,
		["Additional additive"] = 0
	}
	
	value = tonumber(value) -- number or nil
	
	if not value then
		value = default_values[title]
	end
	
	return value
end

-- Fix empty values and generate missing fields
function validate_pixel_info()
	db("validate_pixel_info",5)
	local default_values = {
		["Measured unit"] = nil,
		["Wavelength (m)"] = nil, --pixel_info[filename]["Measured unit"][pixel_index],
		["Sensitivity"] = 1,
		["Additional multiplier"] = 1,
		["Additional additive"] = 0
	}
	
	-- Iterate over pixel info in every Pixel_info*.csv file
	for filename, file_data in pairs(pixel_info) do
		
		-- Iterate over pixel_info columns
		for field, default_value in pairs(default_values) do
			
			if field == "Measured unit" then goto validate_pixel_continue end
			
			-- Generate missing sub-table
			if not file_data[field] then
				pixel_info[filename][field] = {}
				
				db("validate_pixel_info() | Pixel_info input didn't contain " .. tostring(field) .. "column in " .. tostring(filename) .. " file", 0)
			end
			
			-- Iterate over all pixels (different input files might have different amount of pixels)
			for pixel_index = 1, #file_data["Measured unit"] do
				
				-- Generate missing value from default values
				if not file_data[field][pixel_index] then
					
					if field == "Wavelength (m)" then -- take value from Measured unit column
						pixel_info[filename][field][pixel_index] = pixel_info[filename]["Measured unit"][pixel_index]
					else -- take pre-defined constant value
						pixel_info[filename][field][pixel_index] = default_value
					end
					
					db("validate_pixel_info() | Pixel_info input didn't contain " .. tostring(field) .. "column in " .. tostring(filename) .. " file for px " .. tostring(pixel_index), 0)
				end
			end
			
			::validate_pixel_continue::
		end
	end
end

-- Read data from Pixel_info*.csv file into LUA lines_info table
-- Columns: To fit (1/0),Fit priority (1 is first),Wavelength (m),function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian),Max position shift (m),Max line gwidth/hwhm (m), Chemical element,Ionization number (1 is neutrals),E_k (eV),log(A_ki*g_k/?),line index,
-- You don't need all the columns filled but the structure must remain. You need to have at least the 3 first columns filled.
function load_lines_info(filename)
	db("load_lines_info",4)
	-- Iterate over lines
	local titles
	lines_info[filename] = {} -- initialize table for that filename
	local line_index = 1 -- keeps track of how many spectral lines are to be fitted
	
	for line in io.lines(info_folder .. filename) do -- skips line if no break space is in the line
		
		local non_empty = string.match(line, "([^" .. separator .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then -- empty line or only commas
			goto load_lines_info_continue 
		end
		
		-- string to table of csv values
		local values = split(line,separator)
		
		if not titles then -- first line
			titles = values -- first line has titles
			
		else
			lines_info[filename][line_index] = {} -- initialize table for that filename
			
			-- Iterate over csv values in line
			for i=1, tableLength(values) do
				local title = titles[i]
				local has_title = title and (title ~= "")
				
				-- Has value but no title
				if values[i] and (values[i] ~= "") and (not has_title) then
					printe("load_lines_info() | Empty title field " .. tostring(i) .. " but has content at line " .. tostring(line_index) .. " content: " .. tostring(values[i]))
				end
				
				if has_title then -- ignore empty field (e.g. line end)
					lines_info[filename][line_index][title] = check_line_info_value(title, values[i]) -- save data in table with the key being the title
				end
			end
			
			-- Remove lines that aren't for fitting or are missing critical data
			if (lines_info[filename][line_index]["To fit (1/0)"] ~= 1) or (not lines_info[filename][line_index]["Wavelength (m)"]) then
				lines_info[filename][line_index] = nil
			else -- line is saved for fitting, increment index
				line_index = line_index + 1
			end
		end
		::load_lines_info_continue::
	end
	
	-- Sort lines by increasing wavelength and by increasing priority 
	local function compare_wp(a,b)
		if a["Wavelength (m)"] == b["Wavelength (m)"] then
			return (a["Fit priority (1 is first)"] < b["Fit priority (1 is first)"])
		else
			return (a["Wavelength (m)"] < b["Wavelength (m)"]) 
		end
	end
	table.sort(lines_info[filename], compare_wp)
	
	-- Write missing values as default values
	--correct_lines_info()	
	
	-- Shifts all line positions according to user defined equation
	if transform then 
		transform_line_positions(filename)
	end
end

-- In case of missing value return default value
function check_line_info_value(title, value)
	db("check_line_info_value",5)
	local default_values = {
		["To fit (1/0)"] = 1, -- important
		["Fit priority (1 is first)"] = 1,
		["Wavelength (m)"] = nil, -- important
		["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"] = "Voigt",
		["Max position shift (m)"] = 0,
		["Max line fwhm (m)"] = infinity, -- almost infinity
		["Chemical element"] = "_",
		["Ionization number (1 is neutrals)"] = 1,
		["Link parameters"] = nil
	}
	
	-- TODO: remove number option from function to fit type, enforce string
	if (title == "function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)") then -- function type can be string
		if tonumber(value) then -- it's a number
			if (value == "0") then value = "Voigt"
			elseif (value == "1") then value = "Gaussian"
			elseif (value == "2") then value = "Lorentzian"
			else -- number undefined
				printe("check_line_info_value() | Function type number out of bounds: " .. tostring(value))
				value = nil 
			end
		end
	elseif (title == "Chemical element") or (title == "Ionization number (1 is neutrals)") then -- those can be string but must be lowercase and only contain digits, letters and _
		value = string.gsub(value, "%s+", "") -- strip whitespaces
	else -- convert to number
		value = tonumber(value) -- number or nil
	end
	
	
	if not value then
		if (title == "Wavelength (m)") then -- print error if important field is missing value
			printe("check_line_info_value() | Line has no wavelength")
		end

		value = default_values[title]
	end
	
	return value
end


-- Fix empty values and generate missing fields
function validate_lines_info()
	db("validate_lines_info",5)
	local default_values = {
		["To fit (1/0)"] = 1,
		["Fit priority (1 is first)"] = 1,
		["Wavelength (m)"] = nil,
		["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"] = "Voigt",
		["Max position shift (m)"] = 0,
		["Max line fwhm (m)"] = infinity,
		["Chemical element"] = "_",
		["Ionization number (1 is neutrals)"] = 1,
		["Link parameters"] = nil
	}
	
	-- Iterate over lines info in every Lines_info*.csv file
	for filename, file_data in pairs(lines_info) do
		
		-- Iterate over all lines (different input files might have different amount of lines)
		for line_index = 1, #file_data do
		
			-- Iterate over lines_info columns
			for field, default_value in pairs(default_values) do
			
				if field == "Wavelength (m)" then goto validate_lines_continue end
				
				-- Generate missing value from default values
				if not lines_info[filename][line_index][field] then
					lines_info[filename][line_index][field] = default_value
					
					db("validate_lines_info() | Lines_info input didn't contain " .. tostring(field) .. "column for line idx " .. tostring(line_index) .. " in " .. tostring(filename) .. " file", 0)
				end
			end
			
			::validate_lines_continue::
		end
	end
end

--[[
-- Iterate over saved values and write default values if value is missing
function correct_lines_info()
	for filename,info in pairs(lines_info) do -- iterate over filenames
		if not info[""] then
			lines_info[filename][""] = 
		end
	end
end
--]]



-- Read data from Spectra_info*.csv file into LUA spectra_info table
-- Columns: Filename,Pixel correction filename,Lines filename,Background filename, Nr. of spectra accumulations,Camera pre amplification,Camera gain,Camera gate width (s),Series length,Additional multiplier,Additional additive
-- Reorder, so that filename is the key to the rest of the info
function load_spectra_info(filename,pixel_files,lines_files)
	db("load_spectra_info",4)
	-- Iterate over lines
	local titles
	for line in io.lines(info_folder .. filename) do
		
		local non_empty = string.match(line, "([^" .. separator .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then goto load_spectra_info_continue end  -- empty line or only commas
		
		local values = split(line,separator) -- table of csv values
		
		if not titles then -- first line
			titles = values -- first line has titles
		else
			local data_filename = values[1] -- get saved spectrum filename
			if (not data_filename) or (data_filename == "") then -- no filename, skip loop iteration
				printe("load_spectra_info() | No filename")
				goto load_spectra_info_continue 
			end
			
			spectra_info[data_filename] = spectra_info[data_filename] or {} -- initialize table for that filename
			
			-- Iterate over csv values in line
			for i=2, tableLength(values) do -- skip data filenames
				local title = titles[i]
				local has_title = title and (title ~= "")
				
				-- Has value but no title
				if values[i] and (values[i] ~= "") and (not has_title) then
					printe("load_spectra_info() | Empty title field " .. tostring(i) .. " but has content: " .. tostring(values[i]))
				end
				
				if has_title then -- ignore empty field (e.g. line end)
					spectra_info[data_filename][title] = check_info_value(title, values[i]) -- save data in table with the key being the title
				end
			end
			
			-- Add 2 keys that combine experiment/camera settings for spectrum-wise correction
			local additive = spectra_info[data_filename]["Additional additive"]
			local multiplier = 1 / spectra_info[data_filename]["Nr. of spectra accumulations"] / 
				actual_gain(spectra_info[data_filename]["Camera pre amplification"], spectra_info[data_filename]["Camera gain"]) / 
				spectra_info[data_filename]["Camera gate width (s)"] / spectra_info[data_filename]["Additional multiplier"]
			spectra_info[data_filename]["spectrum_additive"] = additive
			spectra_info[data_filename]["spectrum_multiplier"] = multiplier
		end
		
		::load_spectra_info_continue::
	end
	
	-- Write missing values as default values
	--correct_spectra_info(pixel_files,lines_files)
end

-- gets the right gain function based on pre amplification setting and returns the multiplier for y-axis correction.
function actual_gain(pre_amp, gain)
	return gain_functions[pre_amp](gain) -- table comes from user_constants.lua
end


-- In case of missing value return default value
function check_info_value(title, value)
	db("check_info_value",5)
	local default_values = {
		["Filename"] = nil, -- important, already checked
		["Pixel correction filename"] = nil, -- semi-important
		["Lines filename"] = nil, -- semi-important
		["Background filename"] = nil,
		["Nr. of spectra accumulations"] = 1,
		["Camera pre amplification"] = 1,
		["Camera gain"] = 0,
		["Camera gate width (s)"] = 1,
		["Series length"] = nil,
		["Additional multiplier"] = 1,
		["Additional additive"] = 0	
	}
	
	
	if (title == "Pixel correction filename") then
		value = get_sole_filename(value, pixel_info) -- nil or existing filename
	elseif (title == "Lines filename") then
		value = get_sole_filename(value, lines_info) -- nil or existing filename
	elseif (title == "Background filename") then
		-- Add file extension if it doesn't exist
		if value and (value ~= "Background_info") then
			local extens_pattern = "^.+(%.[%a%d]-)$" -- any characters (1 or more), [extracted] ., [extracted] alphanumeric characters (1 or more)
			local file_ext = string.match(value, extens_pattern)
			local has_file_end = (file_ext ~= nil)
			if not has_file_end then value = value .. file_end end -- remove file end
		end
	else -- normal value
		value = tonumber(value) -- convert string to number
	end
	
	if not value then
		value = default_values[title]
	end
	
	return value
end

-- Fix empty values and generate missing fields
function validate_spectra_info()
	db("validate_spectra_info",5)
	local default_values = {
		["Filename"] = nil,
		["Pixel correction filename"] = nil,
		["Lines filename"] = nil,
		["Background filename"] = nil,
		["Nr. of spectra accumulations"] = 1,
		["Camera pre amplification"] = 1,
		["Camera gain"] = 0,
		["Camera gate width (s)"] = 1,
		["Series length"] = nil,
		["Additional multiplier"] = 1,
		["Additional additive"] = 0	
	}
	
	-- Iterate over spectra_info
	for data_filename,_ in pairs(spectra_info) do
		
		-- Iterate over spectra_info columns
		for field, default_value in pairs(default_values) do
		
			if field == "Filename" then goto validate_spectra_continue end
			
			-- Generate missing value from default values
			if not spectra_info[data_filename][field] then
				spectra_info[data_filename][field] = default_value
				
				db("validate_spectra_info() | Spectra_info input didn't contain " .. tostring(field) .. "column for " .. tostring(data_filename) .. " file", 0)
			end
		end
		
		::validate_spectra_continue::
	end
end

-- Check if file exists and if not then return lone corresponding file in folder
function get_sole_filename(value, info_table)
	db("get_sole_filename",4)
	-- Check if file exists
	local file_exists = value and is_in_table_keys(info_table, value)
	if file_exists then return value end -- everything is ok, return same value
	
	if value then -- file specified but not found, print to error log
		printe("check_info_value() | Pixel_info or Lines_info file " .. tostring(value) .. " provided but not found in input info folder", 0)
	end
	
	-- If file doesn't exist or isn't provided then check if there's only one file in input folder and if so then use that
	if (tableLength(info_table) == 1) then
		-- Return the only filename
		local filename
		for k,_ in pairs(info_table) do filename = k end
		if filename then
			printe("Trying to use " .. tostring(filename) .. " instead", 0)
		end
		return filename
	end
end

--[[
-- Iterate over saved values and write default values if value is missing
function correct_spectra_info(pixel_files,lines_files)
	for data_filename,info in pairs(spectra_info) do -- iterate over data_filenames
		
		-- Pixel_correction file is not specified: use first (only) existing file
		if (not info["Pixel correction filename"]) and (#pixel_files == 1) then
			spectra_info[data_filename]["Pixel correction filename"] = pixel_files[1]
		end
		-- Lines file is not specified: use first (only) existing file
		if (not info["Lines filename"]) and (#lines_files == 1) then
			spectra_info[data_filename]["Lines filename"] = lines_files[1]
		end
		
		if not info["Nr. of spectra accumulations"] then
			spectra_info[data_filename]["Nr. of spectra accumulations"] = 1
		end
		if not info["Camera pre amplification"] then
			spectra_info[data_filename]["Camera pre amplification"] = 1
		end
		if not info["Camera gain"] then
			spectra_info[data_filename]["Camera gain"] = 0
		end
		if not info["Camera gate width (s)"] then
			spectra_info[data_filename]["Camera gate width (s)"] = 1
		end
		if not info["Additional multiplier"] then
			spectra_info[data_filename]["Additional multiplier"] = 1
		end
		if not info["Additional additive"] then
			spectra_info[data_filename]["Additional additive"] = 0
		end
	end
end
--]]


-- resets Fityk and asks user for run parameters
function initialize_program()
	db("initialize_program",0)
	
	-- Asks whether to use 1 experiment mode (good for debugging or line finding)
	local answer2 = F:input("Manually check 1 experiment or 1 series? [y/n]")
	
	local data_filename, experiment_check
	if answer2 == 'y' then 
		data_filename = F:input("Series (file)name: ")
		
		-- Spectra info is missing for provided filename
		if not spectra_info[data_filename] then 
			printe("initialize_program() | \"" .. tostring(data_filename) .. "\" file is not a key in spectra_info table. Has to be same as in Spectra_info*.csv")
			return
		end
		
		experiment_check = tonumber(F:input("Experiment number in the series (non-number means all): "))
		
		-- Skip processing background files. Background correction is done before pixel- and file-wise corrections, so we don't even need correction.
		if (spectra_info[data_filename]["Background filename"] == "Background_info") then 
			print("You chose background file")
		end
	end
	
	-- Asks whether you are happy with inserted values and wish to continue
	local continue_answer = F:input("Do you want to continue with the program? [y/n]")
	
	if continue_answer == 'y' then
		--[[
		-- Asks whether to overwrite and start from scratch or just append
		local answer1 = F:input("Instead of overwriting, append to the output file? [y/n]")
		
		if answer1 == 'n' then
			check_output_paths() -- avoid overwriting previous output
			init_output(data_filename) -- write column headings
		else
			output_data_name_nr = output_data_name_nr..output_data_end
		end
		--]]
		
		-- Cleans Fityk-side from everything. Equivalent to delete_all().
		reset()
		continue_answer = true
	else
		continue_answer = false
	end
	
	
	return data_filename, experiment_check, continue_answer
end


----------------------------------------------------------------------
-- Processing phase 1 - Sensitivity correction
----------------------------------------------------------------------


-- Iterates over files, fits lines and outputs data
function process_data(file_check, experiment_check)
	db("process_data", 0)
	
	-- Only check one experiment, save output with that name
	if experiment_check then
		output_data_name = "Output_" ..file_check.. "_experiment_" ..experiment_check
	end
	
	check_output_paths() -- avoid overwriting previous output
	
	-- Initialize output file
	-- TODO: no data_filename
	init_output(data_filename) -- write column headings
	
	-- Checks whether to view 1 file
	if file_check then 
		process_data_series(file_check, experiment_check)
	else
		
		-- Sort series filenames in ascending order for consistent output
		local series_filenames = {}
		for k,v in pairs(spectra_info) do table.insert(series_filenames, k) end
		table.sort(series_filenames, sort_numerical_filenames_fn)
		
		-- Iterate over all data files
		for i,data_filename in ipairs(series_filenames) do
			process_data_series(data_filename, experiment_check)
			
			if stopscript then return end
		end
	end
end

-- Processes one kinetic series/one crater. If nr of shots is larger than spectra in file then script searches other files with same filename start
-- Assumes that all spectra in series have same x-values
function process_data_series(data_filename, experiment_check)
	db("process_data_series", 1)
	
	
	-- Skip processing background files. Background correction is done before pixel- and file-wise corrections, so we don't even need correction.
	if (spectra_info[data_filename]["Background filename"] == "Background_info") then return end
	
	-- Collect the files in corrected spectra folder
	local f_end = string.gsub(file_end, "%.", "%%.") -- replace . with %. for pattern matching
	local safe_search_filename = get_safe_pattern_string(data_filename) -- escape special characters like - and +
	local patterns_or = "^" .. safe_search_filename .. "_(%d+)%-(%d+)" .. f_end .. "$" -- same input as data correction output
	local series_files = match_files(corrected_path, f_end, sort_numerical_corr_filenames_fn, patterns_or)
	
	
	-- Save corrected spectra file in separate folder
	if (tableLength(series_files) == 0) or only_correct_spectra then -- only_correct_spectra does force-overwrite
		
		-- Load in input data, do data correction and save to corrected_path
		process_raw_data_series(data_filename)
		
		-- Recheck files
		series_files = match_files(corrected_path, f_end, sort_numerical_corr_filenames_fn, patterns_or) 
		
		-- Error in saving files
		if (tableLength(series_files) == 0) then 
			printe("process_data_series() | Saving corrected files failed. Skipping series: " .. data_filename)
			return -- skip this series
		end
	end
	
	-- Mode for only correcting spectra and skipping fitting
	if only_correct_spectra then return end
	
	
	-- Get number of spectra. Errors are shown during process_raw_data_series(). You are assumed to correct your input info
	local spectra_nr = spectra_info[data_filename]["Series length"] or 1 -- how many spectra are in the series
	
	if experiment_check and (experiment_check > spectra_nr) then
		printe("process_data_series() | experiment_check is larger than dataset count. experiment_check: " .. tostring(experiment_check) .. " ; dataset count: " .. tostring(spectra_nr))
		stopscript = true
		return
	elseif experiment_check and (experiment_check < 1) then
		printe("process_data_series() | experiment_check is smaller than 1 (first experiment). experiment_check: " .. tostring(experiment_check))
		stopscript = true
		return
	end
	
	
	-- Read noise amplitude estimates from saved corrected file
	noise_stdevs = load_raw_csv(corrected_path..noise_stdevs_file..file_end)
	for i,row_table in ipairs(noise_stdevs) do
		if row_table[1] == data_filename then -- it's the line of current spectra file
			noise_stdevs = row_table
			break
		end
	end
	
	-- Convert string to number 
	for i,stdev in ipairs(noise_stdevs) do
		noise_stdevs[i] = tonumber(stdev)
	end
	
	
	-------------------------------
	-- Manage loading the spectra. Load only the necessary spectra (if not averaging over spectra then only one)
	
	-- Get the experiments to load
	local start_ind = start_experiment_nr
	local end_ind = end_experiment_nr
	if experiment_check then -- One experiment mode
		start_ind = tonumber(experiment_check)
		end_ind = tonumber(experiment_check)
	
	else -- Normal mode
		-- Default values
		start_ind = start_ind or 1 -- starts at first y-value
		end_ind = end_ind or spectra_nr -- ends with last spectrum, end_ind nr is included
		
		-- Set experiment start and end index and clip between 1 and spectra_nr
		start_ind = clip(start_ind, 1, spectra_nr)
		end_ind = clip(end_ind, 1, spectra_nr)
	end
	
	
	-- For holding tables containing the spectra batches
	local spectra1, spectra2
	local s1_start, s1_end, s2_start, s2_end -- spectra numbers saved in corrected files
	
	local moving_avg_experiment_radius = moving_average_experiment_radius or 0 -- initialize
	if moving_avg_experiment_radius > process_nr_spectra - 1 then -- limit moving window
		moving_avg_experiment_radius = math.floor(process_nr_spectra / 2)
		printe("process_data_series() | moving average over experiments currently supports max 2 experiment batches, clipped the value to " .. tostring(moving_avg_experiment_radius))
	end
	
	
	-- Initialize file index, first batch start and end indices and spectra from file
	local file_index, start_prev, end_prev
	for i, filename in ipairs(series_files) do
		s1_start, s1_end = string.match(series_files[i], "^.-_(%d+)%-(%d+)" .. f_end .. "$")
		s1_start = tonumber(s1_start)
		s1_end = tonumber(s1_end)
		
		-- Find the batch that contains current spectra or in case of averaging the first spectra in moving average
		if clip(start_ind - moving_avg_experiment_radius, 1) < s1_start then -- passed the correct batch
			file_index = i - 1 -- previous batch as the index
			s1_start, s1_end = start_prev, end_prev -- previous variables
			break
		end
		start_prev, end_prev = s1_start, s1_end -- save this round as separate variables
		
		-- Last batch
		if i == #series_files then
			-- It's in the last batch
			if (start_ind >= s1_start) and (start_ind <= s1_end) then
				file_index = i
				start_prev, end_prev = s1_start, s1_end
			
			-- Experiment doesn't exist in the files
			else
				printe("process_data_series() | file_index initialization failed. File: "..data_filename.." Start index:"..tostring(start_ind) )
				return
			end
		end
	end
	spectra1 = load_raw_spectra(corrected_path, series_files[file_index], separator)
	
	
	local nr_pixels = tableLength(spectra1) -- amount of pixels in a spectrum
	
	-- Initialize the output table and write wavelengths
	local current_spectrum = {}
	for row_index = 1, nr_pixels do -- iterate over rows
		current_spectrum[row_index] = {spectra1[row_index][1]} -- save wavelength column
	end
	
	--check_output_paths() -- avoid overwriting previous output, create one output for every series
	
	-- Iterate over spectra in series and process them one by one
	for current_spectrum_index = start_ind, end_ind do
		
		-- Index is large enough to require second batch
		if ((current_spectrum_index == start_ind) and -- Check for moving average window requiring second batch on the first iteration
			(moving_avg_experiment_radius > 0) and 
			((current_spectrum_index + moving_avg_experiment_radius) > s1_end) and 
			(file_index < tableLength(series_files)))
			or
			(((current_spectrum_index + moving_avg_experiment_radius) == (s1_end + 1)) and -- normal operations, == is necessary instead of >= because this must run only once
			(file_index < tableLength(series_files)))
			--(((current_spectrum_index + moving_avg_experiment_radius) == (s1_end + 1)) and (file_index <= tableLength(series_files)) and (series_files[file_index + 1]))
			then
				file_index = file_index + 1
				spectra2 = load_raw_spectra(corrected_path, series_files[file_index], separator)
				s2_start, s2_end = string.match(series_files[file_index], "^.-_(%d+)%-(%d+)" .. f_end .. "$")
				s2_start = tonumber(s2_start)
				s2_end = tonumber(s2_end)
		end
		
		-- If it's the last batch but input info suggests there are more then overwrite spectra_nr with the actual series length
		if (file_index == tableLength(series_files))  then -- last batch
			if s2_end then -- is initialized, therefore has at least 2 batches
				if (spectra_nr > s2_end) then -- last batch ends before input info suggests
					spectra_nr = s2_end
					printe("process_data_series() | Series is larger than input info suggests. File: "..data_filename.." File index: "..file_index.." s1_start: "..s1_start.." s1_end: "..s1_end.." s2_start: " ..tostring(s2_start).." s2_end: "..tostring(s2_end) )
				end
			elseif (spectra_nr > s1_end) then -- there's only one batch and it's smaller than input info suggests
				spectra_nr = s1_end
				printe("process_data_series() | Series is larger than input info suggests. File: "..data_filename.." File index: "..file_index.." s1_start: "..s1_start.." s1_end: "..s1_end )
			end
		end
		
		-- If there's an error in input info and actual nr of spectra is lower than expected then break the loop (finish the series)
		if (current_spectrum_index > spectra_nr) then break end
		
		
		-- Index is large enough to delete first batch. Shifts second batch into first
		if (current_spectrum_index - moving_avg_experiment_radius) > s1_end then
			spectra1 = spectra2
			s1_start = s2_start
			s1_end = s2_end
		end
		
		
		
		---------------------------- AVERAGING spectra-wise
		
		-- Initialize intensity table with zeros for sum
		local spectra_averaged_intensities = {}
		for row_index = 1, nr_pixels do -- iterate over rows and write 0 as elements
			spectra_averaged_intensities[row_index] = 0
		end
		
		-- Clip averaging at series edges
		local start_spectrum = clip(current_spectrum_index - moving_avg_experiment_radius, 1, spectra_nr)
		local end_spectrum = clip(current_spectrum_index + moving_avg_experiment_radius, 1, spectra_nr)
		
		-- Average over spectra (or load the only spectrum)
		for j = start_spectrum, end_spectrum do
			
			-- Check which batch to use
			local spectra_batch, spectrum_column 
			if (j >= s1_start) and (j <= s1_end) then -- spectra is in first batch
				spectra_batch = spectra1
				spectrum_column = j - s1_start + 2 -- +1 is from wavelength column and +1 because series starts from 1
			
			elseif (j >= s2_start) and (j <= s2_end) then -- spectra is in second batch -- TODO: check if logic works for 2nd batch with averaging
				spectra_batch = spectra2
				spectrum_column = j - s2_start + 2 -- +1 is from wavelength column and +1 because series starts from 1
			
			else -- error
				printe("process_data_series() | averaging spectrum isn't in either batch. File: "..data_filename.." Index: "..j.." s1_start: " ..s1_start.." s1_end: "..s1_end.." s2_start: " ..tostring(s2_start).." s2_end: "..tostring(s2_end) )
			end
			
			-- Iterate through the spectrum table and sum the spectra
			for row_index = 1, nr_pixels do
				spectra_averaged_intensities[row_index] = spectra_averaged_intensities[row_index] + spectra_batch[row_index][spectrum_column]
			end
		end
		
		-- Divide sum by number of summed spectra
		if moving_avg_experiment_radius > 0 then
			for row_index = 1, nr_pixels do
				spectra_averaged_intensities[row_index] = spectra_averaged_intensities[row_index] / (end_spectrum - start_spectrum + 1)
			end
		end
		
		---------------------------- AVERAGING pixel-wise
		
		
		
		-- Average the intensities pixel-wise
		local averaged_intensities
		local moving_avg_pixels_radius = moving_average_pixels_radius or 0
		if moving_avg_pixels_radius > 0 then
			
			-- Initialize pixel-wise averaged spectrum
			averaged_intensities = {}
			for row_index = 1, nr_pixels do -- iterate over rows and write 0 as elements
				averaged_intensities[row_index] = 0
			end
			
			-- Iterate over pixels to be saved
			for row_index = 1, nr_pixels do
				
				-- Clip averaging at spectrum edges
				local start_px = clip(row_index - moving_avg_pixels_radius, 1, nr_pixels)
				local end_px = clip(row_index + moving_avg_pixels_radius, 1, nr_pixels)
				
				-- Sum over pixels
				local summed_px = 0
				for i = start_px, end_px do
					summed_px = summed_px + spectra_averaged_intensities[i]
				end
				averaged_intensities[row_index] = summed_px / (end_px - start_px + 1) -- finalize averaging
			end
		
		else -- no averaging pixel-wise, pass the table
			averaged_intensities = spectra_averaged_intensities
		end
		
		---------------------------- AVERAGING END
		
		-- Save the averaged spectrum into current_spectrum
		for row_index = 1, nr_pixels do
			current_spectrum[row_index][2] = averaged_intensities[row_index]
		end
		
		
		-- Load the spectrum into GUI
		dataset_from_table(current_spectrum, data_filename, current_spectrum_index)
		
		
		-- Process the spectrum (fitting)
		process_spectrum(data_filename, current_spectrum_index, experiment_check)
		if stopscript then return end -- stop the script
		
		
		-- Stop the loop if using 1 experiment view or user wants to stop the script
		if experiment_check then
			print("Stopping the script after 1 experiment check")
			stopscript = true
			return 
		end
		
		if (not experiment_check) then
			delete_dataset(0)
			delete_variables() -- Deletes all variables. This wasn't done with deleting functions and it kept hogging resources. Now long processes take c.a 60x less time
		end
		
	end
	
	
	print("Series ".. data_filename .." done.")
	
	-- Resets all Fityk-side info (not LUA-side, that holds all necessary info)
	reset()
end


-- Read raw data, process it and save corrected spectra into new file in the same format
function process_raw_data_series(data_filename)
	db("process_raw_data_series", 2)
	
	local noise_stdevs -- save noise estimates separately because sensitivity correction might lose that info
	
	-- Get files with data_filename beginning
	--[[
	local series_files = {}
	local f_end = string.gsub(file_end, "%.", "%%.") -- replace . with %. for pattern matching
	for filename in io.popen("dir \"" .. input_path .. "\" /b"):lines() do
		
		-- Spectra_info*.csv (.* means any character as much as possible and $ is end of string)
		-- abc_P1.txt is matched with abc_P10.txt in using data_filename .. ".*" .. f_end
		local direct_match = string.match(filename, "^" .. data_filename .. f_end .. "$") -- no number added to name
		local numeric_filename = string.match(filename, "^" .. data_filename .. "%D+%d+" .. f_end .. "$") -- number added to name and is separated by non-number
		if direct_match or numeric_filename then 
			table.insert(series_files, filename)
		end
	end
	table.sort(series_files) -- Sort filenames in ascending order for shot to correlate with file number
	--]]
	
	-- Get files with data_filename beginning
	local patterns_or = {}
	local f_end = string.gsub(file_end, "%.", "%%.") -- replace . with %. for pattern matching
	
	-- "abc_P10.txt" and "abc_P1_001.txt" need to be different
	-- and "abc_001.txt" and "abc_d_001.txt" need to be different
	local safe_search_filename = get_safe_pattern_string(data_filename) -- escape special characters like - and +
	table.insert(patterns_or, "^" .. safe_search_filename .. f_end .. "$") -- direct match
	table.insert(patterns_or, "^" .. safe_search_filename .. "_%d+" .. f_end .. "$") -- numeric increment match, assumes Sophi nXt export ("_0001" appended)
	local series_files = match_files(input_path, f_end, sort_numerical_filenames_fn, patterns_or)
	
	local target_nr = spectra_info[data_filename]["Series length"] or 1 -- how many spectra are in the series
	local file_batches = {}
	local batch_names = {}
	
	if target_nr > process_nr_spectra then -- too many spectra to read into memory, process as batches
		local saved_nr = 0 -- how many spectra are saved in all previous batches combined
		local current_nr = 0 -- how many spectra are saved in current batch
		local batch_files = {}
		
		-- Iterate over files and save filenames into batches according to process_nr_spectra
		for i,filename in ipairs(series_files) do
			
			-- Read how many spectra are in the file
			local nr_of_spectra_in_file = 0
			local file = io.open(input_path..filename, "r")
			local line = file:read() 
			nr_of_spectra_in_file = tableLength(split(line,input_data_separator), true) - 1 -- get columns nr in file minus wavelength column
			io.close(file)
			
			if (nr_of_spectra_in_file > 0) then
				if (saved_nr + nr_of_spectra_in_file) > target_nr then
					printe("process_raw_data_series() | too many spectra in files vs known series length. Trying to read " .. filename)
					break -- results in underpopulated series
				end
				
				-- TODO: split big file into multiple column "files"
				-- File fits into batch, add this file to the batch
				if ((current_nr + nr_of_spectra_in_file) <= process_nr_spectra) then
					table.insert(batch_files, filename)
					current_nr = current_nr + nr_of_spectra_in_file
				
				else -- Batch can't fit this file, save the batch and start a new one with this file
					
					-- Save previous batch
					if current_nr > 0 then -- save batch if there's something to save
						table.insert(file_batches, batch_files)
						table.insert(batch_names, data_filename.."_"..(saved_nr + 1).."-"..(saved_nr + current_nr))
					end
					
					-- Start new batch and increment statistics
					batch_files = {filename}
					saved_nr = saved_nr + current_nr
					current_nr = nr_of_spectra_in_file
					
					if (current_nr > process_nr_spectra) then
						printe("process_raw_data_series() | too big file for batch processing spectra. Trying to read " .. filename, 0)
						
						if current_nr > 0 then -- save batch if there's something to save
							table.insert(file_batches, batch_files)
							table.insert(batch_names, data_filename.."_"..(saved_nr + 1).."-"..(saved_nr + current_nr))
						end
					end
				end
			else
				printe("process_raw_data_series() | Empty file. Trying to read " .. filename)
			end
		end
		
		-- Save last batch
		table.insert(file_batches, batch_files)
		table.insert(batch_names, data_filename.."_"..(saved_nr + 1).."-"..(saved_nr + current_nr))
		
		if (saved_nr + current_nr) < target_nr then
			printe("process_raw_data_series() | too few spectra in files vs known series length. Trying to read: " .. data_filename)
			printe("Old Input_data_corrected file?")
		end
		
		target_nr = nil -- don't compare spectra amount in load_raw_series()
		
	else -- can process all spectra at once
		file_batches[1] = series_files
		
		-- Read how many spectra are in the series
		local nr_of_spectra_in_file = 0
		for i = 1, tableLength(series_files) do
			local file = io.open(input_path .. series_files[i], "r")
			local line = file:read() 
			nr_of_spectra_in_file = nr_of_spectra_in_file + tableLength(split(line,input_data_separator), true) - 1 -- get columns nr in file minus wavelength column
			io.close(file)
		end
		
		-- Catch errors in input info vs actual series length
		local target_nr = spectra_info[data_filename]["Series length"] or 1
		if nr_of_spectra_in_file > target_nr then
			printe("process_raw_data_series() | too many spectra in files vs known series length. Trying to read: " .. data_filename)
		end
		if nr_of_spectra_in_file < target_nr then
			printe("process_raw_data_series() | too few spectra in files vs known series length. Trying to read: " .. data_filename)
		end
		
		batch_names[1] = data_filename.. "_1-" ..nr_of_spectra_in_file
	end
	
	-- Gather all noise stdevs from series
	local series_noise_stdevs = {}
	
	-- Iterate over file batches and save the processed spectra in batches
	for i,file_batch in ipairs(file_batches) do
		local batch_name = batch_names[i] or data_filename
		
		-- Read input series into table
		local data_table = load_raw_series(file_batch, target_nr)
		
		if (not data_table) or (tableLength(data_table) == 0) then
			printe("process_raw_data_series() | data_table is nil when using batch: " .. tostring(batch_name))
			return
		end
		
		-- Do file- and pixel-wise correction
		local noise_stdevs
		data_table, noise_stdevs = data_correction(data_table, data_filename)
		series_noise_stdevs = tableConcat(series_noise_stdevs, noise_stdevs) -- concatenate the tables
		
		-- Save corrected spectra into new file
		save_corrected_spectra(data_table, batch_name)
	end
	
	-- Save noise estimates
	save_noise_stdevs(data_filename, series_noise_stdevs)
end

-- Read data from original spectra series (on or multiple files) into LUA table
-- For many large files this results in out of memory error, need to process piece by piece
-- Columns: measured unit (px or m), intensity1, intensity2, intensity3...
function load_raw_series(series_files, target_nr)
	db("load_raw_series", 3)
	
	
	local loaded_spectra = 0
	local data_table = {}
	
	-- Get number of pixels in spectra
	--local pixel_count = 0
	--for _ in io.lines(series_files[1]) do
	--  pixel_count = pixel_count + 1
	--end
	
	-- Iterate over files containing spectra
	for n,filename in ipairs(series_files) do
		
		if target_nr and (loaded_spectra >= target_nr) then
			printe("load_raw_series() | too many files vs known series length. Trying to read " .. filename)
			break
		end
		
		-- Load rows and columns into 2D array
		local file_data_table = load_raw_spectra(input_path, filename, input_data_separator)
		
		if file_data_table then
			if (tableLength(data_table) == 0) then
				data_table = file_data_table
			else
				-- Merge spectra into one table
				for i, row in ipairs(file_data_table) do
					for j, value in ipairs(row) do
						if j > 1 then -- first column is wavelength, skip that for all but first spectrum
							table.insert(data_table[i], value)
							loaded_spectra = loaded_spectra + 1
						end
					end
				end
			end
			loaded_spectra = tableLength(data_table[1]) - 1 -- first column is wavelength
			
			-- Check spectra number
			if target_nr and (loaded_spectra > target_nr) then
				printe("load_raw_series() | file " .. filename .. " contained too many spectra")
			end
		end
	end
	
	if target_nr and (loaded_spectra < target_nr) then
		printe("load_raw_series() | too few spectra in files vs known series length")
	end
	
	return data_table
end

-- Read data from spectra file into LUA table and converts values to numbers
-- Columns: measured unit (px or m), intensity1, intensity2, intensity3...
function load_raw_spectra(path, filename, separ)
	db("load_raw_spectra",4)
	
	if (not path) or (not filename) then return end
	
	local filepath = path..filename
	
	if not file_exists(filepath) then return end
	
	local data_table = {}
	
	-- Iterate over lines
	for line in io.lines(filepath) do
		
		-- Check if row is empty
		local non_empty = string.match(line, "([^" .. separ .. "]+)") -- ignore separators
		
		-- Skip empty line or only commas or comments
		if (not line) or (line == "") or (not non_empty) then goto load_raw_data_continue end  
		
		local values = split(line,separ) -- table of csv values
		
		-- Assumption: Data row has at least x and y columns filled with numbers
		local is_data = tonumber(values[1]) and tonumber(values[2])
		if (not is_data) then goto load_raw_data_continue end  -- skip file comments
		
		-- Account for line ending comma
		if (values[tableLength(values)] == "") then
			table.remove(values, tableLength(values))
		end
		
		-- Convert read strings to numbers
		for i,value in ipairs(values) do
			values[i] = tonumber(value)
		end
		
		-- Save the row into data_table
		table.insert(data_table, values)
		
		::load_raw_data_continue::
	end
	
	return data_table
end

-- Do file- and pixel-wise correction on spectra in table
function data_correction(data_table, data_filename)
	db("data_correction", 4)
	
	-- Background correction before other stuff
	data_table = subtract_background(data_table, data_filename)
	
	-- Load pixel-wise corrections info
	local multipliers, additives, wavelengths, avg_sensitivity_at_signal
	local pixel_info_filename = spectra_info[data_filename]["Pixel correction filename"]
	if pixel_info_filename then -- file with correction info exists
		
		-- Check for errors in pixel_info file
		if (tableLength(pixel_info[pixel_info_filename]["Measured unit"]) ~= tableLength(data_table)) then
			printe("data_correction() | Number of pixels doesn't match the number of correct rows in Pixel_info file when using " .. tostring(data_filename))
		end
		
		-- Corrections info
		multipliers = pixel_info[pixel_info_filename]["pixel_multipliers"]
		additives = pixel_info[pixel_info_filename]["pixel_additives"]
		wavelengths = pixel_info[pixel_info_filename]["Wavelength (m)"]
		
		-- Estimate sensitivity 
		local center_pixel_index = math.floor(tableLength(multipliers) / 2)
		avg_sensitivity_at_signal = (multipliers[center_pixel_index] + multipliers[center_pixel_index - 1] + multipliers[center_pixel_index + 1]) / 3
	else
		avg_sensitivity_at_signal = 1
		printe("data_correction() | Pixel correction filename missing, skipping pixel intensity and wavelength correction for "..tostring(data_filename))
	end
	
	-- Finds line detection threshold before sensitivity and x-axis correction
	local noise_stdevs
	if noise_before_sensitivity_correction then
		noise_stdevs = estimate_noise_amplitude(data_table, avg_sensitivity_at_signal)
	end
	
	-- File-wise correction (e.g. gate width and gain)
	local spectrum_multiplier = spectra_info[data_filename]["spectrum_multiplier"]
	local spectrum_additive = spectra_info[data_filename]["spectrum_additive"]
	
	-- Iterate over data_table and do file-wise and pixel-wise corrections
	for row, row_table in ipairs(data_table) do
		for column, value in ipairs(row_table) do
		
			-- Do correction for each data point
			if column == 1 then -- x-correction
				
				-- Pixel to wavelength
				if pixel_info_filename then -- file with pixel-wise correction info exists
					data_table[row][column] = wavelengths[row] 
				end
			
			else -- y-correction
				
				-- Pixel-wise correction
				local multiplier, additive
				if pixel_info_filename then -- File with pixel-wise correction info exists
					multiplier = spectrum_multiplier * multipliers[row]
					additive = spectrum_additive + additives[row]
				end
				
				-- Modifies y-points
				data_table[row][column] = tonumber(value) * multiplier + additive
			end
		end
	end
	
	-- Finds line detection threshold after sensitivity and x-axis correction
	if not noise_before_sensitivity_correction then
		noise_stdevs = estimate_noise_amplitude(data_table)
	end
	
	return data_table, noise_stdevs
end

-- Subtract background from spectra if it's defined. Do this before other corrections, assuming that background is taken at same parameters as data.
function subtract_background(data_table, data_filename)
	db("subtract_background", 4)
	
	local background_file = spectra_info[data_filename]["Background filename"]
	if (not background_file) or (background_file == "") then return data_table end -- skip quietly when file isn't specified
	
	local background_table = load_raw_spectra(input_path, background_file, input_data_separator)
	
	if not background_table then
		printe("subtract_background() | background_table is nil when using " .. tostring(data_filename))
		return data_table
	end
	
	-- Check if background and data spectrum have same x-values
	if (background_table[1][1] ~= data_table[1][1]) or (tableLength(background_table) ~= tableLength(data_table)) then 
		printe("subtract_background() | Background and data spectrum have different x-values, skipping background correction")
		return data_table
	end
	
	-- Iterate over background_table and average y-columns
	local averaged_background = {}
	for row, row_table in ipairs(background_table) do
		
		-- Sum together backgrounds in kinetic series
		local sum = 0
		local count = 0
		for column, value in ipairs(row_table) do
			if (column ~= 1) and tonumber(value) then -- y-coordinate
				sum = sum + tonumber(value)
				count = count + 1
			end
		end
		
		-- Divide by series length (get average) and write to output
		averaged_background[row] = sum / count
	end
	
	-- Iterate over data_table and do background-correction
	for row, row_table in ipairs(data_table) do
		for column, value in ipairs(row_table) do
			if (column ~= 1) then -- y-coordinate
				data_table[row][column] = value - averaged_background[row]
			end
		end
	end
	
	return data_table
end

-- Finds line detection threshold. Needs to be before y-correction because then the pure-noise edges might be cut off by sensitivity.
function estimate_noise_amplitude(data_table, avg_sensitivity_at_signal)
	db("estimate_noise_amplitude", 4)
	
	if not avg_sensitivity_at_signal then 
		avg_sensitivity_at_signal = 1 
	end
	
	
	if noise_estimate_start and noise_estimate_end then
		local noise_table = {} -- table of intensity tables. Each table has intensities of that experiment
		
		-- Iterate over data_table
		for row, row_table in ipairs(data_table) do
			
			if (row_table[1] >= noise_estimate_start) and (row_table[1] <= noise_estimate_end) then -- check measured units (x)
				for column, value in ipairs(row_table) do
					
					if column ~= 1 then -- is y-point
						noise_table[column - 1] = noise_table[column - 1] or {} -- initialize experiment intensities-table (starts from 1)
						table.insert(noise_table[column - 1], value)
					end
				end
			end
		end
		
		-- Calculate stdev of each intensity table
		local noise_stdevs = {}
		for i,int_table in ipairs(noise_table) do
			table.insert(noise_stdevs, stats.standardDeviation(int_table) * avg_sensitivity_at_signal) -- TODO: additional_multiplier?
		end
		
		return noise_stdevs
	end
end

-- Save corrected spectra and noise estimates
function save_corrected_spectra(data_table, batch_name)
	db("save_corrected_spectra", 2)
	
	-- Open new file for corrected spectra
	local file2 = io.open(corrected_path..batch_name..file_end,"w")
	io.output(file2)
	
	-- Iterate over data_table and write corrected spectra into the new file
	for row, row_table in ipairs(data_table) do
		for column, value in ipairs(row_table) do
			io.write(tostring(value))
			if data_table[row][column+1] then -- don't write comma to the end of the line
				io.write(",")
			end
		end
		if data_table[row+1] then -- don't write endline if it's the end of file
			io.write("\n")
		end
	end
	
	io.close(file2)
end

-- Save noise estimates
function save_noise_stdevs(data_filename, series_noise_stdevs)
	db("save_noise_stdevs", 2)
	
	local filepath = corrected_path..noise_stdevs_file..file_end
	
	-- Create file if needed
	local init_file = io.open(filepath,"a")
	io.close(init_file)
	
	-- check if stdevs for that file are already saved
	local is_saved = false
	for line in io.lines(filepath) do
		local values = split(line,separator) -- table of csv values
		if values[1] == data_filename then 
			is_saved = true
		end
	end
	
	-- If stdevs for current spectra file isn't in the file, add it
	if not is_saved then
		-- Write stdevs into separate file
		local file1 = io.open(filepath,"a")
		io.output(file1)
		
		-- Write noise stdevs
		if series_noise_stdevs then
			io.write("\n" .. data_filename..separator) -- filename
			for i,stdev in ipairs(series_noise_stdevs) do
				io.write(tostring(series_noise_stdevs[i]))
				if series_noise_stdevs[i+1] then -- don't write comma to the end of the line
					io.write(separator)
				end
			end
		end
		io.close(file1)
	end
end


----------------------------------------------------------------------
-- Processing phase 2 - after sensitivity correction
----------------------------------------------------------------------

-- Create a dataset from the provided table, takes 1st column of x-values and 2nd column of y-values
function dataset_from_table(data_table, filename, spectrum_index, dataset_nr)
	db("dataset_from_table", 3)
	
	-- Select the dataset
	dataset_nr = dataset_nr or 0
	F:execute("use @" .. dataset_nr)
	
	F:execute("M = "..tostring(tableLength(data_table))) -- create points
	
	-- Change points from last index to first because modifying x-point modifies its index too. All points are x=0 at first.
	for row_index = tableLength(data_table), 1, -1 do
		local value_table = data_table[row_index]
		F:execute("X["..tostring(row_index - 1).."] = "..tostring(value_table[1])) -- Give x-points values, first is x[0]
		F:execute("Y["..tostring(row_index - 1).."] = "..tostring(value_table[2])) -- Give y-points values, first is y[0]
	end
	
	-- Rename the dataset, so that output image looks better
	F:execute("@0: title = \'"..tostring(filename)..","..tostring(spectrum_index).."\'") -- experiment starts at 1 by default
	
	--F:execute("@+ <\'" ..filepath.. "\':1:" .. startstr .. ".." .. endstr .. "::") -- Loads multiple experiments from file. 
end

-- Check whether user wants to stop the script while it's still running
function check_stopscript()
	local stopfile = io.open(info_folder..stopscript_name,"r")
	io.input(stopfile)
	local content = io.read()
	io.close(stopfile)
	if content then
		stopscript = true
		print("Stopping the script since "..stopscript_name.." isn't empty")
		return
	end
end

-- Do stuff for one spectrum
function process_spectrum(data_filename, spectrum_index, experiment_check)
	db("process_spectrum", 2)
	
	-- Move the view onto the data
	F:execute("plot @0")
	
	-- Check whether user wants to stop the script while it's still running
	check_stopscript()
	if stopscript then return end -- stop the script
	
	-- Get the noise amplitude estimate for current experiment
	noise_stdev = noise_stdevs[spectrum_index + 1] or 0 -- 1st value in noise_stdevs is filename
	
	if stop_before_lines then
		print("Stopping the script before line fitting")
		stopscript = true
		return
	end
	
	print("Fitting experiment: "..data_filename..separator..tostring(spectrum_index))
	
	-- Generates and fits functions
	local minimal_data_value, max_constant_value, max_height_values, angle_errors, polyline_values = fit_functions(data_filename)
	
	-- Check whether user wants to stop the script while it's still running
	check_stopscript()
	if stopscript then return end -- stop the script
	
	-- Saves functions' errors into arrays
	local errors = get_errors(data_filename, minimal_data_value, max_constant_value, max_height_values, angle_errors)
	
	-- Generate polyline as local constants in order to visualize the calculations in the sessions file and to read noise more easily.
	create_polyline_local_constant(polyline_values)
	
	-- Write weak lines as 0-height before write_output()
	if nullify_weak_lines_data then
		nullify_lines()
	end
	
	-- Writes data into output file
	write_output(data_filename, spectrum_index, errors)	
	
	-- Write weak lines as 0-height after write_output()
	if nullify_weak_lines_visual and (not nullify_weak_lines_data) then
		nullify_lines()
	end
	
	-- Save the session in case there's bad fit
	if save_sessions then
		F:execute("info state > \'" ..sessions_path..data_filename..separator..spectrum_index.. ".fit\'")
	end
	
	-- Plots current dataset with functions
	if plot then plot_functions(data_filename, spectrum_index) end
	
	print("Experiment: "..data_filename..separator..spectrum_index.." done.")
	
	-- Stop at current file for debugging
	if stop then 
		if F:input("Stop at file "..data_filename.."? [y/n]")  == 'y' then 
			print("Stopping the script because of your input")
			stopscript = true
			return
		end
	end
	
	-- Stop the loop if using 1 experiment view or user wants to stop the script
	if experiment_check then
		print("Stopping the script after 1 experiment check")
		stopscript = true
		return 
	end
	
	if (not experiment_check) then
		delete_dataset(0)
		delete_variables() -- Deletes all variables. This wasn't done with deleting functions and it kept hogging resources. Now long processes take c.a 60x less time
	end
	
end

-- Read data from original spectra file into LUA table
function load_raw_csv(filepath)
	db("load_raw_csv",3)
	
	if not file_exists(filepath) then return end
	
	local csv_table = {}
	
	-- Iterate over lines
	for line in io.lines(filepath) do
		
		-- Check if row is empty
		local non_empty = string.match(line, "([^" .. input_data_separator .. "]+)") -- ignore separators
		
		-- Skip empty line or only commas or comments
		if (not line) or (line == "") or (not non_empty) then goto load_raw_csv_continue end  
		
		local values = split(line,input_data_separator) -- table of csv values
		
		-- Account for line ending comma
		if (values[tableLength(values)] == "") then
			table.remove(values, tableLength(values))
		end
		
		-- Save the row into csv_table
		table.insert(csv_table, values)
		
		::load_raw_csv_continue::
	end
	
	return csv_table
end

-- Register boundaries for the spectrum
function register_spectrum_boundaries()
	db("register_spectrum_boundaries", 4)
	
	-- Select first dataset
	F:execute("use @0")
	
	startpoint = cut_start or F:calculate_expr("min(X)") -- first pixel as startpoint
	endpoint = cut_end or F:calculate_expr("max(X)") -- last pixel as end
end



----------------------------------------------------------------------
-- Fitting phase
----------------------------------------------------------------------


-- Line fitting for 1 constant and the Voigt/Gaussian/Lorentzian profiles defined for functions
function fit_functions(data_filename)
	db("fit_functions", 1)
	
	
	-- Register the boundaries for line fitting and output image
	register_spectrum_boundaries()
	
	-- Fit constant first, select datapoints for that
	if (noise_estimate_start ~= -infinity) or (noise_estimate_end ~= infinity) and (not noise_before_sensitivity_correction) then -- at least one is defined and data exists after correction
		-- Select/unselect dataset points at location where should be few and only weak lines
		select_active_points(noise_estimate_start, noise_estimate_end)
	else -- no region, use all datapoints in spectrum window
		select_active_points(startpoint, endpoint)
	end
	
	-- Table to hold info for each line and each parameter of that line whether it was simple, locked or compound variable
	-- variable_types[line_index] = {0 = {"name" = variable_name, "v_type" = variable_type}, 1 = ...}
	local variable_types, angle_errors = {}, {}
	angle_errors.bg_local = {} -- for temporary secondary background
	angle_errors.bg_local.value = {}
	angle_errors.bg_local.error = {}
	
	-- Activate all dataset points
	select_active_points(startpoint, endpoint)
	
	-- Constant tries to account for wide lines. The constant is bound between minimal data value
	-- and maximum defined data value (percentile). Otherwise constant is fitted too high because of wide lines.
	-- Lowest constant bound
	local minimal_data_value = F:calculate_expr("min(y if a)")
	if minimal_data_value < 0 then minimal_data_value = 0 end -- physical constraint
	-- Highest constant bound
	local max_constant_value = F:calculate_expr("centile("..tostring(high_constant_bound_percentile)..", y if a)") -- percentile
	if max_constant_value < 0 then max_constant_value = 0 end -- physical constraint
	
	-- Constant angle variable, starts from 3pi/2 so that sin is minimal
	--F:execute("$constant_variable = ~4.712")
	
	-- Binds constant to be fitted between defined percentile and (minimal data value or 0)
	-- equation: constant = (maximum + minimum) / 2 + (maximum - minimum) / 2 * sin(~angle)
	--local constant_parameters = tostring((max_constant_value + minimal_data_value) / 2).." + "..tostring((max_constant_value - minimal_data_value) / 2).."*sin($constant_variable)"
	--F:execute("guess %bg = Constant(a = "..tostring(constant_parameters)..")") -- background continuum
	
	-- Lock constant to minimal_data_value, since local constants are generated on top of it
	F:execute("guess %bg = Constant(a = "..tostring(minimal_data_value)..")") -- background continuum
	
	-- Fit constant
	--F:execute("@0: fit")
	
	-- Lock constant value for fitting lines and save error before it's lost due to locking
	local constant_angle_error = 0 --F:calculate_expr("$constant_variable.error") -- save uncertainty
	--F:execute("$constant_variable = {$constant_variable}")
	
	-- Save the error
	angle_errors[0] = constant_angle_error
	
	-- Add a polyline (local constants) to raise the line functions back to original height. Alternative
	-- is to use Rectangle functions after fitting.
	local polyline_values = {}
	
	-- Process only a part of spectrum at a time. Get first line (sorted by wavelength) and fit only that and lines that are in its influence diameter
	
	-- Iterates over spectral lines and generates them as functions
	local constant_value_temp
	local max_height_values = {}
	local lines_info_filename = spectra_info[data_filename]["Lines filename"]
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		
		-- Check whether user wants to stop the script while it's still running
		check_stopscript()
		if stopscript then  -- stop the script
			print("WARNING: the last line in output file is probably incomplete")
			return 
		end
		
		local line_position = info["Wavelength (m)"]
		
		-- Get current line's influence diameter
		local second_order_multiplier = 1.5 -- multiply influence diameter because influencing line might be influenced by another further away -- TODO: make this constant more transparent to user
		local beginning = line_position - max_line_influence_diameter * second_order_multiplier
		local ending = line_position + max_line_influence_diameter * second_order_multiplier
		if forbid_lines_outside_range then
			beginning = clip(beginning, cut_start, cut_end)
			ending = clip(ending, cut_start, cut_end)
		end
		
		-- Prevent crash with line being so far that it's out of range and there's even no active datapoints
		local minimal_data_value_temp, max_constant_value_temp, constant_parameters_temp, poly_tbl, influenced_line_indices -- define before goto to prevent errors
		if (ending < cut_start) or (beginning > cut_end) then -- TODO: still crashes when creating line outside of dataset
			--goto skip_dummy_fit 
		end
		
		-- Get lines in current line's influence diameter
		influenced_line_indices = get_lines_in_range(lines_info[lines_info_filename], line_position, ending) -- use only the current line and lines to the right because others are already fitted and locked
		
		
		-- Activate dataset points in the diameter
		select_active_points(beginning, ending)
		
		-- Unlock the variables of those lines or create new ones if they don't exist
		-- Writes into variable_types and max_height_values tables
		activate_local_lines(influenced_line_indices, lines_info_filename, minimal_data_value, variable_types, max_height_values)
		
		-- Skip loop if it's a dummy
		if not variable_types[line_index] then -- is dummy function
			goto skip_dummy_fit
		end
		
		----------------------------------------------------------
		-- Fit local secondary and temporary constant 
		-- Local secondary and temporary constant to account for varying background/continuum signal. 
		-- The constant is bound between local minimal data value and maximum defined data value (percentile). 
		-- Otherwise constant is fitted too high because of wide or high lines.
		-- Lowest constant bound
		minimal_data_value_temp = F:calculate_expr("min(y if a)") - minimal_data_value
		if minimal_data_value_temp < 0 then minimal_data_value_temp = 0 end -- physical constraint
		-- Highest constant bound
		max_constant_value_temp = F:calculate_expr("centile("..tostring(high_constant_bound_percentile)..", y if a)") - minimal_data_value -- percentile
		if max_constant_value_temp < 0 then max_constant_value_temp = 0 end -- physical constraint
		
		-- Constant angle variable, starts from 3pi/2 so that sin is minimal
		F:execute("$constant_variable_local = ~4.712")
		
		-- Binds constant to be fitted between defined percentile and (minimal data value or 0)
		-- equation: constant = (maximum + minimum) / 2 + (maximum - minimum) / 2 * sin(~angle)
		constant_parameters_temp = tostring((max_constant_value_temp + minimal_data_value_temp) / 2).." + "..tostring((max_constant_value_temp - minimal_data_value_temp) / 2).."*sin($constant_variable_local)"
		F:execute("guess %bg_local = Constant(a = "..tostring(constant_parameters_temp)..")") -- background
		
		----------------------------------------------------------
		
		-- fit 2x to avoid local minima, catch error in case only dummies are to be fitted
		wrap(function() 
			--F:execute("@0: fit")
			F:execute("@0: fit")
		end)
		
		-- Check the current line area. If not according to requirements (stronger than noise) the line height is written as 0.
		--remove_invalid_line(line_index, variable_types, noise_stdev)
		
		-- Calculate value and error
		constant_value_temp = F:calculate_expr("%bg_local.a")
		angle_errors.bg_local.value[line_index] = constant_value_temp
		if (constant_value_temp == minimal_data_value_temp) or (constant_value_temp == max_constant_value_temp) then -- stopped by the bounds
			angle_errors.bg_local.error[line_index] = 0
		
		else -- ordinary fit
			local angle_error = F:calculate_expr("$constant_variable_local.error") -- save uncertainty
			angle_errors.bg_local.error[line_index] = math.abs((max_constant_value_temp - minimal_data_value_temp) / 2 * math.cos(constant_value_temp) * angle_error)
		end
		
		-- Add the local constant into polyline for session output
		poly_tbl = {["start"] = beginning, ["ending"] = ending, ["height"] = constant_value_temp}
		table.insert(polyline_values, poly_tbl)
		
		-- Delete the temporary background constant in order not to mess up line indices
		F:execute("delete %bg_local")
		
		::skip_dummy_fit::
		
		-- Lock the variables of those lines
		-- Writes into angle_errors table
		lock_lines(line_index, influenced_line_indices, lines_info_filename, variable_types, angle_errors)
	end
	
	
	-- Iterates over lines and checks their area. If not according to requirements (stronger than noise) the line height is written as 0.
	--remove_invalid_lines(lines_info_filename, minimal_data_value)
	
	return minimal_data_value, max_constant_value, max_height_values, angle_errors, polyline_values
end


-- Get function name by index
function get_fn_name(lines_info_filename, line_index)
	db("get_fn_name",4)
	local sig_numbers = 6
	
	-- TODO: delete Ionization and just rename element to identificator
	
	-- Get function name
	local identifier = lines_info[lines_info_filename][line_index]["Chemical element"]
	--local ionization = ""
	--if identifier ~= "_" then -- line is identified
		--ionization = lines_info[lines_info_filename][line_index]["Ionization number (1 is neutrals)"]
	--end
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	--local function_name = identifier..ionization.. "_" .. decimalToInteger(line_position, sig_numbers) -- Fityk doesn't allow anything else besides digits, letters and _. Outputs function name in pm.
	
	-- Fityk doesn't allow anything else besides digits, letters and _. Outputs function name in pm.
	local function_name = identifier.. "_" .. decimalToInteger(line_position, sig_numbers) 
	
	-- Check for duplicate locations. If they exist then append "_x" to the end of name. Otherwise old line gets rewritten instead of new being made.
	local similar_lines_nr = 0
	for i, info in ipairs(lines_info[lines_info_filename]) do
		local pos = info["Wavelength (m)"]
		
		if i >= line_index then break -- only read up to current line_index
		else 
			if (identifier == info["Chemical element"]) and 
				(decimalToInteger(line_position, sig_numbers) == decimalToInteger(pos, sig_numbers)) then
				similar_lines_nr = similar_lines_nr + 1
			end
		end
	end
	similar_lines_nr = (similar_lines_nr > 0) and ("_" ..similar_lines_nr) or ""
	local output_name = function_name.. similar_lines_nr
	
	--[[
	-- Check for duplicate names. If they exist then append "_x" to the end of name. Otherwise old line gets rewritten instead of new being made.
	local existing_line = function_name and F:get_function(function_name)
	if existing_line then
		local count = 1
		local new_name = function_name .. "_" .. tostring(count)
		
		-- Iterate indices until no line with that one exists
		while existing_line do
			output_name = new_name
			new_name = function_name .. "_" .. tostring(count)
			
			count = count + 1
			existing_line = function_name and F:get_function(new_name)
		end
	end
	--]]
	
	return output_name
end

-- Unlock existing lines or create a new line in dataset
function activate_local_lines(line_indices, lines_info_filename, minimal_data_value, variable_types, max_height_values)
	db("activate_local_lines",2)
	
	-- Iterate over the lines
	for i, line_index in ipairs(line_indices) do
		
		--local line_info = lines_info[lines_info_filename][line_index]
		local function_name = get_fn_name(lines_info_filename, line_index)
		
		-- Check if line is already created
		local fn = F:get_function(function_name) -- line function
		
		-- unlock associated variables
		if fn then 
			
			local not_dummy = variable_types[line_index]
			if not_dummy then -- proper line
				-- Unlock the parameter
				unlock_parameters(variable_types[line_index])
			
			-- is dummy but might be only because of last pixel range, try to fit again
			else
				-- TODO: revive dummy if dummy is created with different conditions (not below noise level)
				-- Only check dummies on the right side of the active range
			end
		
		-- Create new function
		else
			
			-- Get parameters for the function guessing
			local guess_parameters, max_height_value = guess_parameter_constructor(lines_info_filename, line_index, minimal_data_value)
			
			max_height_values[line_index] = max_height_value
			
			if guess_parameters then
				-- Possible error catching (if peak is outside of the range)
				local status, err = pcall(function() F:execute(tostring(guess_parameters)) end)
				
				-- Initialize variable types for that line
				if status then
					fn = F:get_function(function_name) -- get the newly created function
					variable_types[line_index] = get_variables_types(fn, line_index) 
				
				-- Catch error
				else
					printe("activate_local_lines() | Error in line creation: " .. err)
					create_dummy_function(lines_info_filename, line_index)
				end
			else
				--printe("activate_local_lines() | guess_parameters is nil")
				create_dummy_function(lines_info_filename, line_index)
			end
		end
	end
end

-- Get types for each variable of a function
function get_variables_types(fn, line_index)
	db("get_variables_types", 4)
	
	local var_types = {}
	
	-- iterate over parameters
	local param_nr = 0
	local param_name = fn:get_param(param_nr)
	while param_name ~= "" do
		
		var_types[param_nr] = get_variable_type(fn, param_name, line_index)
		
		param_nr = param_nr + 1
		param_name = fn:get_param(param_nr)
	end
	
	return var_types
end

-- Get the type of the variable
function get_variable_type(fn, param_name, line_index)
	db("get_variable_type", 5)
	
	local var_type = {}
	local variable_name = fn:var_name(param_name)
	
	-- One shared parameter for those values
	if (param_name == "hwhm") or (param_name == "gwidth") or (param_name == "fwhm") then
		param_name = "width"
	end
	
	-- Get if variable is simple, locked or compound
	local variable = F:get_variable(variable_name)
	if variable:is_simple() then -- simple variable
		var_type.v_type = "simple"
		var_type.name = variable_name
		
	elseif variable:gpos() == -1 then -- compound variable
		-- TODO: find out the final simple variable through "info variable_name" and match string recursively
		
		-- Get angle variable name, assumes this pattern (!!)
		local name = param_name.. "_variable_"..line_index
		if param_name == "a" then
			name = "constant_variable"
		end
		var_type.name = name
		
		local variable2 = F:get_variable(name)
		if variable2:is_simple() then -- simple variable
			var_type.v_type = "simple"
		elseif variable2:gpos() == -1 then -- compound variable
			var_type.v_type = "compound"
		else -- locked variable
			var_type.v_type = "locked"
		end
	
	else -- locked variable
		var_type.v_type = "locked"
		var_type.name = variable_name
	end
	
	return var_type
end

--[[
-- Helper function to run some other function for every parameter in a function
function iterate_parameters(fn, lua_function)
	local output_table = {}
	
	-- iterate over parameters
	local param_nr = 0
	local param_name = fn:get_param(param_nr)
	while param_name ~= "" do
		-- Run the passed function
		table.insert(output_table, lua_function(fn, param_nr, param_name))
		
		param_nr = param_nr + 1
		param_name = fn:get_param(param_nr)
	end
	
	return output_table
end
--]]

-- Lock the lines for fitting other regions
function lock_lines(main_line_index, line_indices, lines_info_filename, variable_types, angle_errors)
	db("lock_lines", 2)
	
	-- Iterate over the lines
	for i, line_index in ipairs(line_indices) do
		
		if variable_types[line_index] then -- isn't dummy function
			angle_errors[line_index] = {}
			
			-- Check if line is already created
			local function_name = get_fn_name(lines_info_filename, line_index)
			local fn = F:get_function(function_name) -- line function
			
			-- Iterate over parameters
			for i=0, tableLength(variable_types[line_index]) - 1 do
				local var_name = variable_types[line_index][i].name
				local var_type = variable_types[line_index][i].v_type
				
				-- Save the error for the main line
				if main_line_index == line_index then
					local param_name = fn:get_param(i)
					local error_value = 0 -- for locked and double-compound variable
					if var_type == "simple" then
						--[[
						-- One shared parameter for those values
						if (param_name == "hwhm") or (param_name == "gwidth") or (param_name == "fwhm") then
							param_name = "width"
						end
						--]]
						--error_value = F:calculate_expr("$" ..param_name.. "_variable_"..line_index..".error")
						error_value = F:calculate_expr("$" ..var_name..".error")
					end
					angle_errors[line_index][param_name] = error_value
				end
				
				-- Lock the variable
				if (var_type == "simple") then
					F:execute("$" ..var_name.. " = {$" ..var_name.. "}")
				elseif (var_type == "compound") then
					printe("lock_lines() | Locking compound variable: " .. var_name)
					F:execute("$" ..var_name.. " = {$" ..var_name.. "}")
				end
			end
		end
	end
end



-- Select/unselect active points on spectrum
function select_active_points(beginning, ending)
	db("select_active_points", 4)
	
	-- Select first dataset
	F:execute("use @0")
	
	-- Clip the points between observable spectrum
	beginning = clip(beginning, startpoint, endpoint)
	ending = clip(ending, startpoint, endpoint)
	
	F:execute("@0: A = 0 or (x > "..tostring(beginning).." and x < "..tostring(ending)..")")
end

-- Get a table of line indices which are inside (or on the edge) of the determined range
function get_lines_in_range(lines_table, beginning, ending)
	db("get_lines_in_range",4)
	
	local line_indices = {}
	for line_index, info in ipairs(lines_table) do
		local position = info["Wavelength (m)"]
		if (position >= beginning) and (position <= ending) then
			table.insert(line_indices, line_index)
		end
	end
	return line_indices
end

-- Constructs string for parameters to be used with "guess Voigt"
function guess_parameter_constructor(lines_info_filename, line_index, minimal_data_value)
	db("guess_parameter_constructor", 4)
	
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	
	-- line is outside range and won't be fitted
	if forbid_lines_outside_range and ((line_position < startpoint) or (line_position > endpoint)) then 
		return -- instead create a dummy function
	end
	
	
	local function_type = lines_info[lines_info_filename][line_index]["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"]
	local max_position_shift = lines_info[lines_info_filename][line_index]["Max position shift (m)"]
	local max_FWHM = lines_info[lines_info_filename][line_index]["Max line fwhm (m)"]
	
	-- Get function name
	local function_name = get_fn_name(lines_info_filename, line_index)
	
	-- Only time when function name can be edited
	local parameters = "guess %" .. function_name .. " = " .. function_type .. " ("
	--local parameters = "guess " .. function_type .. " (height = "
	
	
	-- Center and height
	local height = 0
	
	-- Center is locked variable
	if max_position_shift == 0 then
		parameters = parameters.."center = "..tostring(line_position)
		
		-- average height of 3 pixels around the location
		for i = -1, 1 do
			height = height + F:calculate_expr("y[index("..tostring(line_position)..") + "..tostring(i).."]") -- index gets the y-value index from wavelength
		end
		height = height / 3 - minimal_data_value -- get the averaged height - minimal_data_value at line location and set that as the guess value
	
	else
		-- Center is simple variable
		if max_position_shift < 0 then
			parameters = parameters.."center = ~"..tostring(line_position)
		
		-- Angle variable
		else
			
			F:execute("$center_variable_"..tostring(line_index).." = ~0")
			-- Center is inside given max shift e.g it's a compound variable
			-- equation: center = line_position + max_position_shift * sin(~angle)
			parameters = parameters.."center = "..tostring(line_position).." + "..tostring(max_position_shift).." * sin($center_variable_"..tostring(line_index)..")"
		end
		
		-- height as max in line_position +/- max_position_shift
		local min_ind = F:calculate_expr("index("..tostring(line_position - max_position_shift).. ")")
		local max_ind = F:calculate_expr("index("..tostring(line_position + max_position_shift).. ")")
		
		local min_px = 3
		-- If line position shift range is below 3 px then get the average height of 3 px
		if (max_ind - min_ind) < min_px then
			for i = -math.floor(min_px / 2), math.floor(min_px / 2) do
				height = height + F:calculate_expr("y[index("..tostring(line_position)..") + "..tostring(i).."]") -- index gets the y-value index from wavelength, can be float: Fityk interpolates
			end
			height = height / min_px -- get the averaged height
		
		-- Get max y in the range
		else
			height = F:calculate_expr("max(y if (x > x["..tostring(min_ind).."] and x < x["..tostring(max_ind).."]))")
		end
		
		height = height - minimal_data_value -- get the max height - minimal_data_value around line location and set that as the guess value
	end
	
	-- Get noise level. Since local constant hasn't been fitted yet then only global noise level can be used
	--local noise = F:calculate_expr("centile("..tostring(height_percentile_of_existing_lines)..", y if a)") - minimal_data_value -- some percentile of all active data - min value of active data
	local noise_level = noise_stdev
	
	--if height <= noise then -- line doesn't exist 
	if height <= (noise_stdev * 0.5) then -- line doesn't exist, might be wide, so lower than noise_stdev is ok
		return -- instead create a dummy function
	end
	
	local max_height_value = 1.2 * height -- 1.33x the pixel height as max bound
	--local max_height_value = 2 * F:calculate_expr("max(y if (x > "..tostring(startpoint).." and x < "..tostring(endpoint).."))") -- Maximum data value and set 2x that as the max bound

	-- Forces height to be positive and lower that 1.2 * pixel height. Guess is made at the wavelength's height or at max height in wavelength shift range
	local start_angle = math.asin((height - max_height_value / 2) / (max_height_value / 2)) -- angle at which height is at pixel height
	F:execute("$height_variable_"..tostring(line_index).." = ~"..tostring(start_angle))
	-- equation: height = max/2 + max/2 * sin(~angle), bounds from 0 to max data value*1.33
	parameters = parameters..", height = "..tostring(max_height_value / 2).." + "..tostring(max_height_value / 2).." * sin($height_variable_"..tostring(line_index)..")"
	
	
	
	-- max 1.4% relative error with shape up to 18.5
	-- gwidth = fwhm*(-3.66354460031617E-10 * shape^9 + 3.69496435533307E-08 * shape^8 - 1.59975065392683E-06 * shape^7 + 0.0000389329719949874 * shape^6 - 0.000586382340638549 * shape^5 + 0.00568217176507484 * shape^4 - 0.0358091432488762 * shape^3 + 0.145909575579559 * shape^2 - 0.377843804199813 * shape + 0.599045873823219)
	
	-- 0.7% relative error with shape up to 10
	-- gwidth = fwhm*(6.78763891716388E-06*shape^6 + 0.000250439220766874*shape^5 + 0.00376557995738546*shape^4 + 0.0299113849608546*shape^3 + 0.13686839890362*shape^2 + 0.372187414970291*shape + 0.598230629334298)
	
	-- hwhm, gwidth or FWHM angle variable (depending on fn type), starts from 3pi/2 so that sin is minimal
	F:execute("$width_variable_"..tostring(line_index).." = ~4.712")
	
	-- shape and gwidth or hwhm or fwhm or just shape depending on Voigt type
	if (function_type == "Voigt") or (function_type == "VoigtFWHM") or (function_type == "VoigtApparatus") then -- Voigt or Voigt defined by fwhm or Voigt defined by apparatus fn
		-- shape 
		-- Angle variable (shape starts at 1)
		F:execute("$shape_variable_"..tostring(line_index).." = ~-0.9273")
		
		-- Limit shape for VoigtApparatus (more freedom than other Voigts)
		if (function_type == "VoigtApparatus") then
			local gwidth = apparatus_fn_fwhm / 2 / math.sqrt(math.log(2)) -- from Fityk manual at Voigt function
			local max_VoigtApp_shape = get_shape(max_FWHM, gwidth)
			
			-- equation: shape = max_VoigtApp_shape / 2 + max_VoigtApp_shape / 2 * sin(~angle) (binds it from 0 to 10) (1 is equal parts of Gaussian and Lorentzian and 0 should be pure Gaussian but isn't quite)
			parameters = parameters..", shape = "..tostring(max_VoigtApp_shape / 2).." + "..tostring(max_VoigtApp_shape / 2).." * sin($shape_variable_"..tostring(line_index)..")"
		
		-- Limit shape more for other Voigts
		else 
			-- equation: shape = max_Voigt_shape / 2 + max_Voigt_shape / 2 * sin(~angle) (binds it from 0 to 10) (1 is equal parts of Gaussian and Lorentzian and 0 should be pure Gaussian but isn't quite)
			parameters = parameters..", shape = "..tostring(max_Voigt_shape / 2).." + "..tostring(max_Voigt_shape / 2 + infinitesimal).." * sin($shape_variable_"..tostring(line_index)..")" -- shape mustn't be 0 for VoigtFWHM
		end
		
		-- gwidth
		if (function_type == "Voigt") then -- ordinary Voigt
			local min_gwidth = get_gwidth(min_FWHM, max_Voigt_shape) -- large shape means small gwidth at same FWHM
			local max_gwidth = get_gwidth(max_FWHM, min_Voigt_shape)
			
			if max_FWHM == 0 then -- gwidth is locked variable
				parameters = parameters..", gwidth = "..tostring(min_gwidth)
			
			elseif max_FWHM >= min_FWHM then -- gwidth is bound with an angle variable
				-- equation: gwidth = (max + min) / 2 + (max - min) / 2 * sin(angle)
				parameters = parameters..", gwidth = "..tostring((max_gwidth + min_gwidth) / 2).." + "..tostring((max_gwidth - min_gwidth) / 2)..
									" * sin($width_variable_"..tostring(line_index)..")"
			
			else -- gwidth is simple variable
				parameters = parameters..", gwidth = ~"..tostring(min_gwidth)
			end
		
		-- fwhm
		elseif (function_type == "VoigtFWHM") then -- VoigtFWHM
			if max_FWHM == 0 then -- fwhm is locked variable
				parameters = parameters..", fwhm = "..tostring(min_FWHM)
			
			elseif max_FWHM >= min_FWHM then -- fwhm is bound with an angle variable
				-- equation: fwhm = (max + min) / 2 + (max - min) / 2 * sin(angle)
				parameters = parameters..", fwhm = "..tostring((max_FWHM + min_FWHM) / 2).." + "..tostring((max_FWHM - min_FWHM) / 2)..
									" * sin($width_variable_"..tostring(line_index)..")"
			
			else -- fwhm is simple variable
				parameters = parameters..", fwhm = ~"..tostring(min_FWHM)
			end
		end
	
	else -- Gaussian or Lorentzian
		local max_hwhm = max_FWHM / 2 -- 2 * HWHM = FWHM
		local min_hwhm = min_FWHM / 2 -- 2 * HWHM = FWHM
		
		if max_hwhm == 0 then -- hwhm is locked variable
			parameters = parameters..", hwhm = "..tostring(min_hwhm)
		elseif max_hwhm >= min_hwhm then -- hwhm is bound with an angle variable
			-- equation: hwhm = (max + min) / 2 + (max - min) / 2 * sin(angle)
			parameters = parameters..", hwhm = "..tostring((max_hwhm + min_hwhm) / 2).." + "..tostring((max_hwhm - min_hwhm) / 2)..
								" * sin($width_variable_"..tostring(line_index)..")"
		else -- hwhm is simple variable
			parameters = parameters..", hwhm = ~"..tostring(min_hwhm)
		end
	end
	
	parameters = parameters..")"
	return parameters, max_height_value
end

-- Convert gwidth and shape to FWHM, equation from Fityk documentation in Voigt function section
function get_FWHM(gwidth, shape)
	return 0.5346 * (2 * math.abs(gwidth) * shape) + math.sqrt(0.2169 * (2 * math.abs(gwidth) * shape)^2 + (2 * math.sqrt(math.log(2)) * math.abs(gwidth))^2)
end

-- Convert FWHM and shape to gwidth, equation from Fityk documentation with WolframAlpha help
-- https://www.wolframalpha.com/input?i=solve+for+g%3A+%280.5346+*+%282+*+%7C%28g%29%7C+*+s%29+%2B+sqrt%280.2169+*+%282+*+%7C%28g%29%7C+*+s%29%5E2+%2B+%282+*+sqrt%28ln%282%29%29+*+%7C%28g%29%7C%29%5E2%29%29+%3D+f%2C+f+%3E+0%2C+g%3E0%2C+s%3E0
function get_gwidth(fwhm, shape)
	if (not fwhm) or (not shape) then return end
	
	local breakpoint = 3.17185 -- point of function discontinuation
	if shape == breakpoint then
		return 0.147434 * fwhm
	else
		local a = 1.72243e6 * shape^2 - 1.73287e7
		local b = 2169 * shape^2 + 6931.47
		local c = 2673 * shape
		
		if shape < breakpoint then
			return 2500 * (50 * math.abs(fwhm) * math.sqrt(b) / math.abs(a) + (c * fwhm) / a)
		else
			return 2500 * (-50 * math.abs(fwhm) * math.sqrt(b) / math.abs(a) + (c * fwhm) / a)
		end
	end
end

-- Convert FWHM and gwidth to shape, equation from Fityk documentation with WolframAlpha help
-- https://www.wolframalpha.com/input?i=solve+for+s%3A+%280.5346+*+%282+*+%7C%28g%29%7C+*+s%29+%2B+sqrt%280.2169+*+%282+*+%7C%28g%29%7C+*+s%29%5E2+%2B+%282+*+sqrt%28ln%282%29%29+*+%7C%28g%29%7C%29%5E2%29%29+%3D+f%2C+f+%3E+0%2C+g%3E0%2C+s%3E0
function get_shape(fwhm, gwidth)
	return (2227500 * fwhm - 5000 * gwidth * math.sqrt((150625 * fwhm^2) / gwidth^2 + 191381 * math.log(2))) / (574143 * gwidth)
end

-- Create a function with locked variables to keep the indexing
function create_dummy_function(lines_info_filename, line_index)
	db("create_dummy_function")
	db(line_position)
	
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	local function_type = lines_info[lines_info_filename][line_index]["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"]
	
	-- Get function name
	local function_name = get_fn_name(lines_info_filename, line_index)
	
	--local sig_numbers = 6
	--local pos_name = decimalToInteger(line_position, sig_numbers) -- Fityk doesn't allow anything else besides digits, letters and _. Outputs function name in pm.
	
	-- gwidth, shape and fwhm might cause trouble if they're 0
	if function_type == "Voigt" then -- Voigt
		F:execute("guess %" .. function_name .. " = Voigt(center = "..tostring(line_position)..", height = 0, gwidth = 1, shape = 1)")
	elseif function_type == "VoigtFWHM" then -- FWHM defined Voigt
		F:execute("guess %" .. function_name .. " = VoigtFWHM(center = "..tostring(line_position)..", height = 0, fwhm = 1, shape = 1)")
	elseif function_type == "VoigtApparatus" then -- Apparatus fn defined Voigt
		F:execute("guess %" .. function_name .. " = VoigtApparatus(center = "..tostring(line_position)..", height = 0, shape = 1)")
	else -- Gaussian and Lorentzian have same variables
		F:execute("guess %" .. function_name .. " = Gaussian(center = "..tostring(line_position)..", height = 0, hwhm = 1)")
	end
end

--[[
-- If the line is too small then it is written as 0-height.
function remove_invalid_line(line_index, variable_types, noise_stdev)
	db("remove_invalid_line", 3)
	
	local breadth_multiplier = math.pi -- don't remember where it came
	--local rectangle_width = gwidth / 1.2 * breadth_multiplier -- to hwhm and then get the rectangle width
	local rectangle_width = min_FWHM / 2 * breadth_multiplier
	local detection_sn_ratio = 2 -- required signal to noise ratio
	local min_area = detection_sn_ratio * noise_stdev * rectangle_width -- get the rectangle area -- F:calculate_expr("x[1]-x[0]") --/ noise_stdev_calibration * detection_threshold_calibration -- minimum area of a detectable line
	
	local functions = F:get_components(0)
	local fn = functions[line_index]
	
	if not ((fn.name == "bg") or (fn.name == "bg_local")) then -- not the constant
		local area = fn:get_param_value("Area")
		
		if area <= min_area then -- line doesn't exist 
			--F:execute("%"..tostring(functions[line_index].name)..".height = 0")
			
			-- Lock the parameters
			F:execute("$height_variable_"..tostring(line_index).." = 0") -- write height as 0
			
			variable_types[line_index] = nil
			
			lock_parameters(fn, line_index)
		end
	end
end

-- If a line is too small then it is written as 0-height.
function remove_invalid_lines(lines_info_filename, minimal_data_value)
	db("remove_invalid_lines", 3)
	
	local functions = F:get_components(0)
	--local noise = math.abs(F:calculate_expr("centile("..tostring(height_percentile_of_existing_lines)..", y if a)") - minimal_data_value) -- some percentile of all active data - min value of active data
	
	local breadth_multiplier = math.pi -- don't remember where it came
	--local rectangle_width = gwidth / 1.2 * breadth_multiplier -- to hwhm and then get the rectangle width
	local rectangle_width = min_FWHM / 2 * breadth_multiplier
	local detection_sn_ratio = 2 -- required signal to noise ratio
	local min_area = detection_sn_ratio * noise_stdev * rectangle_width -- get the rectangle area -- F:calculate_expr("x[1]-x[0]") --/ noise_stdev_calibration * detection_threshold_calibration -- minimum area of a detectable line
	
	
	-- iterates over lines
	--for line_index,_ in ipairs(lines_info[lines_info_filename]) do
	for line_index = 1, #functions-1 do
		local fn = functions[line_index]
		if not (fn.name == "bg") then -- not the constant
			local area = fn:get_param_value("Area")
			
			if area <= min_area then -- line doesn't exist 
				--F:execute("%"..tostring(functions[line_index].name)..".height = 0")
				
				-- Lock the parameters
				F:execute("$height_variable_"..tostring(line_index).." = 0") -- write height as 0
				lock_parameters(fn, line_index)
			end
		end
	end
end
--]]

-- Write weak lines as 0-height. This function is meant to be run after finishing with line fitting
function nullify_lines()
	db("nullify_lines", 2)
	
	-- Iterate over lines
	local functions = F:all_functions()
	for idx = 0, #functions - 1 do
		local fn = functions[idx]
		
		-- Check if the function has height and center parameter 
		local height, center
		local status, err = pcall(function() 
			height = fn:get_param_value("height")
			center = fn:get_param_value("center") 
		end)
		
		if height and center then
			local noise_level = get_noise_estimate(center)
			
			-- Line is too weak and is influenced by noise too much
			if height < (noise_level * noise_level_check_multiplier) then
			
				-- Write line height as 0 and lock all variables
				local height_var = "$" .. fn:var_name("height")
				F:execute(height_var .. " = 0")
				lock_parameters(fn)
			end
		end
	end
end

-- Estimate the local noise level as the average of global noise and polyline local height
function get_noise_estimate(location)
	local noise_level_constant = get_constant_noise_estimate(location)
	
	local noise_level = (noise_level_constant + noise_stdev) / 2
	return noise_level
end

-- Get noise estimate as the local polyline (local continuum is actually global constant + local constant)
function get_constant_noise_estimate(location)
	db("get_constant_noise_estimate", 2)
	local bg_local_fn = F:get_function("bg_local")
	local local_constant = bg_local_fn:value_at(location)
	
	return local_constant
end

-- unlock the parameters of the function
function unlock_parameters(fn_var_types)
	db("unlock_parameters", 3)
	
	-- Iterate over final variables and unlock them, respecting the type of variable they were created as
	for i=0, tableLength(fn_var_types) - 1 do
		local variable_name = fn_var_types[i].name
		local variable_type = fn_var_types[i].v_type
		
		local type_symbol = "" -- locked variable
		if variable_type == "compound" then
			printe("unlock_parameters() | function has double-compound variable: " .. variable_name)
		elseif variable_type == "simple" then
			type_symbol = "~"
		end
		
		-- Unlock the parameter with its value
		F:execute("$" ..variable_name.. " = " ..type_symbol.. "{$" ..variable_name.. "}")
	end
end

-- Lock the parameters of the function
function lock_parameters(fn, line_index)
	db("lock_parameters",3)
	
	-- iterate over parameters
	local param_nr = 0
	local param_name = fn:get_param(param_nr)
	while param_name ~= "" do
		
		-- Line defined, get angle variables and lock these instead of direct variables
		if line_index then
			-- One shared parameter for those values
			if (param_name == "hwhm") or (param_name == "gwidth") or (param_name == "fwhm") then
				param_name = "width"
			end
			
			-- Get angle variable name
			local variable_name = param_name.. "_variable_" ..line_index
			if param_name == "a" then
				variable_name = "constant_variable"
			end
			
			-- Lock the parameter with its value
			F:execute("$" ..variable_name.. " = {$" ..variable_name.. "}")
		else -- brute-lock
			-- Lock the parameter with its value by creating a new variable
			local direct_variable = "$" .. fn:var_name(param_name)
			F:execute(direct_variable .. " = {" ..direct_variable.. "}")
		end
		
		param_nr = param_nr + 1
		param_name = fn:get_param(param_nr)
	end
end



----------------------------------------------------------------------
-- Output phase
----------------------------------------------------------------------

-- Saves line parameters' errors. It gets errors from $_variable.parameter.error.
-- I've concluded that this value is the standard error for that parameter.
function get_errors(data_filename, minimal_data_value, max_constant_value, max_height_values, angle_errors)
	db("get_errors", 1)
	
	-- y = a + b * sin(angle) => y_error = d_y / d_angle * angle_error
	-- y_error = b * cos(angle) * angle_error
	
	--TODO: check what happens (crash or line skipping) when fitting 2 lines at same location (same line ID) -- probably done
	
	-- Finds dataset functions
	local functions = F:get_components(0)
	
	local errors = {}
	errors.height_errors,errors.center_errors,errors.hwhm_errors,errors.gwidth_errors,errors.shape_errors = {},{},{},{},{}
	errors.local_constant = {}
	
	-- Constant
	local constant_value = F:calculate_expr("%bg.a")
	if (constant_value == minimal_data_value) or (constant_value == max_constant_value) then -- stopped by the bounds
		errors.constant_error = 0
	else -- ordinary fit
		local angle_error = angle_errors[0] or 0
		errors.constant_error = math.abs((max_constant_value - minimal_data_value) / 2 * math.cos(constant_value) * angle_error)
	end
	
	-- No functions or only constant
	if #functions <= 1 then
		return errors
	end
	
	-- Iterates over lines
	local lines_info_filename = spectra_info[data_filename]["Lines filename"]
	for line_index,_ in ipairs(lines_info[lines_info_filename]) do -- starts at 1. Constant has index 0
		
		local function_name = functions[line_index].name
		
		-- Skip constant
		if function_name == "%bg" then
			goto continue_get_errors
		end
		
		local height = functions[line_index]:get_param_value("height")
		
		if (height == 0) then -- non-existent line
			errors.height_errors[line_index] = nil
			errors.center_errors[line_index] = nil
			errors.hwhm_errors[line_index] = nil
			errors.gwidth_errors[line_index] = nil
			errors.shape_errors[line_index] = nil
			errors.local_constant[line_index] = nil
			goto continue_get_errors -- skip to the next iteration
		end
		
		-- Pass local constant values on
		errors.bg_local = angle_errors.bg_local
		
		-- Height
		local max_h = max_height_values[line_index] or 0
		if (height >= max_h) then -- min function selected max_height_value or the line is non-existent
			errors.height_errors[line_index] = 0
		else -- angle fit
			local angle_error = angle_errors[line_index] and angle_errors[line_index]["height"] or 0
			-- y_error = max / 2 * cos(angle) * angle_error
			errors.height_errors[line_index] = math.abs((max_height_values[line_index] / 2) * math.cos(F:calculate_expr("$height_variable_"..line_index)) * angle_error)
		end
		
		
		-- Center
		local center_angle_error = angle_errors[line_index] and angle_errors[line_index]["center"] or 0
		local max_position_shift = lines_info[lines_info_filename][line_index]["Max position shift (m)"]
		if max_position_shift == 0 then -- Center is locked variable
			errors.center_errors[line_index] = 0
		elseif max_position_shift < 0 then -- Center is simple variable
			
			errors.center_errors[line_index] = center_angle_error
		else -- Angle variable
			errors.center_errors[line_index] = math.abs(max_position_shift * math.cos(F:calculate_expr("$center_variable_"..line_index)) * center_angle_error)
		end
		
		
		local function_type = lines_info[lines_info_filename][line_index]["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"]
		local max_FWHM = lines_info[lines_info_filename][line_index]["Max line fwhm (m)"] or infinity
		if (function_type == "Voigt") or (function_type == "VoigtFWHM") or (function_type == "VoigtApparatus") then -- Voigt or Voigt defined by fwhm or Voigt defined by apparatus fn
			
			errors.hwhm_errors[line_index] = nil
			
			-- TODO: check max_Voigt_shape effect
			
			-- Shape error from angle variable
			-- y_error = 5 * cos(angle) * angle_error
			local shape_angle_error = angle_errors[line_index] and angle_errors[line_index]["shape"] or 0
			
			-- VoigtApparatus
			if (function_type == "VoigtApparatus") then
				local gwidth = apparatus_fn_fwhm / 2 / math.sqrt(math.log(2)) -- from Fityk manual at Voigt function
				local max_VoigtApp_shape = get_shape(max_FWHM, gwidth)
				
				errors.shape_errors[line_index] = math.abs(max_VoigtApp_shape / 2 * math.cos(F:calculate_expr("$shape_variable_"..line_index)) * shape_angle_error)
				errors.gwidth_errors[line_index] = nil
			
			-- Voigt or VoigtFWHM
			else
				errors.shape_errors[line_index] = math.abs(max_Voigt_shape / 2 * math.cos(F:calculate_expr("$shape_variable_"..line_index)) * shape_angle_error)
				
				-- gwidth
				if (function_type == "Voigt") then -- ordinary Voigt
					local gwidth_angle_error = angle_errors[line_index] and angle_errors[line_index]["gwidth"] or 0
					if max_FWHM == 0 then -- gwidth is locked variable
						errors.gwidth_errors[line_index] = 0
					
					elseif max_FWHM >= min_FWHM then -- gwidth is bound with an angle variable
						local min_gwidth = get_gwidth(min_FWHM, max_Voigt_shape) -- large shape means small gwidth at same FWHM
						local max_gwidth = get_gwidth(max_FWHM, min_Voigt_shape)
						
						-- equation: gwidth = (max + min) / 2 + (max - min) / 2 * sin(angle)
						-- y_error = (max - min) / 2 * cos(angle) * angle_error
						errors.gwidth_errors[line_index] = math.abs((max_gwidth - min_gwidth) / 2 * math.cos(F:calculate_expr("$width_variable_"..line_index)) * gwidth_angle_error)
					
					else -- gwidth is simple variable
						errors.gwidth_errors[line_index] = gwidth_angle_error
					end
				
				-- fwhm
				else -- VoigtFWHM
					
					-- TODO: convert angle_errors[line_index]["gwidth"] to fwhm
					
					local fwhm_angle_error = angle_errors[line_index] and angle_errors[line_index]["gwidth"] or 0
					if max_FWHM == 0 then -- gwidth is locked variable
						errors.gwidth_errors[line_index] = 0
					
					elseif max_FWHM >= min_FWHM then -- gwidth is bound with an angle variable					
						-- equation: gwidth = (max + min) / 2 + (max - min) / 2 * sin(angle)
						-- y_error = (max - min) / 2 * cos(angle) * angle_error
						errors.gwidth_errors[line_index] = math.abs((max_FWHM - min_FWHM) / 2 * math.cos(F:calculate_expr("$width_variable_"..line_index)) * fwhm_angle_error)
					
					else -- gwidth is simple variable
						errors.gwidth_errors[line_index] = fwhm_angle_error
					end
				end
			end
			
		-- Gaussian or Lorentzian
		else 
			errors.gwidth_errors[line_index] = nil
			errors.shape_errors[line_index] = nil
			
			local max_hwhm = max_FWHM / 2 -- 2 * HWHM = FWHM
			local min_hwhm = min_FWHM / 2 -- 2 * HWHM = FWHM
			
			local hwhm_angle_error = angle_errors[line_index] and angle_errors[line_index]["hwhm"] or 0
			if max_hwhm == 0 then -- hwhm is locked variable
				errors.hwhm_errors[line_index] = 0
			elseif max_hwhm >= min_hwhm then -- hwhm is bound with an angle variable
				-- equation: hwhm = (max + min) / 2 + (max - min) / 2 * sin(angle)
				-- y_error = (max - min) / 2 * cos(angle) * angle_error
				errors.hwhm_errors[line_index] = math.abs((max_hwhm - min_hwhm) / 2 * math.cos(F:calculate_expr("$width_variable_"..line_index)) * hwhm_angle_error)
			else -- hwhm is simple variable
				errors.hwhm_errors[line_index] = hwhm_angle_error
			end
		end
		
		::continue_get_errors::
	end
	
	return errors
end


-- Writes parameters of the functions into output file.
-- I've concluded that error values are standard errors.
function write_output(data_filename, spectrum_index, errors)
	db("write_output", 1)
	
	local file = io.open(output_path..output_data_name_nr,"a")
	io.output(file)
	
	local chi2 = F:get_wssr(0) -- Weighted sum of squared residuals, a.k.a. chi^2
	local dof 
	pcall(function() dof = F:get_dof(0) end) -- Degrees of freedom, requires at least one simple variable (not locked)
	local functions = F:get_components(0)

	-- Writes dataset info
	io.write(data_filename)
	io.write(separator..spectrum_index)
	io.write(separator..chi2)
	io.write(separator..tostring(dof))
	io.write(separator..F:get_function("%bg"):get_param_value("a"))
	io.write(separator..noise_stdev)
	io.write(separator..errors.constant_error)
	
	
	
	F:execute("@+ <") -- Creates second dataset for FWHA calculations
	local FWHA_spectrum_index = F:get_dataset_count() - 1
	F:execute("use @"..tostring(FWHA_spectrum_index)) -- use new dataset
	F:execute("%FWHA = Constant(a = 0)") -- Create a dummy function
	F:execute("F+= %FWHA") -- add the function to dataset functions
	
	local lines_info_filename = spectra_info[data_filename]["Lines filename"]
	
	-- Copies wavelengths into an array
	local wavelength_array = {}
	for j, _ in ipairs(lines_info[lines_info_filename]) do -- iterate over lines
		table.insert(wavelength_array, functions[j]:get_param_value("center"))
	end	
	
	local maximum = 0 -- variable to check smallest wavelength index
	for i, _ in ipairs(lines_info[lines_info_filename]) do -- iterate over lines, starts at 1. Constant has index 0
		
		-- Finds the index of the next smallest wavelength
		local line_index = 1
		local mininum = infinity
		for i = 1, tableLength(wavelength_array) do
			if (wavelength_array[i] < mininum) and (wavelength_array[i] > maximum) then
				mininum = wavelength_array[i]
				line_index = i
			end
		end
		maximum = wavelength_array[line_index] -- doesn't look for values smaller than this
		
		
		-- Get variables
		local height = functions[line_index]:get_param_value("height")
		local center = functions[line_index]:get_param_value("center")
		local area = functions[line_index]:get_param_value("Area")
		local fwhm = functions[line_index]:get_param_value("FWHM")
		
		
		-- Get variables according to the fitted line type
		local hwhm,gwidth,shape,GFWHM,LFWHM
		local function_type = lines_info[lines_info_filename][line_index]["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"]
		if function_type == "Voigt" then -- Voigt
			gwidth = math.abs(functions[line_index]:get_param_value("gwidth"))
			shape = math.abs(functions[line_index]:get_param_value("shape"))
			GFWHM = functions[line_index]:get_param_value("GaussianFWHM")
			LFWHM = functions[line_index]:get_param_value("LorentzianFWHM")
		elseif function_type == "VoigtFWHM" then -- VoigtFWHM
			gwidth = math.abs(functions[line_index]:get_param_value("fwhm")) -- TODO: separate this into fwhm output field
			shape = math.abs(functions[line_index]:get_param_value("shape"))
		elseif function_type == "VoigtApparatus" then -- VoigtApparatus
			shape = math.abs(functions[line_index]:get_param_value("shape"))
		else -- Gaussian or Lorentzian
			hwhm = math.abs(functions[line_index]:get_param_value("hwhm"))
		end
		
		local FWHA = get_FWHA(FWHA_spectrum_index, function_type, height, center, hwhm, gwidth, shape, fwhm) -- Full width at half area
		
		-- If there's no peak (peak height is 0) or width is 0 then all parameters are written ""
		if (not height) or (height <= 0) or (gwidth and (gwidth == 0)) or (hwhm and (hwhm == 0)) then
			io.write(string.rep(separator, 17)) -- 13 values for Voigt, Gaussian/Lorentzian have 9 values from which 7 overlap the previous ones, +2 for local constant
		else -- Else reads errors and writes peak info into output
			-- values
			io.write(separator..tostring(height))
			io.write(separator..tostring(center))
			io.write(separator..(tostring(hwhm) or ""))
			io.write(separator..(tostring(gwidth) or ""))
			io.write(separator..(tostring(shape) or ""))
			io.write(separator..tostring(area))
			io.write(separator..tostring(fwhm))
			io.write(separator..tostring(FWHA))
			io.write(separator..(tostring(GFWHM) or ""))
			io.write(separator..(tostring(LFWHM) or ""))
			
			-- standard errors
			io.write(separator..tostring(errors.height_errors[line_index]))
			io.write(separator..tostring(errors.center_errors[line_index]))
			io.write(separator..tostring(errors.hwhm_errors[line_index] or ""))
			io.write(separator..tostring(errors.gwidth_errors[line_index] or ""))
			io.write(separator..tostring(errors.shape_errors[line_index] or ""))
			
			-- Local constant
			io.write(separator..(tostring(errors.bg_local.value[line_index]) or ""))
			io.write(separator..(tostring(errors.bg_local.error[line_index]) or ""))
		end
	end
	
	F:execute("use @0") -- reset active dataset to default
	delete_dataset(FWHA_spectrum_index) -- Deletes the dataset created for FWHA calculation
	
	io.write("\n")
	io.close(file)
end

-- Checks if the output file exists and if it does increment its number, also create sessions folder
function check_output_paths()
	db("check_output_paths", 4)
	
	-- Create Input_data_corrected folder if it doesn't exist
	if not path_exists(corrected_path) then
		os.execute("mkdir \"" ..corrected_path.. "\"")
	end
	
	-- Create output folder if it doesn't exist
	if not path_exists(output_path) then
		os.execute("mkdir \"" ..output_path.. "\"")
	end
	
	
	local i = 1
	local f = io.open(output_path..output_data_name.. "_" .. tostring(i) ..output_data_end, "r")
	
	-- find first index which file doesn't exist
	while (f ~= nil) and io.close(f) do
		i = i + 1 -- increment index
		f = io.open(output_path..output_data_name.. "_" .. tostring(i) ..output_data_end, "r") -- check new file
	end

	output_data_name_nr = output_data_name .. "_" .. tostring(i) ..output_data_end
	
	-- Create sessions folder if it doesn't exist
	if not path_exists(output_path.. "Sessions") then
		os.execute("mkdir \"" ..output_path.. "Sessions\"")
	end
end

-- Initializes output file, change path if needed
function init_output(data_filename)
	db("init_output", 2)
	
	-- Find lines info file with most lines
	local table_size, lines_info_filename
	if not data_filename then
		
		-- Collect lines_files to be used
		local lines_files = {}
		for data_filename, info in pairs(spectra_info) do
			table.insert(lines_files,info["Lines filename"])
		end
		
		-- Check if any lines file are defined
		if tableLength(lines_files) > 0 then
			
			-- Iterate over defined files
			for i, filename in ipairs(lines_files) do
				
				-- Get nr of lines defined in the file
				local size = tableLength(lines_info[filename])
				table_size = table_size or size -- initialize value
				lines_info_filename = lines_info_filename or filename -- initialize value
				
				if size > table_size then -- overwrite variable values
					table_size = size
					lines_info_filename = filename
					
					printe("init_output() | lines info is different size in different specified input files, taking longest list. You might want to input only spectra with same lines.") -- print error log
				end
			end
			
		-- no lines file specified, find longest list from all files in input info folder
		else 
			for filename, info in pairs(lines_info) do
				
				-- Get nr of lines defined in the file
				local size = tableLength(info)
				table_size = table_size or size -- initialize value
				lines_info_filename = lines_info_filename or filename -- initialize value
				
				if size > table_size then -- overwrite variable values
					table_size = size
					lines_info_filename = filename
					
					printe("init_output() | lines info is different size in different input files in input info folder, taking longest list. You might want to input only spectra with same lines.") -- print error log
				end
			end
		end
	else
		lines_info_filename = spectra_info[data_filename] and spectra_info[data_filename]["Lines filename"]
		table_size = lines_info_filename and lines_info[lines_info_filename] and tableLength(lines_info[lines_info_filename]) or nil
	end
	
	
	local file = io.open(output_path..output_data_name_nr,"w")
	io.output(file)
	
	-- First header, write line names
	io.write("All lines")
	io.write(string.rep(separator.. "All lines", 6)) -- 6 values for general info
	
	-- Iterate over lines
	if lines_info_filename and table_size then 
		for i = 1, table_size do -- iterate over lines
			local fn_type = lines_info[lines_info_filename][i]["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"] -- line type
			local fn_name = get_fn_name(lines_info_filename, i) -- line name
			local output_str = separator..tostring(i).." "..fn_name.." "..fn_type
			io.write(string.rep(output_str, 17)) -- 17 values for every line: 13 values for Voigt, Gaussian/Lorentzian have 9 values from which 7 overlap the previous ones, +2 for local constant
		end
	end
	
	io.write("\n")
	
	-- Write second header with data names
	io.write("Filename")
	io.write(separator .. "Experiment nr")
	io.write(separator .. "CHI^2")
	io.write(separator .. "Degrees of freedom")
	io.write(separator .. "Global constant (min intensity)")
	io.write(separator .. "Global noise stdev")
	io.write(separator .. "Global constant error")
	
	-- Write titles to the output
	if lines_info_filename and table_size then 
		for i = 1, table_size do -- iterate over lines
		--for i, info in ipairs(lines_info[filename]) do -- iterate over lines
			
			-- TODO: ouput according to line types
			
			io.write(separator.. "height")
			io.write(separator.. "center")
			io.write(separator.. "hwhm")
			io.write(separator.. "gwidth")
			io.write(separator.. "shape")
			io.write(separator.. "Area")
			io.write(separator.. "FWHM")
			io.write(separator.. "FWHA")
			io.write(separator.. "GaussianFWHM")
			io.write(separator.. "LorentzianFWHM")
			
			-- Standard errors
			io.write(separator.. "height error")
			io.write(separator.. "center error")
			io.write(separator.. "hwhm error")
			io.write(separator.. "gwidth error")
			io.write(separator.. "shape error")
			
			-- Local constant
			io.write(separator.. "local constant")
			io.write(separator.. "local constant error")
		end
	end
	
	io.write("\n")
	io.close(file)
end

-- Calculates full width at half area from the line. Uses a slow method of simply iterating over the pixels.
function get_FWHA(FWHA_spectrum_index, function_type, height, center, hwhm, gwidth, shape, fwhm)
	db("get_FWHA", 3)
	
	if (function_type == "Voigt") then -- Voigt
		--gwidth = gwidth or get_gwidth(fwhm, shape) or infinitesimal
		F:execute("%FWHA = Voigt(center = "..center..", height = "..height..", gwidth = "..gwidth..", shape = "..shape..")")
	
	elseif (function_type == "VoigtFWHM") then -- VoigtFWHM
		F:execute("%FWHA = VoigtFWHM(center = "..center..", height = "..height..", fwhm = "..fwhm..", shape = "..shape..")")
	
	elseif function_type == "VoigtApparatus" then
		F:execute("%FWHA = VoigtApparatus(center = "..center..", height = "..height..", shape = "..shape..")")
	
	elseif function_type == "Gaussian" then -- Gaussian
		F:execute("%FWHA = Gaussian(center = "..center..", height = "..height..", hwhm = "..hwhm..")")
	else -- Lorentzian
		F:execute("%FWHA = Lorentzian(center = "..center..", height = "..height..", hwhm = "..hwhm..")")
	end
	
	
	local range = 10
	local pixels = 1001
	
	-- 1001 px and wavelengths are from -range * fwhm to + range * fwhm, equation: center - range * fwhm + 20 * fwhm / 10001 * index
	F:execute("M = "..tostring(pixels).."; x = "..tostring(center - range * fwhm).." + "..tostring(fwhm).." * "..tostring(2 * range).." / "..tostring(pixels).." * n; y = 0") -- create points
	F:execute("Y = F(x)") -- set y points according to the function
	
	local area = F:calculate_expr("darea(y)")
	local area25 = area * 0.25
	local area75 = area * 0.75
	
	--argmin(darea(y) if (darea(y) < (0.25 * darea(y))) darea(y if(darea(y) < (0.25 * darea(y)) ) )
	
	
	local x1,x2,cum_area = 0,0,0 -- FWHA start, FWHA end and area left of the viewed value
	for i = 0, pixels do -- loop over pixels
		cum_area = F:calculate_expr("darea(y if n <= "..i..")") -- calculate area left of the pixel
		
		if cum_area <= area25 then -- 25 percentile of area
			x1 = F:calculate_expr("x["..i.."]")
		end
		
		if cum_area >= area75 then -- 75 percentile area
			x2 = F:calculate_expr("x["..i.."]")
			break -- stop the loop
		end
	end
	
	return x2 - x1
	--[[
	F:execute("$startpoint={y[0]}") -- save first pixel value
	F:execute("Y = y[n] + Y[n - 1]") -- create cumulative distribution function
	F:execute("Y = y[n] - 2 * $startpoint") -- subtract first pixel value two times since area starts from 0 and Y[-1] == Y[0] added first value twice at index 0.
	--F:execute("Y = y * (x[10001] - x[0])") -- multiply with wavelength range to get cumulative distribution function of area
	
	
	local FWHA = tonumber(F:calculate_expr("argmin(y if y > 0.75 * y[10001]) - argmin(y if y > 0.25 * y[10001])")) or 0 -- assuming the function is symmetrical
	
	F:execute("use @0") -- reset te active dataset
	
	return FWHA
	--]]
end

-- Draws a plot of the dataset @0 and all it's functions the way
-- it's rendered on the GUI
function plot_functions(data_filename, spectrum_index)
	db("plot_functions", 1)
	
	-- Find view limit ranges
	local min_int = F:calculate_expr("min(Y)")
	local max_int = F:calculate_expr("max(Y)")
	local x_min = pad_x_min and (startpoint - (endpoint - startpoint) * pad_x_min)
	local x_max = pad_x_max and (endpoint + (endpoint - startpoint) * pad_x_max)
	local y_min = pad_y_min and (min_int - (max_int - min_int) * pad_y_min)
	local y_max = pad_y_max and (max_int + (max_int - min_int) * pad_y_max)
	
	-- Select the points
	select_active_points(startpoint, endpoint)
	
	-- Constructs plot command with correct ranges
	plot_command = "plot ["
	if x_min then plot_command = plot_command..x_min end
	plot_command = plot_command..":"
	if x_max then plot_command = plot_command..x_max end
	plot_command = plot_command.."] ["
	if y_min then plot_command = plot_command..y_min end
	plot_command = plot_command..":"
	if y_max then plot_command = plot_command..y_max end
	
	-- Draws an image from data and functions and saves it to output folder
	plot_command = plot_command.."] @0 >> \'"..output_path..data_filename..separator..tostring(spectrum_index)..".png\'"
	F:execute(plot_command)
end


-- Generate a polyline to simulate the fitted local constants. 
-- This manipulation is done here instead of adding rectangle functions
-- during data fitting because that could increase fitting time.
function create_polyline_local_constant(polyline_values)
	
	-- Add a polyline (local constants) to raise the line functions back to original height. Alternative
	-- is to use Rectangle functions.
	local polyline_str = "%bg_local = Polyline("
	
	-- Sort polyline values by increasing start wavelengths
	local function compare_start(a,b) return (a["start"] < b["start"]) end
	table.sort(polyline_values, compare_start)
	
	-- Construct polyline string
	--local narrower_step = max_line_influence_diameter / narrower_polyline_step -- many lines region overpopulates the polyline
	for idx, value_tbl in ipairs(polyline_values) do
		
		-- Get the bondaries of previous and next steps
		local end_prev = -infinity
		local start_next = infinity
		if idx > 1 then end_prev = polyline_values[idx - 1].ending end
		if idx < #polyline_values then start_next = polyline_values[idx + 1].start end
		
		-- if two steps overlap then take the center of these as boundary
		local use_start = value_tbl.start
		local use_end = value_tbl.ending
		if use_start < end_prev then use_start = (use_start + end_prev) / 2 end
		if use_end > start_next then use_end = (use_end + start_next) / 2 end
		
		if idx > 1 then polyline_str = polyline_str .. "," end  -- not 1st value 
		polyline_str = polyline_str .. tostring(use_start) .. "," .. tostring(value_tbl.height)
		polyline_str = polyline_str .. "," ..  tostring(use_end) .. "," .. tostring(value_tbl.height)
		
		--polyline_str = polyline_str .. tostring(value_tbl.start + narrower_step) .. "," .. tostring(value_tbl.height)
		--polyline_str = polyline_str .. "," ..  tostring(value_tbl.ending - narrower_step) .. "," .. tostring(value_tbl.height)
	end
	
	-- Finalize polyline string and execute
	polyline_str = polyline_str .. ")"
	F:execute(polyline_str)
	F:execute("F += %bg_local")
end


-------------------------------------------------------------------------------------------------------------
-- Utility functions
-------------------------------------------------------------------------------------------------------------

-- prints if debug mode is active. The lower the priority the sooner it's printed.
function db(something, priority)
	priority = priority or 1 -- defaults to 1
	if (debug_mode >= priority) then
		printTable(something)
	end
end

-- Wraps provided fn in pcall, catches the error and prints it
function wrap(fn)
	local status, err = pcall(fn)
	if not status then print(tostring(err)) end
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

-- Iterate over table keys and if value is in table keys return true
function is_in_table_keys(table, value)
	for key,_ in pairs(table) do
		if (value == key) then return true end
	end
	return false
end
-- Iterate over table values and if value is in table values return true
function is_in_table(table, value)
	for _,val in pairs(table) do
		if (value == val) then return true end
	end
	return false
end

--[[
-- string.gmatch() doesn't work properly with Fityk LUA, returns empty line every 2nd time
-- Split string and return a table
function split(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	for str in string.gmatch(inputstr, "([^" .. sep .. "]*)") do
		table.insert(t, str)
	end
	return t
end
--]]

-- Concatenate two tables
function tableConcat(t1,t2)
    for i=1,tableLength(t2) do
        t1[tableLength(t1) + 1] = t2[i]
    end
    return t1
end

-- Clip variable between two values
function clip(var, low, high)
	if not low then low = -infinity end
	if not high then high = infinity end
	if low and (var < low) then var = low end
	if high and (var > high) then var = high end
	return var
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


-- Prepare ordinary string to be used in regex patterns. Put a % in front of special characters/magic characters like + and -
function get_safe_pattern_string(str)
	str = string.gsub(str, "%%", "%%%%") -- put % in front of %
	
	-- Go over other special characters
	local normal_special_chars = {"(", ")", ".", "+", "-", "*", "?", "[", "^", "$"} -- https://www.lua.org/pil/20.2.html
	for idx, char in ipairs(normal_special_chars) do
		str = string.gsub(str, "%" .. char, "%%" .. char) -- put % in front
	end
	return str
end

-- Search a folder for files that match the provided pattern, if no pattern then return all files
function match_files(path, f_end, sort_fn, patterns_or, patterns_and)
	
	-- Get files with data_filename beginning
	local files = {}
	for filename in io.popen("dir \"" .. path .. "\" /b"):lines() do
		
		local bool = false
		
		-- OR matches
		if patterns_or and (type(patterns_or) == "table") then
			for i,pattern in pairs(patterns_or) do
				if string.match(filename, pattern) then
					bool = true
					break -- lazy OR algorithm
				end
			end
		elseif patterns_or then
			bool = string.match(filename, patterns_or)
		end
		
		-- AND matches
		if patterns_and then
			for i,pattern in pairs(patterns_and) do
				bool = bool and string.match(filename, pattern)
			end
		end
		
		if bool then 
			table.insert(files, filename)
		end
	end
	
	table.sort(files, sort_fn) -- Sort filenames in ascending order for shot to correlate with file number
	
	return files
end

-- Sort gives 0,1,100,1001,1002,2,3,871,99... This sort gives 0,1,2,3,99,100,101,871,1001,1002
-- The function assumes that you get the full filename like "abc_1-201.txt" or "abc_cd,e_f_127_1-201.txt" but ".txt" can be omitted
-- Only sorts according to first number in corrected files
function sort_numerical_corr_filenames_fn(filename1,filename2)
	
	-- Test whether files have end part (e.g. ".txt") and remove it
	local end_pattern = "^.+(%.[%a%d]-)$" -- any characters (1 or more), [extracted] ., [extracted] alphanumeric characters (1 or more)
	local file_ext1 = string.match(filename1, end_pattern)
	local has_file_end1 = (file_ext1 ~= nil)
	if has_file_end1 then filename1 = string.gsub(filename1, file_ext1, "") end -- remove file end
	local file_ext2 = string.match(filename2, end_pattern) -- 2nd file might have different extension, ignore it
	local has_file_end2 = (file_ext2 ~= nil)
	if has_file_end2 then filename2 = string.gsub(filename2, file_ext2, "") end -- remove file end
	
	
	-- Extract digits from the end of the filenames
	local pattern = "^(.-)(%d+)%-%d+$" -- any characters (0 or more), [extracted] digits (1 or more), -, digits (1 or more)
	local f1_root, f1_digits = string.match(filename1, pattern)
	local f2_root, f2_digits = string.match(filename2, pattern)
	
	-- If filename beginning doesn't match then sort filenames by the beginning
	if f1_root ~= f2_root then
		if (not f1_root) or (not f2_root) then  -- some error
			printe("sort_numerical_corr_filenames_fn() | Root doesn't exist: " .. tostrint(f1_root) .. ", " .. tostring(f2_root))
			return 
		end
		
		return f1_root < f2_root
	end
	
	-- Errors in matching the filename pattern (no match)
	if not f1_digits then
		printe("sort_numerical_filenames_fn() | 1st filename doesn't match pattern, filename: " .. filename1)
		return
	end
	if not f2_digits then
		printe("sort_numerical_filenames_fn() | 2nd filename doesn't match pattern, filename: " .. filename2)
		return
	end
	
	-- Convert to number to get rid of leading zeroes, no extracted digits is assumed to be 1
	local filename1_nr = tonumber(f1_digits) or 1
	local filename2_nr = tonumber(f2_digits) or 1
	
	-- Filenames match, only file end can be different
	if (f1_root == f2_root) and (filename1_nr == filename2_nr) then
		return filename1 < filename2
	end
	
	-- Sort according to end digits
	return filename1_nr < filename2_nr 
end

-- Sort gives 0,1,100,1001,1002,2,3,871,99... This sort gives 0,1,2,3,99,100,101,871,1001,1002
-- The function assumes that you get the full filename like "abc.txt" or "abc_cd,e_f_127.txt" but ".txt" can be omitted
function sort_numerical_filenames_fn(filename1,filename2)
	
	-- Test whether files have end part (e.g. ".txt") and remove it
	local end_pattern = "^.+(%.[%a%d]-)$" -- any characters (1 or more), [extracted] ., [extracted] alphanumeric characters (1 or more)
	local file_ext1 = string.match(filename1, end_pattern)
	local has_file_end1 = (file_ext1 ~= nil)
	if has_file_end1 then filename1 = string.gsub(filename1, file_ext1, "") end -- remove file end
	local file_ext2 = string.match(filename2, end_pattern) -- 2nd file might have different extension, ignore it
	local has_file_end2 = (file_ext2 ~= nil)
	if has_file_end2 then filename2 = string.gsub(filename2, file_ext2, "") end -- remove file end
	 
	-- Extract digits from the end of the filenames
	local pattern = "^(.-)(%d*)$" -- any characters (0 or more), [extracted] digits (0 or more) before the end
	local f1_root, f1_digits = string.match(filename1, pattern)
	local f2_root, f2_digits = string.match(filename2, pattern)
  
	-- If filename beginning doesn't match then sort filenames by the beginning
	if f1_root ~= f2_root then
	  if (not f1_root) or (not f2_root) then  -- some error
	    printe("sort_numerical_filenames_fn() | Root doesn't exist: " .. tostrint(f1_root) .. ", " .. tostring(f2_root))
	    return 
	  end
	  
		return f1_root < f2_root
	end
	
	-- Errors in matching the filename pattern (no match)
	if not f1_digits then
		printe("sort_numerical_filenames_fn() | 1st filename doesn't match pattern, filename: " .. filename1)
		return
	end
	if not f2_digits then
		printe("sort_numerical_filenames_fn() | 2nd filename doesn't match pattern, filename: " .. filename2)
		return
	end
	
	-- Convert to number to get rid of leading zeroes, no extracted digits is assumed to be 1
	local filename1_nr = tonumber(f1_digits) or 1
	local filename2_nr = tonumber(f2_digits) or 1
	
	-- Filenames match, only file end can be different
	if (f1_root == f2_root) and (filename1_nr == filename2_nr) then
		return filename1 < filename2
	end
	
	-- Sort according to end digits
	return filename1_nr < filename2_nr 
end

-- Prints every key and value of table
function printTable1(table)
	if type(table) == "table" then
		for key,value in pairs(table) do
			print("Key:" .. tostring(key) .. " ; Value:" .. tostring(value))
		end
	else
		print(tostring(table))
	end
end

-- Print entire table contents
function printTable(table)
	print(strTable(table))
end

-- Make entire table into string recursively
function strTable(table)
   if type(table) == 'table' then
      local s = '{ '
      for k,v in pairs(table) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. strTable(v) .. ','
      end
      return s .. '} '
   else
      return tostring(table)
   end
end

-- LUA can't handle no break space symbols
function trim_nobreakspace(s)
	return s:match"^[%s\160]*(.-)[%s\160]*$"
end

-- Print error log (usually uncertain data)
function printe(str, priority)
	priority = priority or -1 -- by default, print errors even when debugging isn't on

	if str ~= last_error_msg then -- print only if it's a new error
		db("ERROR: " .. str, priority)
		last_error_msg = str
	end
end

-- Check if file exists. Returns false for a directory
function file_exists(name)
	local f=io.open(name,"r")
	if f~=nil then 
		io.close(f)
		return true 
	else 
		return false 
	end
end

-- Write t2 stuff into t1 without duplicates
function merge_tables(t1,t2)
	for k,v in pairs(t2) do
		t1[k] = v
	end
end

-- Rounds to numDecimalPlaces
-- http://lua-users.org/wiki/SimpleRound
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- Round to significant numbers
function roundSn(value, nrs)
	return string.format("%." ..nrs.. "g", value)
end

-- Convert float value to integer with provided length without considering decimal point (remove point). This is only for Fityk
function decimalToInteger(value, length)
	length = length and math.max(1, length) or 1
	if value == 0 then return 0 end
	
	-- Consider negative values
	local minus = value < 0
	if minus then
		value = -value
	end
	
	value = value * 10^(math.floor(-math.log(value, 10)) + length)
	value = round(value) * (minus and -1 or 1)
	
    return value
end

-----------------------------------------------------------
-- From: https://stackoverflow.com/questions/1340230/check-if-directory-exists-in-lua
-- Check if file/folder exists       
----------------------------------------------

-- Check if a file or directory exists in this path
-- TODO: do this only during initialization for all files and save into table. Otherwise PC is uncontrollable during fast calculations 
-- bacause CMD keeps opening and closing. At least I guess this is the issue.
function path_exists(filepath)
   local ok, err, code = os.rename(filepath, filepath) -- this function doesn't care if it's / or \ (at least on windows), todo: check on Unix
   if not ok then
      if code == 13 then
         -- Permission denied, but it exists
         return true
      end
   end
   return ok, err
end

--- Check if a directory exists in this path
function isdir(path)
   -- "/" works on both Unix and Windows for os.rename()
   return path_exists(path.."/")
end



-----------------------------------------------------------
-- From: http://lua-users.org/wiki/SimpleStats
-- Small stats library                      --
----------------------------------------------
-- Version History --
-- 1.0 First written.

-- Tables supplied as arguments are not changed.


-- Table to hold statistical functions
stats={}

-- Get the mean value of a table
function stats.mean( t )
  local sum = 0
  local count= 0

  for k,v in pairs(t) do
    if type(v) == 'number' then
      sum = sum + v
      count = count + 1
    end
  end

  return (sum / count)
end

-- Get the mode of a table.  Returns a table of values.
-- Works on anything (not just numbers).
function stats.mode( t )
  local counts={}

  for k, v in pairs( t ) do
    if counts[v] == nil then
      counts[v] = 1
    else
      counts[v] = counts[v] + 1
    end
  end

  local biggestCount = 0

  for k, v  in pairs( counts ) do
    if v > biggestCount then
      biggestCount = v
    end
  end

  local temp={}

  for k,v in pairs( counts ) do
    if v == biggestCount then
      table.insert( temp, k )
    end
  end

  return temp
end

-- Get the median of a table.
function stats.median( t )
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
    

-- Get the standard deviation of a table
function stats.standardDeviation( t )
  local m
  local vm
  local sum = 0
  local count = 0
  local result

  m = stats.mean( t )

  for k,v in pairs(t) do
    if type(v) == 'number' then
      vm = v - m
      sum = sum + (vm * vm)
      count = count + 1
    end
  end

  result = math.sqrt(sum / (count-1))

  return result
end

-- Get the max and min for a table
function stats.maxmin( t )
  local max = -infinity
  local min = infinity

  for k,v in pairs( t ) do
    if type(v) == 'number' then
      max = math.max( max, v )
      min = math.min( min, v )
    end
  end

  return max, min
end


-------------------------------------------------------------------------------------------------------------
-- MAIN PROGRAM
-------------------------------------------------------------------------------------------------------------

-- Run the script
main_program()
