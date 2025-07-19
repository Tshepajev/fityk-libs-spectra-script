-- Lua script for Fityk GUI version.
-- Script version: 4.3.1
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
-- Also change user constants in _user_constants.lua in info_folder
----------------------------------------------------------------------
-- What is system path for input folder?
-- Input folders and files in them have to exist beforehand. Fityk really doesn't like special characters anywhere.
-- Leave / or \ at the end of the string, so that a filename can be concatenated directly.
-- Windows path can be both with \ or /. However, \ is special in LUA strings, so it needs to be \\.
--work_folder = "D:/Research_analysis/Projects/2024_JET/Lab_comparison_test/Data_processing/Stage_1/"
work_folder = "E:/Research_analysis/2024.03 VTT JET/Test/"
info_folder = work_folder .. "Input_info/" -- has to contain "_user_constants.lua"
----------------------------------------------------------------------
-- CHANGE CONSTANTS ABOVE!




-------------------------------------------------------------------------------------------------------------
-- Global constants
-------------------------------------------------------------------------------------------------------------
-- Math constants
infinity = 1.79769e308 -- Fityk doesn't like math.huge
infinitesimal = 1e-18 -- a very small value but still in the ballpark of other Fityk variables

-- Constants from _user_constants.lua in info_folder
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
	is_complex_filename
	
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
	gain_functions -- table of functions
	
	forbid_lines_outside_range
	apparatus_function_fwhm -- function
	min_FWHM_function -- function
	default_max_line_influence_radius
	high_constant_bound_percentile
	max_Voigt_shape
	min_Voigt_shape
	nullify_weak_lines_data
	nullify_weak_lines_visual
	detection_sn_ratio_height
	detection_sn_ratio_area
	
	only_correct_spectra
	save_sessions
	narrower_polyline_step
	plot
	pad_x_min
	pad_x_max
	pad_y_min
	pad_y_max
	
	debug_mode
	debug_print_message_summary
	stop_after_file
	stop_before_lines
	stop_before_fitting
	stop_before_fit_window
	stop_after_fit_window
	stop_after_lock_lines
	
--]]


-------------------------------------------------------------------------------------------------------------
-- Global variables
-------------------------------------------------------------------------------------------------------------
-- TODO: noise with input info
-- TODO: integrate Fityk output organizer script
-- TODO: Write readmes for filenames
-- TODO: Write readmes for linked variables
-- TODO: Update changelog
-- TODO: Create new examples
-- TODO: use polyline directly instead of constants as local constant?
-- TODO: improve local constant algorithm when multiple active regions of linked lines are fitted

-- Hack to stop frozen script safely
stopscript = false

-- boundaries for the spectrum
startpoint = nil
endpoint = nil

-- Noise amplitudes for current file. Lines smaller than this are written as 0 intensity.
noise_stdevs = nil -- read from noise_stdevs file in Input_data_corrected/ folder
global_noise_height = 0

-- Output text file name (compiled automatically from output_data_name and output_data_end)
output_data_name_nr = nil

-- Flag for initializing the output only once
output_initialized = false

-- Initialize table for holding input_info folder data
spectra_info, pixel_info, lines_info = {},{},{}

-- The filename for the Lines_info*.csv to use with the currently processed spectra series
lines_info_filename = nil

-- The format in which the filename is constructed
filename_identifier_start = nil -- used when accessing Input_data files
filename_identifier_start_clean = nil -- used by default, except for when accessing Input_data files
filename_identifier_end = nil
filename_index_digits_nr = nil

-- Save the lines and parameters that are linked. This table is used to check which regions to activate
-- and which parameters of the line have already been fitted by and earlier linked line
-- format: tbl[line_name][param_name]["linked_name.linked_param_name"] = true
linked_lines = {}

-- This table holds the info about each line (key is line index), the sub-table has the line type, 
-- each parameter of each line, and all root parent variables of each parameter
lines_data = {}

-- This table keeps track of which lines and their parameters are fitted and shouldn't be fitted again.
-- Format: tbl[line_name][param] = true
finalized_lines_params = {}

-- Contains a list of variable names (as key) that have been fitted and are linked.
-- If the variable name is in the list then it won't be unlocked with another line and
-- won't be fitted again.
-- Format: tbl[variable_name] = true
finalized_variables = {}

-- Hold a table of error strings (as key) to print if a line fitting failed for a specific line only once
-- during the experiment series. If the fit fails systematically then the errors would clog the log.
series_fit_errors = {}


-------------------------------------------------------------------------------------------------------------
-- MAIN PROGRAM
-------------------------------------------------------------------------------------------------------------
-- Loads data from files into memory, finds defined peaks, fits them, exports the data and plots the graphs.
function main_program()
	if not file_exists(info_folder.."_user_constants.lua") then
		printe("main_program() | _user_constants.lua is not in info folder. info_folder: "..info_folder)
		return
	end
	
	-- Read in user constants from separate script (separate for reproducibility of analysis)
	F:execute("exec \'"..info_folder.."_user_constants.lua\'")
	
	-- Create stopscript in info_folder if it doesn't exist, empty it if it does.
	initialize_stopscript()
	
	-- Initialize variables defined at the start and/or re-order them
	initialize_variables()
	
	-- Reset and initialize Fityk (keeps LUA variables and Fityk GUI formatting, but e.g. user defined functions are deleted)
	reset_fityk()
	
	print([[
	Starting calculations. 
	The GUI (and the GUI output) will be mostly frozen during this process. 
	To stop the script prematurely write something in ]]..stopscript_name..[[ in Input_info folder and save the file.
	]])
	
	-- Load info from info files to LUA tables
	load_info()
	
	-- resets Fityk and asks user for run parameters
	local file_check, experiment_check, continue = user_query()
	
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
-- Initialization and info loading phase
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
	pcall(function() -- Try to undefine existing function definition to prevent crash
		F:execute("undefine VoigtFWHM")
	end)
	-- Create Voigt profile which takes FWHM as its argument, Fityk can't handle non-continuous functions due to ternary operator ("?") not supported.
	-- The function is gained by brute force fitting polynomial to FWHM vs shape vs gwidth data and then doing linear fit to the polynomials. This requires shape to remain under 20 (!!). Also it's more volatile than ordinary Voigt
	-- Analytical fn: gwidth = 2500 (50 sqrt((fwhm^2 (2169 * shape^2 + 6931.47))/(1.72243e6 * shape^2 - 1.73287e7)^2) + (2673 * fwhm * shape)/(1.72243e6 * shape^2 - 1.73287e7)) if shape > 0 and shape < 3.17185 and fwhm > 0
	-- The command has to be on one line for opening Fityk session from history
	F:execute("define VoigtFWHM(height, center, fwhm = hwhm*2, shape = 0.3[0:18]) = Voigt(height, center, fwhm*(-3.66354460031617E-10 * abs(shape)^9 + 3.69496435533307E-08 * shape^8 - 1.59975065392683E-06 * abs(shape)^7 + 0.0000389329719949874 * shape^6 - 0.000586382340638549 * abs(shape)^5 + 0.00568217176507484 * shape^4 - 0.0358091432488762 * abs(shape)^3 + 0.145909575579559 * shape^2 - 0.377843804199813 * abs(shape) + 0.599045873823219), abs(shape))")
	
	
	-- VoigtApparatus declaration
	pcall(function() -- Try to undefine existing function definition to prevent crash
		F:execute("undefine VoigtApparatus")
	end)
	-- Create Voigt profile which locks the Gaussian part width as the apparatus function.
	-- gwidth = (gauss_fwhm / 2)
	-- w_G = 2 * sqrt(ln(2)) * gwidth
	--local gwidth = apparatus_fn_fwhm / 2 / math.sqrt(math.log(2)) -- from Fityk manual at Voigt function
	F:execute("define VoigtApparatus(height, center, gwidth, shape = 0.3[0:18]) = Voigt(height, center, gwidth, shape)") -- TODO: use Voigt to get GFWHM and LFWHM automatically?
	
	-- Rectangle function declaration. The start and end parameters need to be locked, otherwise Fityk throws 
	-- "Error: Trying to reverse singular matrix. Column 1 is zeroed."
	pcall(function() -- Try to undefine existing function definition to prevent crash
		F:execute("undefine Rectangle")
	end)
	F:execute("define Rectangle(height=avgy, start, end) = Sigmoid(0, height, start, 1e-300) + Sigmoid(0, -height, end, 1e-300)")
	
	-- Another possibility for a rectangle function is 
	-- "%_1 = Polyline(-1.79769e308,0, $poly_start,0, $poly_start,$poly_height, $poly_end,$poly_height, $poly_end,0, 1.79769e308,0)"
	-- but this fits 2x slower than rectangle from 2 Sigmoids.
	
	
	-- RectanglePositive function declaration. Same as Rectangle but height is only positive.
	pcall(function() -- Try to undefine existing function definition to prevent crash
		F:execute("undefine RectanglePositive")
	end)
	F:execute("define RectanglePositive(height=avgy, start, end) = Sigmoid(0, abs(height), start, 1e-300) + Sigmoid(0, -abs(height), end, 1e-300)")
end

------------------------------------------

-- Resets data in Fityk and sets the settings again because Fityk also resets it's settings to default
function reset_fityk()
	db("reset",2)
	-- Selects the first dataset
	F:execute("use @0")
	
	-- Resets all Fityk-side info (not LUA-side, that still holds all necessary info)
	F:execute("reset")
	
	-- Define VoigtFWHM and VoigtApparatus functions and relevant settings
	initialize_fityk()
end

-- Deletes all variables
function delete_all_variables()
	db("delete_all_variables", 4)
	local variables = F:all_variables()
	for idx = #variables - 1, 0, -1 do -- iterate backwards so that loop indexing works after deletion
		F:execute("delete $"..variables[idx].name)
	end
end

-- Deletes all functions
function delete_all_functions()
	db("delete_all_functions", 4)
	local functions = F:all_functions()
	for idx = #functions - 1, 0, -1 do -- iterate backwards so that loop indexing works after deletion
		F:execute("delete %"..functions[idx].name)
	end
end

-- Deletes all datasets
function delete_all_datasets()
	db("delete_all_datasets", 4)
	
	F:execute("use @0") -- Prevent future crash because non-existent dataset is selected
	
	local series_length = F:get_dataset_count()
	for dataset_i = series_length - 1, 0, -1 do  -- iterate backwards so that loop indexing works after deletion
		F:execute("delete @"..dataset_i)
	end
end

-- Deletes all functions for dataset
function delete_dataset_functions(dataset_i)
	db("delete_dataset_functions", 4)
	local functions = F:get_components(dataset_i)
	for function_index = #functions - 1, 0, -1 do  -- iterate backwards so that loop indexing works after deletion
		F:execute("delete %"..functions[function_index].name)
	end
end

-- Deletes dataset with given index, does NOT delete variables
function delete_dataset(dataset_i)
	db("delete_dataset", 4)
	delete_dataset_functions(dataset_i)
	F:execute("delete @"..dataset_i)
end
------------------------------------------

-- Deletes all datasets, functions and variables for clean sheet
-- equivalent to F:execute("reset")
function delete_all()
	db("delete_all", 4)
	delete_all_datasets()
	delete_all_functions()
	delete_all_variables()
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
	
	-- Fill in fields which didn't have a column in input info
	finalize_pixel_info()
	
	-- Iterate over files containing pixel info
	for i,filename in ipairs(lines_files) do
		load_lines_info(filename) -- Load all info from that file
	end
	
	-- Fill in fields which didn't have a column in input info
	finalize_lines_info()
	
	-- Iterate over files containing spectra info
	for i,filename in ipairs(spectrum_files) do
		load_spectra_info(filename,pixel_files,lines_files) -- Load all info from that file
	end
	
	-- Fill in fields which didn't have a cloumn in input info
	finalize_spectra_info()
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
		
		local safe_separ = get_safe_pattern_string(separator) -- defuse special characters in identifier
		local non_empty = string.match(line, "([^" .. safe_separ .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then -- empty line or only commas
			printe("load_pixel_info() | Empty line " .. tostring(pixel_index))
			goto load_pixel_info_continue -- skip line in file
		end 
		
		local values = split_string_csv(line,separator) -- table of csv values
		
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
function finalize_pixel_info()
	db("finalize_pixel_info", 1)
	
	-- Iterate over pixel info in every Pixel_info*.csv file
	for filename, file_data in pairs(pixel_info) do
		
		-- Iterate over pixel_info columns, fix empty values and generate missing fields
		validate_pixel_info(filename)
		
		
		-- Iterate over the pixels and add 2 more keys that combine experiment/camera settings for pixel-wise correction
		pixel_info[filename]["pixel_multipliers"] = {}
		pixel_info[filename]["pixel_additives"] = {}
		for pixel_index = 1, #file_data["Measured unit"] do
			
			-- Get values of intensity correction fields or get the default value if fields don't exist
			local sensitivity = pixel_info[filename]["Sensitivity"][pixel_index]
			local extra_mult = pixel_info[filename]["Additional multiplier"][pixel_index]
			local additive = pixel_info[filename]["Additional additive"][pixel_index]
			
			-- Add 2 keys that combine experiment/camera settings for pixel-wise correction
			pixel_info[filename]["pixel_multipliers"][pixel_index] = sensitivity * extra_mult
			pixel_info[filename]["pixel_additives"][pixel_index] = additive
		end
	end
end

-- Fix empty values and generate missing fields
function validate_pixel_info(filename)
	db("validate_pixel_info", 5)
	
	local default_values = {
		["Measured unit"] = nil,
		["Wavelength (m)"] = nil, --pixel_info[filename]["Measured unit"][pixel_index],
		["Sensitivity"] = 1,
		["Additional multiplier"] = 1,
		["Additional additive"] = 0
	}
	
	-- Iterate over pixel_info columns
	local file_data = pixel_info[filename]
	for field, default_value in pairs(default_values) do
		
		if field == "Measured unit" then
			if (not pixel_info[filename]["Measured unit"]) then -- Flawed file, delete it from pixel_info
				pixel_info[filename] = nil
				printe("validate_pixel_info() | File didn't contain \"Measured unit\" column. filename: "..tostring(filename))
				return
			end
			goto validate_pixel_continue
		end
		
		-- Generate missing sub-table
		if not file_data[field] then
			pixel_info[filename][field] = {}
			
			printe("validate_pixel_info() | Pixel_info input didn't contain " .. tostring(field) .. "column in " .. tostring(filename) .. " file", 0)
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
				
				printe("validate_pixel_info() | Pixel_info input didn't contain " .. tostring(field) .. "column in " .. tostring(filename) .. " file for px " .. tostring(pixel_index), 0)
			end
		end
		
		::validate_pixel_continue::
	end
end

-- Read data from Pixel_info*.csv file into LUA lines_info table
-- Columns: To fit (1/0),Fit priority (1 is first),Wavelength (m),function to fit,Max position shift (m),Max line gwidth/hwhm (m), Identificator,E_k (eV),log(A_ki*g_k/?),line index,
-- You don't need all the columns filled but the structure must remain. You need to have at least the 3 first columns filled.
function load_lines_info(filename)
	db("load_lines_info",4)
	-- Iterate over lines
	local titles
	lines_info[filename] = {} -- initialize table for that filename
	local line_index = 1 -- keeps track of how many spectral lines are to be fitted
	
	for line in io.lines(info_folder .. filename) do -- skips line if no break space is in the line
		
		local safe_separ = get_safe_pattern_string(separator) -- defuse special characters in identifier
		local non_empty = string.match(line, "([^" .. safe_separ .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then -- empty line or only commas
			goto load_lines_info_continue 
		end
		
		-- string to table of csv values
		local values = split_string_csv(line,separator)
		
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
			if (lines_info[filename][line_index]["To fit (1/0)"] == 0) or (not lines_info[filename][line_index]["Wavelength (m)"]) then
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
		["Wavelength (m)"] = nil, -- important
		["Identificator"] = "_",
		["Function to fit"] = "Voigt",
		["To fit (1/0)"] = 1, -- line is used by default if the field is empty
		["Fit priority (1 is first)"] = 1,
		["Max position shift (m)"] = 0,
		["Max line fwhm (m)"] = infinity, -- almost infinity
		["Max influence radius (m)"] = default_max_line_influence_radius,
		["Linked variables"] = nil
	}
	
	if (title == "Function to fit") then -- function type can be string
		if tonumber(value) then -- it's a number
			if (value == "0") then value = "Voigt"
			elseif (value == "1") then value = "Gaussian"
			elseif (value == "2") then value = "Lorentzian"
			else -- number undefined
				printe("check_line_info_value() | Function type number out of bounds: " .. tostring(value))
				value = nil 
			end
		end
	elseif (title == "Identificator") then -- this can be string but must be lowercase and only contain digits, letters and _
		value = strip_string(value, "%s+") -- strip whitespaces
	elseif (title == "Linked variables")  then
		value = strip_string(value, "%s+") -- strip whitespaces
		if value == "" then value = nil end -- don't allow empty string
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
function finalize_lines_info()
	db("finalize_lines_info", 1)
	
	-- Iterate over lines info in every Lines_info*.csv file
	for filename, file_data in pairs(lines_info) do
		
		-- Iterate over all lines, fix empty values and generate missing fields
		validate_lines_info(filename)
		
		
		-- iterate over lines again to check for actual influence range, considering other lines too
		for main_line_index = 1, #file_data do
			
			-- Add 1 key that describes which line indices influence the current line
			lines_info[filename][main_line_index]["Influencing_lines"] = {}
			
			local left_bound, right_bound = get_influence_range_bounds(filename, main_line_index)
			lines_info[filename][main_line_index]["Influencing_lines"]["left"] = left_bound
			lines_info[filename][main_line_index]["Influencing_lines"]["right"] = right_bound
		end
	end
end

-- Fix empty values and generate missing fields
function validate_lines_info(filename)
	db("validate_lines_info", 5)
	
	local default_values = {
		["Wavelength (m)"] = nil, -- important
		["Identificator"] = "_",
		["Function to fit"] = "Voigt",
		["To fit (1/0)"] = 1, -- line is used by default if the field is empty
		["Fit priority (1 is first)"] = 1,
		["Max position shift (m)"] = 0,
		["Max line fwhm (m)"] = infinity, -- almost infinity
		["Max influence radius (m)"] = default_max_line_influence_radius,
		["Linked variables"] = nil
	}
	
	-- Iterate over all lines (different input files might have different amount of lines)
	for line_index = 1, #lines_info[filename] do
	
		-- Iterate over lines_info columns
		for field, default_value in pairs(default_values) do
			
			-- Generate missing value from default values
			if (field ~= "Wavelength (m)") and (not lines_info[filename][line_index][field]) then
				lines_info[filename][line_index][field] = default_value
				
				db("validate_lines_info() | Lines_info input didn't contain " .. tostring(field) .. "column for line idx " .. tostring(line_index) .. " in " .. tostring(filename) .. " file", 0)
			end
		end
	end
end


-- Check for all lines and return the left and right bound for the active window for current line,
-- so that all lines that influence the current one are in the range. It's advisable to input larger 
-- "Max influence radius (m)" for very strong lines, so that weak lines far away account for that line.
-- This function makes filling Lines_info*.csv easier, since you only need to consider the line in question's 
-- width when filling "Max influence radius (m)" field (unless it's a very strong line).
function get_influence_range_bounds(filename, main_line_index)
	db("get_influence_range_bounds", 5)
	
	local file_table = lines_info[filename]
	
	local main_wl = file_table[main_line_index]["Wavelength (m)"]
	
	-- Account for line shift
	local main_shift = file_table[main_line_index]["Max position shift (m)"]
	local main_radius = file_table[main_line_index]["Max influence radius (m)"]
	local main_influence = main_shift + main_radius
	
	-- Default values if no other line influences
	-- Otherwise gets the widest range out of all influencing lines
	local left_bound = main_wl - main_influence
	local right_bound = main_wl + main_influence
	
	-- iterate over all lines and check which lines influence the current one
	for other_line_index = 1, #file_table do 
		if main_line_index ~= other_line_index then -- skip the same line
			
			local second_wl = file_table[other_line_index]["Wavelength (m)"]
			
			-- Account for line shift
			local second_shift = file_table[other_line_index]["Max position shift (m)"]
			local second_radius = file_table[other_line_index]["Max influence radius (m)"]
			local second_influence = second_shift + second_radius
			
			-- Check if secondary line influences main line
			local simple_range = main_influence + second_influence -- alternative situation if second line had 0 influence range
			local is_influencing = math.abs(second_wl - main_wl) <= simple_range -- lines are close enough for their ranges to touch
			
			-- Save the active window wavelength bounds for the main line.
			-- The bound is related to the farthest second line which's influence range still touches the influence range of the current line.
			-- The bound is either main line influence range or second line's wavelength plus half of its max fwhm 
			-- (so second line still gets decently fitted)
			if is_influencing then
				local second_fwhm = math.min(file_table[other_line_index]["Max line fwhm (m)"], second_radius / 4) -- min in case it defaulted to infinity
				
				-- gets widest range out of all influencing lines, so that the secondary line is still decently fitted
				-- the range doesn't include the entire influence range of second line, but still a bit more than the center of the secondary line
				left_bound = math.min(left_bound, second_wl - second_fwhm)
				right_bound = math.max(right_bound, second_wl + second_fwhm)
			end
		end
	end
	
	return left_bound, right_bound
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
	
	-- Iterate over lines in the file
	local titles
	for line in io.lines(info_folder .. filename) do
		
		local safe_separ = get_safe_pattern_string(separator) -- defuse special characters in identifier
		local non_empty = string.match(line, "([^" .. safe_separ .. "]+)") -- ignore separators
		if (not line) or (line == "") or (not non_empty) then goto load_spectra_info_continue end  -- empty line or only commas
		
		local values = split_string_csv(line,separator) -- table of csv values
		
		if not titles then -- first line
			titles = values -- first line has titles
		else
			local data_filename = values[1] -- get saved spectrum filename
			if (not data_filename) or (data_filename == "") then -- no filename, skip loop iteration
				printe("load_spectra_info() | No filename in the file row field. filename: "..tostring(filename))
				goto load_spectra_info_continue 
			end
			
			-- Remove the extension (e.g. ".txt")
			data_filename = remove_filename_extension(data_filename)
			
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
		end
		
		::load_spectra_info_continue::
	end
	
	-- Write missing values as default values
	--correct_spectra_info(pixel_files,lines_files)
end

-- gets the right gain function based on pre amplification setting and returns the multiplier for y-axis correction.
function actual_gain(pre_amp, gain)
	return gain_functions[pre_amp](gain) -- table comes from _user_constants.lua
end


-- In case of missing value return default value
function check_info_value(title, value)
	db("check_info_value",5)
	local default_values = {
		["Filename"] = nil, -- important, already checked
		["Pixel correction filename"] = nil, -- semi-important
		["Lines filename"] = nil, -- semi-important
		["Background filename"] = nil,
		["Series length"] = nil, -- semi-important
		["Nr. of spectra accumulations"] = 1,
		["Camera pre amplification"] = 1,
		["Camera gain"] = 0,
		["Camera gate width (s)"] = 1,
		["Additional multiplier"] = 1,
		["Additional additive"] = 0	
	}
	
	
	if (title == "Pixel correction filename") then
		value = get_sole_filename(value, pixel_info) -- nil or existing filename
	elseif (title == "Lines filename") then
		value = get_sole_filename(value, lines_info) -- nil or existing filename
	elseif (title == "Background filename") then
		if value == "" then 
			value = nil
		
		-- Add file extension if it doesn't exist
		elseif value and (value ~= "Background_info") then
			local extens_pattern = "^.+(%.[%a%d]-)$" -- any characters (1 or more), [extracted] ., [extracted] alphanumeric characters (1 or more)
			local file_ext = string.match(value, extens_pattern)
			local has_file_end = (file_ext ~= nil)
			if not has_file_end then value = value .. file_end end -- add file end
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
function finalize_spectra_info()
	db("finalize_spectra_info", 1)
	
	-- Iterate over spectra_info
	for data_filename,_ in pairs(spectra_info) do
		
		-- Fix empty values and generate missing fields
		validate_spectra_info(data_filename)
		
		-- Add 2 keys that combine experiment/camera settings for spectrum-wise correction
		local additive = spectra_info[data_filename]["Additional additive"]
		local multiplier = 1 / spectra_info[data_filename]["Nr. of spectra accumulations"] / 
			actual_gain(spectra_info[data_filename]["Camera pre amplification"], spectra_info[data_filename]["Camera gain"]) / 
			spectra_info[data_filename]["Camera gate width (s)"] / spectra_info[data_filename]["Additional multiplier"]
		spectra_info[data_filename]["spectrum_additive"] = additive
		spectra_info[data_filename]["spectrum_multiplier"] = multiplier
	end
end

-- Fix empty values and generate missing fields
function validate_spectra_info(data_filename)
	db("finalize_spectra_info", 1)
	
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
	
	-- Iterate over spectra_info columns
	for field, default_value in pairs(default_values) do
		
		-- Generate missing value from default values
		if (field ~= "Filename") and (not spectra_info[data_filename][field]) then
			spectra_info[data_filename][field] = default_value
			
			db("validate_spectra_info() | Spectra_info input didn't contain " .. tostring(field) .. "column for " .. tostring(data_filename) .. " file", 0)
		end
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


-----------------------------------
-- Program initialization
-----------------------------------

-- Asks user for run parameters
function user_query()
	db("user_query",0)
	
	-- Asks whether to use 1 experiment mode (good for debugging or line finding)
	local answer2 = F:input("Manually check 1 experiment or 1 series? [y/n]")
	
	local data_filename, experiment_check
	if answer2 == 'y' then 
		data_filename = F:input("Series 1st spectrum filename (same as in Spectra_info*.csv): ")
		
		-- Spectra info is missing for provided filename
		if not spectra_info[data_filename] then 
			printe("user_query() | \"" .. tostring(data_filename) .. "\" file is not a key in spectra_info table. Has to be same as in Spectra_info*.csv")
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
	continue_answer = continue_answer == 'y'
	
	-- Remove the extension (e.g. ".txt")
	data_filename = remove_filename_extension(data_filename)
	
	return data_filename, experiment_check, continue_answer
end


----------------------------------------------------------------------
-- Processing phase 1 - Sensitivity correction
----------------------------------------------------------------------

----------------------------
-- Extracting file identifier
----------------------------

-- Iterates over files, fits lines and outputs data
function process_data(file_check, experiment_check)
	db("process_data", 0)
	
	-- Only check one experiment, save output with that name
	if experiment_check then
		output_data_name = "Output_" ..file_check.. "_experiment_" ..experiment_check
	end
	
	-- avoid overwriting previous output
	check_output_paths()
	
	-- Checks whether to view 1 file
	if file_check then
		
		-- Reset stuff for the new spectra series
		reset_series()
		
		process_data_series(file_check, experiment_check)
	else
		
		-- Sort series filenames in ascending order for consistent output
		-- Some experimental campaigns have many spectra in one file but some have each in separate file.
		-- Either way the list needs sorting because it's uncertain how the user feeds the info in.
		local series_filenames = {}
		for k,v in pairs(spectra_info) do table.insert(series_filenames, k) end
		table.sort(series_filenames, sort_spectra_info_filenames)
		--printTable(series_filenames)
		
		-- Iterate over all data files
		for i, data_filename in ipairs(series_filenames) do
			
			-- Reset stuff for the new spectra series
			reset_series()
			
			process_data_series(data_filename, experiment_check)
			
			if stopscript then return end
		end
	end
end


----------------------------
-- Processing series
----------------------------

-- Processes one kinetic series/one crater. If nr of shots is larger than spectra in file then script searches other files with same filename start
-- Assumes that all spectra in series have same x-values
function process_data_series(data_filename, experiment_check)
	db("process_data_series", 1)
	
	-- Get the filename format (into global variables) for the current series in order to extract index from these files
	extract_file_identifier(data_filename)
	local series_id = compile_corrected_series_id()
	
	-- data_filename (with index) is the key for spectra_info table, but series_id (without index) is used when outputting/printing stuff
	
	-- Identifiers didn't have a match
	if (not filename_identifier_start_clean) or (not filename_identifier_end) then
		printe("process_data_series() | Identifiers are nil, filename: " ..tostring(data_filename).. ", start: " ..tostring(filename_identifier_start_clean).. ", end: " ..tostring(filename_identifier_end))
		return
	end
	
	-- Skip processing background files. Background correction is done before pixel- and file-wise corrections, so we don't even need correction.
	if (spectra_info[data_filename]["Background filename"] == "Background_info") then return end
	
	-- Collect the files in Input_data_corrected (corrected spectra) folder
	local pattern = compile_corrected_filename_pattern()
	local patterns_or = pattern
	local series_files = match_files(corrected_path, sort_corr_filenames_fn, patterns_or)
	
	-- Save corrected spectra file in separate folder (Input_data_corrected)
	if (tableLength(series_files) == 0) or only_correct_spectra then -- only_correct_spectra does force-overwrite
		
		-- Load in input data, do data correction and save to corrected_path
		process_raw_data_series(data_filename)
		
		-- Recheck files
		series_files = match_files(corrected_path, sort_corr_filenames_fn, patterns_or)
		
		-- Error in saving files
		if (tableLength(series_files) == 0) then 
			printe("process_data_series() | Saving corrected files failed. Skipping series: " .. series_id)
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
	
	-- Check if file existed
	if noise_stdevs then
		for i,row_table in ipairs(noise_stdevs) do
			if row_table[1] == series_id then -- it's the line of current spectra file
				noise_stdevs = row_table
				break
			end
		end
		
		-- Convert string to number 
		for i,stdev in ipairs(noise_stdevs) do
			noise_stdevs[i] = tonumber(stdev)
		end
	
	else
		printe("process_data_series() | noise_stdevs is nil. Did you manually copy " ..corrected_path.. " folder but not " ..noise_stdevs_file.. ".txt?\nWriting stdevs as 0.")
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
	local corr_file_extract_pattern = compile_corrected_filename_pattern()
	local file_index, start_prev, end_prev
	for i, filename in ipairs(series_files) do
		s1_start, s1_end = string.match(series_files[i], corr_file_extract_pattern)
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
				printe("process_data_series() | file_index initialization failed. Series: "..series_id.." Start index:"..tostring(start_ind) )
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
	
	-- Get the lines_info_filename and write it into the global variable
	get_lines_info_filename(data_filename)
	
	-- Iterate over spectra in series and process them one by one
	for current_spectrum_index = start_ind, end_ind do
		
		-- Reset stuff for each spectrum
		reset_spectrum()
		
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
				
				s2_start, s2_end = string.match(series_files[file_index], corr_file_extract_pattern)
				s2_start = tonumber(s2_start)
				s2_end = tonumber(s2_end)
		end
		
		-- If it's the last batch but input info suggests there are more then overwrite spectra_nr with the actual series length
		if (file_index == tableLength(series_files))  then -- last batch
			if s2_end then -- is initialized, therefore has at least 2 batches
				if (spectra_nr > s2_end) then -- last batch ends before input info suggests
					spectra_nr = s2_end
					printe("process_data_series() | Series is larger than input info suggests. Series: "..series_id.." File index: "..file_index.." s1_start: "..s1_start.." s1_end: "..s1_end.." s2_start: " ..tostring(s2_start).." s2_end: "..tostring(s2_end) )
				end
			elseif (spectra_nr > s1_end) then -- there's only one batch and it's smaller than input info suggests
				spectra_nr = s1_end
				printe("process_data_series() | Series is larger than input info suggests. Series: "..series_id.." File index: "..file_index.." s1_start: "..s1_start.." s1_end: "..s1_end )
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
				printe("process_data_series() | averaging spectrum isn't in either batch. Series: "..series_id.." Index: "..j.." s1_start: " ..s1_start.." s1_end: "..s1_end.." s2_start: " ..tostring(s2_start).." s2_end: "..tostring(s2_end) )
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
		dataset_from_table(current_spectrum, series_id, current_spectrum_index)
		
		-- Register the boundaries for line fitting and output image
		register_spectrum_boundaries()
		
		-- Process the spectrum (fitting)
		process_spectrum(data_filename, current_spectrum_index, experiment_check)
		if stopscript then return end -- stop the script
		
		
		-- Stop the loop if using 1 experiment view or user wants to stop the script
		if experiment_check then
			print("Stopping the script after 1 experiment check")
			stopscript = true
			return 
		end
	end
	
	
	print("Series ".. series_id .." done.")
end


-- Reset stuff for each spectra series, so that new spectra series (or Spectra_info*.csv file) can be used
function reset_series()
	db("reset_series", 1)
	
	-- Resets all Fityk-side info (not LUA-side, that still holds all necessary info)
	reset_fityk()
	
	-- Reset global variables
	series_fit_errors = {}
end

-- Reset stuff for each spectrum
function reset_spectrum()
	db("reset_spectrum", 2)
	
	-- Resets all Fityk-side info (not LUA-side, that still holds all necessary info)
	reset_fityk()
	
	-- Create a global constant
	F:execute("%bg = Constant(a = 0)") -- background continuum
	F:execute("F += %bg") -- add to the model
	
	-- Create temporary local constant for the main line (moves with the main window)
	local local_constant_name = get_local_const_name()
	F:execute("%"..local_constant_name.." = RectanglePositive(height = 0, start = 0, end = 0)")
	F:execute("F += %"..local_constant_name)
	
	-- Reset global line variables
	linked_lines = {}
	lines_data = {}
	finalized_lines_params = {}
	finalized_variables = {}
end

-- Return the name of the local constant which is associated with the main line window
function get_local_const_name()
	return "bg_local" -- Main line
end

-- Return the name of a secondary window local constant which is associated with the line of line_index
function get_secondary_local_const_name(line_index)
	return get_local_const_name().."_"..tostring(line_index)
end

-- Get the longest lines_info_filename that is defined in Spectra_info*.csv, otherwise get the longest in the folder
-- If the one defined in the data_filename is (also) the longest then use that instead
function get_lines_info_filename(data_filename)
	db("get_lines_info_filename", 1)
	
	local wanted_filename = spectra_info[data_filename] and spectra_info[data_filename]["Lines filename"]
	
	-- Find lines info file with most lines
	local table_size
	local potential_filenames = {}
	
	-- The file has already been initialized (was the longest), check if the wanted file is the same
	if lines_info_filename then 
		
		-- Filename already initialized but current filename not defined, use the last one
		if (not wanted_filename) then return end
		
		potential_filenames = {lines_info_filename, wanted_filename}
		table_size = tableLength(lines_info_filename)
		
	-- Check defined files or all Lines_info*.csv files in the folder
	else
		-- Collect lines_files to be used
		local lines_files = {}
		local has_no_filename = false -- true if any series doesn't have Lines filename defined (and isn't sole file in folder)
		for series_filename, info in pairs(spectra_info) do
			local defined_filename = info["Lines filename"]
			if defined_filename then lines_files[defined_filename] = true end
			has_no_filename = has_no_filename or (not defined_filename)
		end
		
		-- not only one lines file specified for all series, find longest list from all files in input info folder
		if has_no_filename or (tableLength(lines_files) ~= 1) then
			lines_files = lines_info
		end
		
		-- Iterate over defined files or all Lines_info*.csv files in the folder
		for filename,_ in pairs(lines_files) do
			
			-- Get nr of lines defined in the file
			local size = tableLength(lines_info[filename])
			table_size = table_size or size -- initialize value
			
			-- Save the longest list filenames
			if size == table_size then
				table.insert(potential_filenames, filename)
			
			-- overwrite variable values because there's even longer list
			elseif size > table_size then
				potential_filenames = {[1] = filename} -- (re)initialize
				table_size = size
			end
		end
	end
	
	-- Iterate over potential files and check if their contents match (wavelengths and identificator)
	local files_are_different = false
	if tableLength(potential_filenames) > 1 then
		
		local wavelengths, ids -- used to check list length but get assigned the table only after the entire first file has been iterated
		local first_wavelengths, first_ids = {}, {} -- holds temporary values to skip the length check for first file
		
		-- Iterate over filenames
		for _, filename in ipairs(potential_filenames) do
			
			-- Iterate over lines and check if the files match
			for line_index, info in ipairs(lines_info[filename]) do
					
				-- Check if the lines in different files match
				if not files_are_different then -- lazy match
					
					-- Check lengths, skip first file but check the following
					if wavelengths and (tableLength(info["Wavelength (m)"]) ~= tableLength(wavelengths)) then
						files_are_different = true
					elseif ids and (tableLength(info["Identificator"]) ~= tableLength(ids)) then
						files_are_different = true
					end
					
					if not files_are_different then -- lazy match
						
						-- initialize the wavelength and ID 
						first_wavelengths[line_index] = first_wavelengths[line_index] or info["Wavelength (m)"]
						first_ids[line_index] = first_ids[line_index] or info["Identificator"]
						
						-- check if wavelength and ID match with previously saved ones.
						files_are_different = files_are_different or (first_wavelengths[line_index] ~= info["Wavelength (m)"])
						files_are_different = files_are_different or (first_ids[line_index] ~= info["Identificator"])
					end
				end
			end
			
			-- Assign the entire table at once
			wavelengths = wavelengths or first_wavelengths
			ids = ids or first_ids
		end
	end
	
	-- Check if defined filename has the longest list of lines
	local wanted_table_size = wanted_filename and lines_info[wanted_filename] and tableLength(lines_info[wanted_filename]) or 0
	local wanted_is_longest = (wanted_table_size >= table_size)
	
	-- Use the same file for all series (duration of the script), unless the other specified file contains same data
	-- if file is initialized and wanted file is same then use wanted file
	-- elseif file is initialized and wanted file is different then use previous lines_info_filename
	-- elseif file isn't initialized and wanted file is longest then use wanted file
	-- elseif file isn't initialized and wanted file isn't longest then use random longest file 
	
	-- if file is initialized
	if lines_info_filename then
		
		-- if file is initialized and wanted file is same then use wanted file
		if not files_are_different then
			lines_info_filename = wanted_filename
		end
		
		-- if file is initialized and wanted file is different then use previous lines_info_filename; do nothing
	
	-- File isn't initialized
	else
		-- if file isn't initialized and wanted file is longest then use wanted file
		if wanted_is_longest then -- therefore also the wanted file is defined
			lines_info_filename = wanted_filename
		
		-- if file isn't initialized and wanted file isn't longest then use random longest file 
		else
			lines_info_filename = potential_filenames[1]
		end
		
		-- Print error log once if files are different and file isn't initialized
		if files_are_different then
			print("WARNING! get_lines_info_filename() | lines info is different in specified longest input files (different wavelengths and Identificators), taking longest list. You might want to input only spectra with same lines because the output must have same columns for all spectra.")
		end
	end
	
	-- Couldn't use the file that was specified
	if (lines_info_filename ~= wanted_filename) and (not wanted_is_longest) then
		printe("get_lines_info_filename() | Wanted Lines filename didn't have the most lines. Using instead: "..tostring(lines_info_filename))
	end
	
	-- Failed to initialize
	if not lines_info_filename then
		printe("get_lines_info_filename() | Failed to get lines_info_filename. data_filename: "..tostring(data_filename)..", potential_filenames: "..strTable(potential_filenames))
		stopscript = true
		return
	end
end


-- Read raw data, process it and save corrected spectra into new file in the same format
function process_raw_data_series(data_filename)
	db("process_raw_data_series", 2)
	
	print("Starting calculating noise stdevs and saving processed spectra in folder: "..corrected_path)
	
	-- Get files with data_filename beginning
	local patterns_or = {}
	local filename_pattern = compile_filename_pattern(nil, nil, nil, file_end)
	local safe_search_filename = get_safe_pattern_string(data_filename) -- escape special characters like - and +
	local f_end = get_safe_pattern_string(file_end) -- escape special characters like .
	local direct_match_pattern = "^" .. safe_search_filename .. f_end .. "$"
	
	-- "abc_P10.txt" and "abc_P1_001.txt" need to be different
	-- and "abc_001.txt" and "abc_d_001.txt" need to be different
	table.insert(patterns_or, direct_match_pattern) -- direct match
	table.insert(patterns_or, filename_pattern) -- numeric increment match
	local series_files = match_files(input_path, sort_numerical_filenames_fn, patterns_or)
	
	if tableLength(series_files) <= 0 then
		printe("process_raw_data_series() | No spectra found in series. data_filename: " ..tostring(data_filename).. ", direct_match_pattern: " ..tostring(direct_match_pattern).. ", filename_pattern: " ..tostring(filename_pattern))
		print("Did you check is_complex_filename variable and make sure that the Spectra_info*.csv contains the filenames with correct format (e.g. direct match or with _0001)?")
		return
	end
	
	local target_nr = spectra_info[data_filename]["Series length"] or 1 -- how many spectra are in the series
	local file_batches = {}
	local batch_names = {}
	
	local corrected_id = compile_corrected_series_id()
	
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
			nr_of_spectra_in_file = tableLength(split_string_csv(line,input_data_separator), true) - 1 -- get columns nr in file minus wavelength column
			io.close(file)
			
			if (nr_of_spectra_in_file > 0) then
				if (saved_nr + nr_of_spectra_in_file) > target_nr then
					printe("process_raw_data_series() | too many spectra in files vs known series length. You should correct the Spectra_info*.csv. Trying to read " .. filename)
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
						table.insert(batch_names, corrected_id.."_"..(saved_nr + 1).."-"..(saved_nr + current_nr))
					end
					
					-- Start new batch and increment statistics
					batch_files = {filename}
					saved_nr = saved_nr + current_nr
					current_nr = nr_of_spectra_in_file
					
					if (current_nr > process_nr_spectra) then
						printe("process_raw_data_series() | too big file for batch processing spectra. Trying to read " .. filename, 0)
						
						if current_nr > 0 then -- save batch if there's something to save
							table.insert(file_batches, batch_files)
							table.insert(batch_names, corrected_id.."_"..(saved_nr + 1).."-"..(saved_nr + current_nr))
						end
					end
				end
			else
				printe("process_raw_data_series() | Empty file. Trying to read " .. filename)
			end
		end
		
		-- Save last batch
		table.insert(file_batches, batch_files)
		table.insert(batch_names, corrected_id.."_"..(saved_nr + 1).."-"..(saved_nr + current_nr))
		
		if (saved_nr + current_nr) < target_nr then
			printe("process_raw_data_series() | too few spectra in files vs known series length. You should correct the Spectra_info*.csv and/or check is_complex_filename variable. Trying to read: " .. corrected_id)
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
			nr_of_spectra_in_file = nr_of_spectra_in_file + tableLength(split_string_csv(line,input_data_separator), true) - 1 -- get columns nr in file minus wavelength column
			io.close(file)
		end
		
		-- Catch errors in input info vs actual series length
		local target_nr = spectra_info[data_filename]["Series length"] or 1
		if nr_of_spectra_in_file > target_nr then
			printe("process_raw_data_series() | too many spectra in files vs known series length. You should correct the Spectra_info*.csv. Trying to read: " .. corrected_id)
		end
		if nr_of_spectra_in_file < target_nr then
			printe("process_raw_data_series() | too few spectra in files vs known series length. You should correct the Spectra_info*.csv and/or check is_complex_filename variable. Trying to read: " .. corrected_id)
		end
		
		batch_names[1] = corrected_id.. "_1-" ..nr_of_spectra_in_file
	end
	
	-- Gather all noise stdevs from series
	local series_noise_stdevs = {}
	
	-- Iterate over file batches and save the processed spectra in batches
	for i,file_batch in ipairs(file_batches) do
		local batch_name = batch_names[i] or corrected_id
		
		-- Read input series into table
		local data_table = load_raw_series(file_batch, target_nr)
		
		if (not data_table) or (tableLength(data_table) == 0) then
			printe("process_raw_data_series() | data_table is nil when using batch: " .. tostring(batch_name))
			return
		end
		
		-- Do file- and pixel-wise correction
		local noise_stdevs -- save noise estimates separately because sensitivity correction might lose that info
		data_table, noise_stdevs = data_correction(data_table, data_filename)
		series_noise_stdevs = tableConcat(series_noise_stdevs, noise_stdevs) -- concatenate the tables
		
		-- Save corrected spectra into new file
		save_corrected_spectra(data_table, batch_name)
	end
	
	-- Save noise estimates
	save_noise_stdevs(series_noise_stdevs)
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
	
	-- Iterate over lines in the file
	for line in io.lines(filepath) do
		
		-- Check if row is empty
		local safe_separ = get_safe_pattern_string(separ) -- defuse special characters in identifier
		local non_empty = string.match(line, "([^" ..safe_separ.. "]+)") -- ignore separators
		
		-- Skip empty line or only commas or comments
		if (not line) or (line == "") or (not non_empty) then goto load_raw_data_continue end  
		
		local values = split_string_csv(line,separ) -- table of csv values
		
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

----------------------------
-- Spectrum correction - sensitivity
----------------------------

-- Do file- and pixel-wise correction on spectra in table
function data_correction(data_table, data_filename)
	db("data_correction", 4)
	
	-- Background correction before other stuff
	data_table = subtract_background(data_table, data_filename)
	
	-- Load pixel-wise corrections info
	local multipliers, additives, wavelengths, avg_sensitivity_at_noise
	local pixel_info_filename = spectra_info[data_filename]["Pixel correction filename"]
	if pixel_info_filename then -- file with correction info exists
		
		-- Check for errors in pixel_info file
		if (tableLength(pixel_info[pixel_info_filename]["Measured unit"]) ~= tableLength(data_table)) then
			printe("data_correction() | Number of pixels doesn't match the number of correct rows in Pixel_info file when using " .. tostring(compile_corrected_series_id()))
		end
		
		-- Corrections info
		multipliers = pixel_info[pixel_info_filename]["pixel_multipliers"]
		additives = pixel_info[pixel_info_filename]["pixel_additives"]
		wavelengths = pixel_info[pixel_info_filename]["Wavelength (m)"]
		
		-- Estimate sensitivity
		avg_sensitivity_at_noise = get_sensitivity_at_noise_range(multipliers, wavelengths) or 1
	else
		avg_sensitivity_at_noise = 1
		printe("data_correction() | Pixel correction filename missing, skipping pixel intensity and wavelength correction for "..tostring(compile_corrected_series_id()))
	end
	
	-- Finds line detection threshold before sensitivity and x-axis correction
	local noise_stdevs
	if noise_before_sensitivity_correction then
		noise_stdevs = estimate_noise_amplitude(data_table, avg_sensitivity_at_noise)
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

-- Get median noise between noise_estimate_start and noise_estimate_end
function get_sensitivity_at_noise_range(multipliers, wavelengths)
	
	-- Gather multipliers from the noise range
	local noise_mults = {}
	for idx, wl in ipairs(wavelengths) do
		if (wl >= noise_estimate_start) and (wl <= noise_estimate_end) then
			table.insert(noise_mults, multipliers[idx])
		end
	end
	
	return wrapSilent(function() return stats.median(noise_mults) end) -- wrap in case there's an empty table
end

-- Subtract background (blind spectrum) from spectra if it's defined. 
-- Do this before other corrections, assuming that background is taken at same parameters as data.
function subtract_background(data_table, data_filename)
	db("subtract_background", 4)
	
	local background_file = spectra_info[data_filename]["Background filename"]
	if (not background_file) or (background_file == "") then return data_table end -- skip quietly when file isn't specified
	
	local background_table = load_raw_spectra(input_path, background_file, input_data_separator)
	
	if not background_table then
		printe("subtract_background() | background_table is nil when using " .. tostring(compile_corrected_series_id()))
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
function estimate_noise_amplitude(data_table, avg_sensitivity_at_noise)
	db("estimate_noise_amplitude", 4)
	
	avg_sensitivity_at_noise = avg_sensitivity_at_noise or 1
	
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
			local stdev = wrapSilent(function() return stats.standardDeviation(int_table) * avg_sensitivity_at_noise end) or 0
			table.insert(noise_stdevs, stdev)
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
function save_noise_stdevs(series_noise_stdevs)
	db("save_noise_stdevs", 2)
	
	local filepath = corrected_path..noise_stdevs_file..file_end
	
	-- Create file if needed
	local init_file = io.open(filepath,"a")
	io.close(init_file)
	
	local corrected_id = compile_corrected_series_id()
	
	-- check if stdevs for that file are already saved
	local is_saved = false
	for line in io.lines(filepath) do
		local values = split_string_csv(line,separator) -- table of csv values
		if values[1] == corrected_id then 
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
			io.write("\n" .. corrected_id..separator) -- filename
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
function dataset_from_table(data_table, series_id, spectrum_index, dataset_nr)
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
	F:execute("@0: title = \'"..tostring(series_id)..","..tostring(spectrum_index).."\'") -- experiment starts at 1 by default
	
	--F:execute("@+ <\'" ..filepath.. "\':1:" .. startstr .. ".." .. endstr .. "::") -- Loads multiple experiments from file. 
end

-- Check whether user wants to stop the script while it's still running
-- Only writes stopscript = true when file isn't empty, does nothing if file is empty.
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
	
	
	-- Check whether user wants to stop the script while it's still running
	check_stopscript()
	if stopscript then return end -- stop the script
	
	-- Get the noise amplitude estimate for current experiment
	global_noise_height = noise_stdevs and noise_stdevs[spectrum_index + 1] or 0 -- 1st value in noise_stdevs is filename, if nil then 0
	
	if stop_before_lines then
		print("Stopping the script before line creation")
		stopscript = true
		return
	end
	
	local series_id = compile_corrected_series_id()
	print("Fitting experiment: "..series_id..separator..tostring(spectrum_index))
	
	-- Generates and fits functions
	local minimal_data_value, max_constant_value, max_height_values, angle_errors, polyline_values = fit_functions(data_filename)
	
	if stopscript then return end -- stop the script
	
	-- Turn weak lines into dummies before write_output()
	if nullify_weak_lines_data then
		nullify_lines(polyline_values)
	end
	
	-- Check whether user wants to stop the script while it's still running
	check_stopscript()
	if stopscript then return end -- stop the script
	
	-- Saves functions' errors into arrays
	local errors = get_errors(data_filename, minimal_data_value, max_constant_value, max_height_values, angle_errors)
	
	-- Generate polyline as local constants in order to visualize the calculations in the sessions file and to read noise more easily.
	create_polyline_local_constant(polyline_values)
	
	-- Writes data into output file
	write_output(data_filename, spectrum_index, errors)	
	
	-- Turn weak lines into dummies after write_output()
	if nullify_weak_lines_visual and (not nullify_weak_lines_data) then
		nullify_lines(polyline_values)
	end
	
	-- Save the session in case there's bad fit
	if save_sessions then
		-- Generate polyline as local constants in order to visualize the calculations in the sessions file.
		--prepare_session_save(polyline_values)
		
		-- Save session
		F:execute("info state > \'" ..sessions_path..series_id..separator..spectrum_index.. ".fit\'")
	end
	
	-- Plots current dataset with functions
	if plot then plot_functions(series_id, spectrum_index) end
	
	print("Experiment: "..series_id..separator..spectrum_index.." done.")
	
	-- Stop at current file for debugging
	if stop_after_file then 
		if F:input("Stop at series "..series_id.."? [y/n]")  == 'y' then 
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
end

-- Read data from original spectra file into LUA table
function load_raw_csv(filepath)
	db("load_raw_csv",3)
	
	if not file_exists(filepath) then return end
	
	local csv_table = {}
	
	-- Iterate over lines in the file
	for line in io.lines(filepath) do
		
		-- Check if row is empty
		local safe_separ = get_safe_pattern_string(input_data_separator) -- defuse special characters in identifier
		local non_empty = string.match(line, "([^" .. safe_separ .. "]+)") -- ignore separators
		
		-- Skip empty line or only commas or comments
		if (not line) or (line == "") or (not non_empty) then goto load_raw_csv_continue end  
		
		local values = split_string_csv(line,input_data_separator) -- table of csv values
		
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
	
	local min_x = F:calculate_expr("min(X)")
	local max_x = F:calculate_expr("max(X)")
	
	startpoint = cut_start or min_x -- first pixel as startpoint
	endpoint = cut_end or max_x -- last pixel as end
	
	-- Constructs plot command with correct ranges and shows the entire range in the GUI for easier debugging
	local window_size = max_x - min_x
	plot_command = "plot ["..tostring(min_x - window_size * 0.05)..":"..tostring(max_x + window_size * 0.05).."] [:]"
	F:execute(plot_command)
end



----------------------------------------------------------------------
-- Fitting phase
----------------------------------------------------------------------


-- Line fitting for 1 constant and the Voigt/Gaussian/Lorentzian profiles defined for functions
function fit_functions(data_filename)
	db("fit_functions", 1)
	
	-- Fit constant first, select datapoints for that
	if (noise_estimate_start ~= -infinity) or (noise_estimate_end ~= infinity) and (not noise_before_sensitivity_correction) then -- at least one is defined and data exists after correction
		-- Select/unselect dataset points at location where should be few and only weak lines
		select_active_points(noise_estimate_start, noise_estimate_end)
	else -- no region, use all datapoints in spectrum window
		select_active_points(startpoint, endpoint)
	end
	
	-- Table to hold errors for simple variables to preserve the error after locking the variable
	local angle_errors = {}
	angle_errors.bg_local = {} -- for temporary secondary background
	angle_errors.bg_local.value = {}
	angle_errors.bg_local.error = {}
	
	-- Add a polyline (local constants) to raise the line functions back to original height. Alternative
	-- is to use Rectangle functions after fitting.
	local polyline_values = {}
	
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
	F:execute("%bg = Constant(a = "..tostring(minimal_data_value)..")") -- background continuum
	
	-- Lock constant value for fitting lines and save error before it's lost due to locking
	local constant_angle_error = 0 -- save uncertainty
	--F:execute("$constant_variable = {$constant_variable}")
	
	-- Save the error
	angle_errors.constant_angle_error = constant_angle_error
	
	
	-- Create all lines and lock all variables
	local max_height_values = {}
	initialize_all_lines(minimal_data_value, max_height_values)
	
	if stop_before_fitting then 
		print("Stopping the script before line fitting")
		stopscript = true
		return
	end
	
	-- TODO: if any one line references more than 75 % (?) of all lines then just fit the entire spectral range and all lines at once
	-- TODO: give the user an option to use fit-all mode in _user_constants.lua
	
	-- Iterates over all spectral lines
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		
		-- Check whether user wants to stop the script while it's still running
		check_stopscript()
		if stopscript then  -- stop the script
			print("WARNING: stopped script, the last line in output file is probably incomplete")
			return 
		end
		
		fit_one_line(line_index, angle_errors, polyline_values, minimal_data_value)
	end
	
	return minimal_data_value, max_constant_value, max_height_values, angle_errors, polyline_values
end

-- Create all lines and lock all used variables
-- This is necessary to link variables before first fitting
function initialize_all_lines(minimal_data_value, max_height_values)
	db("initialize_all_lines", 1)
	
	-- Create temporary local constant for the main line (moves with the main window)
	--local local_constant_name = get_local_const_name()
	--F:execute("%"..local_constant_name.." = RectanglePositive(height = 0, start = "..tostring(startpoint)..", end = "..tostring(endpoint)..")")
	
	-- Table to hold info for each line and each parameter of that line whether it was simple, locked or compound variable
	-- root_variables[line_index] = {param_name_1 = {"name" = variable_name, "v_type" = variable_type}, param_name_2 = ...}
	local root_variables = {}
	
	-- TODO: what if dummy is referenced by other lines? run save_linked_info() before create_line() and don't turn linked lines into dummies in the latter
	
	-- Iterate over all the spectral lines and create them
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		create_line(line_index, minimal_data_value, root_variables, max_height_values)
	end
	
	-- Create variables defined in the links
	local parameter_expressions = {}
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		
		-- Apply variable definitions from Lines_info*.csv, so that creating dependency links works as intended
		-- Also save parameter link expressions
		local line_expressions = apply_variable_declarations(line_index)
		parameter_expressions = tableMerge(parameter_expressions, line_expressions)
	end
	
	-- Get the dependencies of lines to link (if left line references right one then right has to be linked first or the first link is broken)
	local links_dependencies = {} -- Format: tbl[func_param] = {func_param_link1, func_param_link2, ...}
	for line_name, expr_table in pairs(parameter_expressions) do
		
		-- Get dependencies. If there are no function dependencies then the expression is executed (parameter depends only on variables, not linked to other parameters)
		local line_dependencies = get_links_dependencies(line_name, expr_table, root_variables)
		
		-- Merge the new dependencies into links_dependencies
		links_dependencies = tableMerge(links_dependencies, line_dependencies)
	end
	
	-- Sort the dependencies and create a 1D table (ordered list) of the dependencies (dependency is first and the func_param referencing it is after)
	local sorted_links_dependencies = topological_sort(links_dependencies)
	
	-- Create links for the lines that depend on other lines (variables and lines without line dependencies are already applied)
	-- Iterate over the newly-created lines and create links between them
	-- Use Linked variables equations defined in Lines_info*.csv
	for idx, func_param in ipairs(sorted_links_dependencies) do
		
		-- extract function name and parameter
		local func_name, param_name = separate_function_parameter(func_param)
		local line_index = get_line_index_by_name(func_name)
		
		-- Apply links only for that function and parameter
		apply_linked_parameter(line_index, root_variables, param_name) -- TODO: use it during line creation (guess constructor)?
	end
	
	-- Delete the variables that aren't used anywhere after linking (just in case if it improves speed)
	delete_rogue_variables()
	
	-- Iterate over the newly-created links and variables and save the info about the links for future use in linked_lines
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		save_linked_info(line_index)
		save_line_info(line_index, root_variables) -- save generic info like line type (dummy) or root variables
	end
	
	-- Lock the lines and do nothing else
	lock_lines_simple()
end

-- Create a line with the guess with mathematically locked domains. If it fails, create a dummy function for indexing.
-- Link variables after line creation.
function create_line(line_index, minimal_data_value, root_variables, max_height_values)
	db("create_line", 4)
	
	-- Get parameters for the function guessing
	local guess_parameters, max_height_value = guess_parameter_constructor(line_index, minimal_data_value)
	
	max_height_values[line_index] = max_height_value
	
	if guess_parameters then
		-- Possible error catching (if peak is outside of the range)
		local status, err = pcall(function() F:execute(tostring(guess_parameters)) end)
		
		-- Initialize variable types for that line
		if status then
			local function_name = get_fn_name(line_index)
			fn = F:get_function(function_name) -- get the newly created function
			root_variables[line_index] = get_variables_types(line_index, fn) 
		
		else -- Catch error
			printe("create_line() | Error in line creation: " .. err)
			create_dummy_function(line_index)
		end
	else
		--printe("create_line() | guess_parameters is nil")
		create_dummy_function(line_index)
	end
end


-- Constructs string for parameters to be used with "guess Voigt"
function guess_parameter_constructor(line_index, minimal_data_value)
	db("guess_parameter_constructor", 4)
	
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	
	-- line is outside range and won't be fitted
	if forbid_lines_outside_range and ((line_position < startpoint) or (line_position > endpoint)) then 
		return -- instead create a dummy function
	end
	
	
	local function_type = lines_info[lines_info_filename][line_index]["Function to fit"]
	local max_position_shift = lines_info[lines_info_filename][line_index]["Max position shift (m)"]
	local max_FWHM = lines_info[lines_info_filename][line_index]["Max line fwhm (m)"]
	
	-- Get function name
	local function_name = get_fn_name(line_index)
	
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
	local noise_level = global_noise_height
	
	--if height <= noise then -- line doesn't exist 
	local smaller_noise = 0.75 -- Low but wide line can still be distinguished from noise but I have to only use height here, so make the condition more relaxed.
	if height <= (global_noise_height * detection_sn_ratio_height * smaller_noise) then -- line doesn't exist, might be wide, so lower than global_noise_height is ok
		-- TODO: don't turn linked line into dummy here
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
	
	-- Get the min FWHM bound for the wavelength
	local min_FWHM = min_FWHM_function(line_position)
	
	-- shape and gwidth or hwhm or fwhm or just shape depending on Voigt type
	if (function_type == "Voigt") or (function_type == "VoigtFWHM") or (function_type == "VoigtApparatus") then -- Voigt or Voigt defined by fwhm or Voigt defined by apparatus fn
		-- shape 
		-- Angle variable (shape starts at 1)
		F:execute("$shape_variable_"..tostring(line_index).." = ~-0.9273")
		
		-- Limit shape for VoigtApparatus (more freedom than other Voigts)
		if (function_type == "VoigtApparatus") then
			local apparatus_fn = apparatus_function_fwhm(line_position) -- apparatus function at given wavelength
			local gwidth = apparatus_fn / 2 / math.sqrt(math.log(2)) -- from Fityk manual at Voigt function
			local max_VoigtApp_shape = get_shape(max_FWHM, gwidth)
			
			-- Lock gwidth, so it would result in GaussianFWHM of apparatus function
			parameters = parameters..", gwidth = "..tostring(gwidth)
			
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

-- Get function name by index
-- TODO: optimization: create all function names during script initialization
function get_fn_name(line_index)
	db("get_fn_name", 4)
	local sig_numbers = 6
	
	-- Get function name
	local identifier = lines_info[lines_info_filename][line_index]["Identificator"]
	
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	
	-- Fityk doesn't allow anything else besides digits, letters and _. Outputs function name in pm.
	local function_name = identifier.. "_" .. decimalToInteger(line_position, sig_numbers) 
	
	-- Check for duplicate locations. If they exist then append "_x" to the end of name. Otherwise old line gets rewritten instead of new being made.
	local similar_lines_nr = 0
	for idx, info in ipairs(lines_info[lines_info_filename]) do
		local pos = info["Wavelength (m)"]
		
		if idx >= line_index then break -- only read up to current line_index
		else 
			if (identifier == info["Identificator"]) and 
				(decimalToInteger(line_position, sig_numbers) == decimalToInteger(pos, sig_numbers)) then
				similar_lines_nr = similar_lines_nr + 1
			end
		end
	end
	similar_lines_nr = (similar_lines_nr > 0) and ("_" ..tostring(similar_lines_nr)) or ""
	local output_name = function_name.. similar_lines_nr
	
	--[[ -- this method doesn't work if the duplicate name lines aren't created (inconsistent output)
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



-- Get types for each variable of a function
function get_variables_types(line_index, fn)
	db("get_variables_types", 4)
	
	local var_types = {}
	
	-- Get parameters
	local function_name = get_fn_name(line_index)
	local param_names = get_parameter_names(function_name)
	
	-- Iterate over parameters and save root parent variable names and types
	for idx, param_name in ipairs(param_names) do
		local param_nr = idx - 1 -- parameter index starts from 0
		var_types[param_name] = get_variable_type(fn, param_name, line_index)
	end
	
	return var_types
end

-- Return a table of parameter names for the given (existing) function
function get_parameter_names(function_name)
	db("get_parameter_names", 4)
	
	local param_names = {}
	local fn = F:get_function(function_name)
	
	if not fn then 
		printe("get_parameter_names() | Function doesn't exist. function_name: "..tostring(function_name))
	end
	
	-- iterate over parameters and save their names
	local param_nr = 0
	local param_name = fn:get_param(param_nr)
	while param_name ~= "" do
		table.insert(param_names, param_name)
		param_nr = param_nr + 1
		param_name = fn:get_param(param_nr)
	end
	
	return param_names
end


-- Get the type of the variable
function get_variable_type(fn, param_name, line_index)
	db("get_variable_type", 5)
	
	local var_type = {}
	local orig_variable_name = fn:var_name(param_name)
	
	-- get the variables this compound variable references
	local root_var_names_tbl = get_root_parent_variables(orig_variable_name)
	
	-- Iterate over the root variables and save their type
	local var_types_tbl = {}
	for idx, var_name in ipairs(root_var_names_tbl) do
		
		-- Rename if constant function
		if var_name == "a" then
			root_var_names_tbl[idx] = "constant_variable"
		end
		
		-- Check root variable type
		local variable_type = get_one_variable_type(var_name)
		table.insert(var_types_tbl, variable_type)
	end
	
	var_type.names = root_var_names_tbl
	var_type.v_types = var_types_tbl
	
	return var_type
end


-- Get the type of the variable
function get_one_variable_type(variable_name)
	local var_obj = wrapSilent(function() return F:get_variable(variable_name) end)
	if var_obj:is_simple() then -- simple variable
		return "simple"
	elseif is_variable_constant(variable_name) then -- constant variable
		return "locked"
	else -- compound variable
		return "compound"
	end
end

-- Checks variable expression and determines if it's constant
function is_variable_constant(var_name)
	local expression = F:get_info("$"..var_name) -- results in "$_1883 = 2.24157108339+2.24157108339*sin($shape_variable_2) = 4.46134  [auto]" or "$b = 2+$center_variable_1 = -9.17266"
	local equation = split_string(expression, "=")[2] -- take the middle part
	equation = strip_string(equation, "%s") -- remove whitespaces
	local is_number = tonumber(equation) and true or false -- anything other than a constant will have non-digits and will return nil
	return is_number
end

-- Get the referenced variables of a variable. If the referenced variables are compound variables then recursively find the root simple variable.
-- This function works only before locking the variables for the first time. After that var:is_simple() and is_variable_constant() don't necessarily give the result I want.
function get_root_parent_variables_simple(orig_var_name, root_var_names_tbl)
	db("get_root_parent_variables_simple", 4)
	root_var_names_tbl = root_var_names_tbl or {}
	
	local var = wrapSilent(function() return F:get_variable(orig_var_name) end) -- variable object
	if var and var:is_simple() then -- simple variable
		if not is_in_table(root_var_names_tbl, orig_var_name) then table.insert(root_var_names_tbl, orig_var_name) end -- prevent duplicates
	
	elseif not is_variable_constant(orig_var_name) then -- compound variable
		
		-- get the variables this compound variable references
		local var_names = get_parent_variables(orig_var_name)
		
		-- Iterate over the variable names recursively
		for idx, name in ipairs(var_names) do
			root_var_names_tbl = get_root_parent_variables_simple(name, root_var_names_tbl)
		end
	end
	
	return root_var_names_tbl
end

-- Get the referenced variables of a variable. If the referenced variables are compound variables then recursively find the root simple/constant variable.
function get_root_parent_variables(orig_var_name, root_var_names_tbl)
	db("get_root_parent_variables", 4)
	root_var_names_tbl = root_var_names_tbl or {}
	
	local var = wrapSilent(function() return F:get_variable(orig_var_name) end) -- variable object
	if var:is_simple() or is_variable_constant(orig_var_name) then -- simple variable or constant
		if not is_in_table(root_var_names_tbl, orig_var_name) then table.insert(root_var_names_tbl, orig_var_name) end -- prevent duplicates
	
	else -- compound variable
		-- get the variables this compound variable references
		local var_names = get_parent_variables(orig_var_name)
		
		-- Iterate over the variable names recursively
		for idx, name in ipairs(var_names) do
			root_var_names_tbl = get_root_parent_variables(name, root_var_names_tbl)
		end
	end
	
	return root_var_names_tbl
end

-- Get the function.parameter names that use the variable. If any of the children are variables (not function.parameter) then recursively find the root child function.parameter.
-- The table might contain duplicates
function get_root_child_functions(orig_var_name, root_var_names_tbl)
	db("get_root_child_functions", 4)
	root_var_names_tbl = root_var_names_tbl or {}
	
	-- get and save the function.parameter names this compound variable references
	local function_names = get_child_functions(orig_var_name)
	for idx, func_name in ipairs(function_names) do
		table.insert(root_var_names_tbl, func_name)
	end
	
	-- get the variables this variable references and run the next recursion on each variable
	local variable_names = get_child_variables(orig_var_name)
	for idx, var_name in ipairs(variable_names) do
		root_var_names_tbl = get_root_child_functions(var_name, root_var_names_tbl)
	end
	
	return root_var_names_tbl
end

-- Take an expression (equation) and return a table of variables it references
function get_variables_from_expression(expression)
	return gather_matches(expression, "%$([_%w]+)") -- $, [extracted] alphanumeric characters and _ (greedy 1 or more)
end

-- Return the list of variables that are referenced in the given variable
function get_parent_variables(variable_name)
	db("get_parent_variables", 5)
	local expression = F:get_info("$"..variable_name) -- results in "$_1883 = 2.24157108339+2.24157108339*sin($shape_variable_2) = 4.46134  [auto]" or "$b = 2+$center_variable_1-$var_ex = -9.17266"
	local equation = split_string(expression, "=")[2] -- take the middle part
	local variables_list = get_variables_from_expression(equation)
	return variables_list
end

-- Return the list of variables that use the given variable
function get_child_variables(variable_name)
	db("get_child_variables", 5)
	local str = F:get_info("refs $"..variable_name) -- results in "$_1877, $b" or "$_584, %Be2_313042.center, %Be2_313042_1.center"
	local variables_list = get_variables_from_expression(str)
	return variables_list
end

-- Return the list of function.parameter names that use the given variable
function get_child_functions(variable_name)
	db("get_child_functions", 5)
	local str = F:get_info("refs $"..variable_name) -- results in "$_1877, $b" or "$_584, %Be2_313042.center, %Be2_313042_1.center"
	local functions_list = get_functions_from_expression(str)
	return functions_list
end

-- Take an expression and return a table of function.parameter names it has
function get_functions_from_expression(expression)
	return gather_matches(expression, "%%([_%w]+%.[_%w]+)") -- %; [extracted] alphanumeric characters and _ (greedy 1 or more), and ., and alphanumeric charactes and _
end

-- Get ordered list of which lines and parameters to link first in order not to break links later
function get_links_dependencies(function_name, expr_table, root_variables)
	db("get_links_dependencies", 2)
	
	local line_dependencies = {}
	
	-- If line is dummy then skip the parsing its links -- TODO: if dummy is revived then need to parse the links
	local line_index = get_line_index_by_name(function_name)
	if not root_variables[line_index] then return line_dependencies end
	
	-- Iterate over the expressions, parse them
	for expr_idx, expression in ipairs(expr_table) do
		local func_param, expression_dependencies = parse_expression_for_dependencies(expression, function_name, root_variables)
		
		-- Merge the new dependencies into line_dependencies
		if tableLength(expression_dependencies) > 0 then
			line_dependencies[func_param] = line_dependencies[func_param] or {}
			line_dependencies[func_param] = tableConcat(line_dependencies[func_param], expression_dependencies)
		end
	end
	
	return line_dependencies
end

-- Sort algorithm from ChatGPT (2025.07.12)
-- Sorts the dependencies and flattens the array, so that first elements are dependencies of later elements
function topological_sort(dependency_graph)
    local sorted = {} -- output
    local visited = {} -- don't go over same lines
    local visiting = {} -- what line is under observation

    local function visit(node)
        if visited[node] then return end -- already checked
        if visiting[node] then
            printe("topological_sort() | Cyclic dependency detected and is cut arbitrarily, check links in Lines_info*.csv. Cycle at node: " .. tostring(node))
			return
        end
		
        visiting[node] = true
		
		-- Check if the (referenced) line has references
        local deps = dependency_graph[node]
        if deps then
			
			-- Iterate over secondary references and do recursion
            for _, dep in ipairs(deps) do
                visit(dep)
            end
        end
		
		-- No more dependencies, save the line
        visiting[node] = nil
        visited[node] = true
        table.insert(sorted, node)
    end
	
	-- Iterate over line names which define expressions
    for node, _ in pairs(dependency_graph) do
        visit(node)
    end

    return sorted
end

-- Parse the given expression (linked variables) and return declared func.param string and
-- return func.param strings that the declaration references
-- Execute expressions which don't reference any other lines
function parse_expression_for_dependencies(expression, function_name, root_variables)
	db("parse_expression_for_dependencies", 3)
	
	local dependency_table = {}
	
	-- parameter declaration
	local declared_parameter_name = string.match(expression, "^([%w]+)%s-=") -- string start, [extracted] alphanumeric characters (greedy 1 or more), any whitespace characters (lazy 0 or more), =
	local func_param = function_name.."."..declared_parameter_name
	
	-- Get a list of referenced functions
	local func_param_pattern = "%%([_%w]+%.[_%w]+)" -- %; [extracted] alphanumeric characters and _ (greedy 1 or more), ., alphanumeric characters and _ (greedy 1 or more)
	local referenced_func_params = gather_matches(expression, func_param_pattern) 
	
	-- Todo: what if current parameter references a variable and that variable references another parameter?
	
	-- If there are no referenced functions then execute the expression immediately (variables are defined in apply_variable_declarations)
	if tableLength(referenced_func_params) <= 0 then
		expression = "%"..function_name.."."..expression
		F:execute(expression)
		
		-- Modify root_variables to account for the new parameter variable(s)
		local line_index = get_line_index_by_name(function_name)
		local var_names, var_types = get_link_variable_types(line_index, declared_parameter_name)
		root_variables[line_index][declared_parameter_name].names = var_names
		root_variables[line_index][declared_parameter_name].v_types = var_types
	end
	
	return func_param, referenced_func_params
end

-- Apply variable definitions from Lines_info*.csv, so that creating dependency links works as intended
-- Create all defined and referenced variables
-- Save return parameter linking expressions
function apply_variable_declarations(line_index)
	db("apply_variable_declarations", 2)
	
	local expressions = {}
	local function_name = get_fn_name(line_index)
	
	-- Get the string to parse
	local linked_string = lines_info[lines_info_filename][line_index]["Linked variables"]
	if not linked_string then return expressions end
	
	-- Get expressions to parse
	local line_expressions = split_string(linked_string, ";")
	
	-- Iterate over the expressions, parse them and execute them
	for idx, expression in ipairs(line_expressions) do
		parse_var_declaration_expression(expression, function_name, expressions)
	end
	
	return expressions
end

-- Create all defined and referenced variables in the expression
-- Save parameter linking expressions into expressions table inline
function parse_var_declaration_expression(expression, function_name, expressions)
	db("parse_var_declaration_expression", 3)
	
	-- Check if it's a variable declaration expression
	local declared_var_name = string.match(expression, "^%s-%$([_%w]+)%s-=") -- string start, whitespace characters (lazy 0 or more), $, [extracted] alphanumeric characters and _ (greedy 1 or more), any whitespace characters (lazy 0 or more), =
	
	-- Check if variable is already created, return if yes
	if declared_var_name then
		local var = wrapSilent(function() return F:get_variable(declared_var_name) end) -- variable object
		if var then
			printe("parse_var_declaration_expression() | Variable declaration but variable already exists. Linked variable command under function: "..function_name..", expression: "..expression)
			return
		end
	end
	
	-- Get a list of referenced variables
	local variable_names_table = get_variables_from_expression(expression)
	
	-- Iterate over the table and create variables that don't exist
	for idx, var_name in ipairs(variable_names_table) do
		if (var_name ~= declared_var_name) then -- don't create the declared variable yet
			
			-- check if the variable exists, create it if not
			local var = wrapSilent(function() return F:get_variable(var_name) end) -- variable object
			if not var then
				F:execute("$"..var_name.." = ~1") -- default value 1, simple variable (~)
			end
		end
	end
	
	-- Execute the variable declaration or save the parameter declaration
	if declared_var_name then -- is variable declaration
		
		-- Execute the expression and catch errors
		local status, err = pcall(function()
			F:execute(expression)
		end)
		
		if not status then 
			printe("parse_var_declaration_expression() | Failed to execute variable declaration. Expression: "..tostring(expression)..", for line: "..tostring(function_name))
		end
	
	-- Save other expressions which are function parameter linking for later use
	else
		expressions[function_name] = expressions[function_name] or {}
		table.insert(expressions[function_name], expression)
		return
	end
end

-- Use Linked variables equations defined in Lines_info*.csv
function apply_linked_parameter(line_index, root_variables, check_param_name)
	db("apply_linked_parameter", 2)
	
	if not root_variables[line_index] then return end -- line is dummy -- TODO: revive dummy?
	
	local function_name = get_fn_name(line_index)
	
	-- Get the string to parse
	local linked_string = lines_info[lines_info_filename][line_index]["Linked variables"]
	if not linked_string then return end
	
	-- Get expressions to parse
	local expressions = split_string(linked_string, ";")
	
	-- Iterate over the expressions, parse them and execute them
	for idx, expression in ipairs(expressions) do
		parse_and_execute_parameter_expression(expression, line_index, function_name, root_variables, check_param_name)
	end
end

-- Parse the given expression (linked variables) and execute it if no immediate flaws are seen
-- Returns if check_param_name is defined and the expression isn't about defining that parameter
-- All referenced and defined variables are already created in apply_variable_declarations()
function parse_and_execute_parameter_expression(expression, line_index, function_name, root_variables, check_param_name)
	db("parse_and_execute_parameter_expression", 3)
	
	-- Check if it's a variable declaration expression
	local declared_var_name = string.match(expression, "^%s-%$([_%w]+)%s-=") -- string start, whitespace characters (lazy 0 or more), $, [extracted] alphanumeric characters and _ (greedy 1 or more), any whitespace characters (lazy 0 or more), =
	if declared_var_name then return end
	
	-- Get the declared parameter
	local declared_parameter_name = string.match(expression, "^([%w]+).-=") -- string start, [extracted] alphanumeric characters (greedy 1 or more), any characters (lazy 0 or more), =
	if declared_parameter_name ~= check_param_name then return end -- wrong parameter
	
	-- Get a list of referenced functions and check if they exist, if not then return because expression is invalid
	-- The current function is newly created, others need to be checked
	local functions_iterator = string.gmatch(expression, "%%([_%w]+)") -- %, [extracted] alphanumeric characters and _ (greedy 1 or more)
	for fn_name in functions_iterator do
		
		-- Check if line is already created
		local fn = F:get_function(fn_name) -- line function
		if not fn then
			printe("parse_and_execute_parameter_expression() | Function referenced but not yet created. Linked variable command under function: "..function_name..", referenced function name: "..fn_name..", expression: "..expression)
			return
		end
		
		-- Check if the referenced function is a dummy, return if yes -- TODO: revive dummy or prevent this situation in create_line()
		local line_index = get_line_index_by_name(fn_name)
		if not root_variables[line_index] then
			printe("parse_and_execute_parameter_expression() | Function referenced a dummy. Skipping the declaration and it might break other links. Linked variable command under function: "..function_name..", referenced function name: "..fn_name..", expression: "..expression)
			return
		end
	end
	
	-- Execute the expression and catch errors
	local status, err = pcall(function() 
		
		-- add function name in the beginning and execute
		expression = "%"..function_name.."."..expression
		F:execute(expression)
		
		-- Modify root_variables to account for the new parameter variable(s)
		local var_names, var_types = get_link_variable_types(line_index, declared_parameter_name)
		root_variables[line_index][declared_parameter_name].names = var_names
		root_variables[line_index][declared_parameter_name].v_types = var_types
	end)
	
	if not status then -- had error
		printe("parse_and_execute_parameter_expression() | Executing the expression raised an error. Linked variable command under function: "..function_name..", expression: "..expression.." , error: "..tostring(err))
		return
	end
end

-- Get the type of the variable when creating a link
function get_link_variable_types(line_index, param_name)
	db("get_link_variable_types", 5)
	
	local var_types = {}
	
	-- Get the root variables (simple or constant, not compound)
	local function_name = get_fn_name(line_index)
	local fn = F:get_function(function_name) -- line function
	local variable_name = fn:var_name(param_name)
	local root_var_names_tbl = get_root_parent_variables(variable_name)
	
	-- Check if the "link" actually is just a simple variable (even if through multiple direct references without math)
	if is_linked_simple_variable(variable_name) then
		
		if tableLength(root_var_names_tbl) > 1 then -- some error in is_linked_simple_variable()
			printe("get_link_variable_types() | Is linked simple variable but there are multiple roots? line_index: "..tostring(line_index)..", param_name: "..tostring(param_name)..", variable_name: "..tostring(variable_name))
		end
		
		local var_type = "linked_simple"
		table.insert(var_types, var_type)
		return root_var_names_tbl, var_types
	end
	
	-- Iterate over the variables and save the type of each
	for idx, var_name in ipairs(root_var_names_tbl) do
		local var_type = get_one_variable_type(var_name)
		
		if (var_type == "compound") then printe("get_link_variable_types() | Root variable type is compound. Linked variable name: "..var_name)
		elseif (var_type == "simple") then var_type = "linked" end
		
		table.insert(var_types, var_type)
	end
	
	return root_var_names_tbl, var_types
end

-- Check if the parameter's variable is a simple variable or it's a compound variable with only a reference to a simple variable (and no equation) etc.
function is_linked_simple_variable(variable_name)
	db("is_linked_simple_variable", 6)
	
	-- Check if it's a simple variable
	local var_obj = wrapSilent(function() return F:get_variable(variable_name) end)
	if var_obj:is_simple() then return true end
	
	-- Check the expression if there's only "$a = $b" or something more (math)
	-- Get the expression (equation)
	local expression = F:get_info("$"..variable_name) -- results in "$_1883 = 2.24157108339+2.24157108339*sin($shape_variable_2) = 4.46134  [auto]" or "$b = 2+$center_variable_1-$var_ex = -9.17266"
	local equation = split_string(expression, "=")[2] -- take the middle part
	equation = strip_string(equation, "%s+") -- strip whitespaces
	
	-- Check if the equation only references one variable (no math), if yes then do another recursion
	local parent = string.match(equation, "^%$([_%w]+)$") -- str start, $, [extracted] alphanumeric characters and _ (greedy 1 or more), str end
	if parent then return is_linked_simple_variable(parent) end
	
	return false
end

-- Delete the variables that aren't used anywhere after linking (just in case if it improves speed)
-- Recursively check the parent variables
function delete_rogue_variables()
	db("delete_rogue_variables", 2)
	
	local check_variables = {}
	
	-- Iterate over all variables
	local variables = F:all_variables()
	for idx = 0, #variables - 1 do
		local variable_name = variables[idx].name
		check_variables[variable_name] = true
	end
	
	-- Recursively delete all unused variables and then their unused parents etc.
	delete_rogue_variables_recursive(check_variables, {})
end

-- Recursively check if the variables and their parents are used by something, delete if not
function delete_rogue_variables_recursive(check_variables, checked_variables)
	local check_parents = {}
	
	-- Iterate over variables
	for variable_name, _ in pairs(check_variables) do
		
		if not checked_variables[variable_name] then -- prevent loops
			checked_variables[variable_name] = true
			
			-- Check if the variable is used anywhere
			local child_vars = get_child_variables(variable_name)
			local child_fns = get_child_functions(variable_name)
			
			-- Exterminate and check parents if nothing depends on it
			if (tableLength(child_vars) <= 0) and (tableLength(child_fns) <= 0) then
				local parents = get_parent_variables(variable_name)
				
				-- Save into a different table to avoid duplicates
				for idx2, parent in ipairs(parents) do
					check_parents[parent] = true
				end
				
				F:execute("delete $"..variable_name)
			end
		end
	end
	
	-- Do the recursion with parents
	if (tableLength(check_parents) > 0) then
		delete_rogue_variables_recursive(check_parents, checked_variables)
	end
end

-- Save the info about which lines and parameters are linked into linked_lines table.
-- Each line that is linked to another is referenced in linked_lines. The references are two-way, so there is duplicate info.
-- This has to be run only after creating all links to get the actual root/child variables
-- E.g. %line1.height ($var1_height) depends on root variable $var_r1, which is also used by %line2.gwith. 
-- However, %line2.gwith ($var2_gwidth) references also another root variable $var_r2. Since all these are linked for fitting
-- then the process needs to recursively check all root variables and all child variables for each root variable and the
-- process needs to repeat until no new links are found. 
function save_linked_info(line_index)
	db("save_linked_info", 2)
	
	-- Get function name and function object
	local original_function_name = get_fn_name(line_index)
	local fn = F:get_function(original_function_name)
	
	-- Iterate over all parameters
	local param_nr = 0
	local original_parameter_name = fn:get_param(param_nr)
	while original_parameter_name ~= "" do
		local original_var_name = fn:var_name(original_parameter_name)
		
		-- Get all linked functions and parameters
		local links_table = linked_lines[original_function_name] and linked_lines[original_function_name][original_parameter_name] or {} -- initialize
		links_table[original_function_name.."."..original_parameter_name] = true -- save temporarily for recursion
		local links_table, checked_parents = get_linked_functions_recursive(original_function_name, original_parameter_name, original_var_name, links_table)
		
		--remove the original function from the links table (is key in linked_lines table)
		links_table[original_function_name.."."..original_parameter_name] = nil
		
		-- Save the result
		if tableLength(links_table) > 0 then 
			linked_lines[original_function_name] = linked_lines[original_function_name] or {}
			linked_lines[original_function_name][original_parameter_name] = links_table
			
			
			-- Save the line in the current linked lines keys too
			for func_param, bool in pairs(links_table) do
				
				-- extract function name and parameter
				local func_name, param_name = separate_function_parameter(func_param)
				
				-- Save the current function.parameter into the sub-table on the lines it's linked to
				linked_lines[func_name] = linked_lines[func_name] or {}
				linked_lines[func_name][param_name] = linked_lines[func_name][param_name] or {}
				linked_lines[func_name][param_name][original_function_name.."."..original_parameter_name] = true
			end
		end
		
		
		param_nr = param_nr + 1
		original_parameter_name = fn:get_param(param_nr)
	end
end


-- save generic info like line type (dummy) or root variables
function save_line_info(line_index, root_variables)
	db("save_line_info", 2)
	
	local function_name = get_fn_name(line_index)
	local parameter_names = get_parameter_names(function_name)
	
	-- Get the line type
	local line_type
	if not root_variables[line_index] then
		line_type = "dummy"
	else
		line_type = lines_info[lines_info_filename][line_index]["Function to fit"]
	end
	
	-- Save info
	lines_data[line_index] = {}
	lines_data[line_index].name = function_name
	lines_data[line_index].type = line_type
	lines_data[line_index].parameters = {}
	
	-- Iterate over parameters
	for idx, parameter_name in ipairs(parameter_names) do
		lines_data[line_index]["parameters"][parameter_name] = {}
		--[[
		-- Save root parent variables
		if line_type ~= "dummy" then
			lines_data[line_index]["parameters"][parameter_name].root_vars = root_variables[line_index][parameter_name]
		end
		lines_data[line_index]["parameters"][parameter_name].root_vars = lines_data[line_index]["parameters"][parameter_name].root_vars or {}
		--]]
		
		-- Save root parent variables
		if line_type == "dummy" then
			lines_data[line_index]["parameters"][parameter_name].root_vars = {}
			
			local direct_var_name = get_direct_variable_name(function_name, parameter_name)
			lines_data[line_index]["parameters"][parameter_name].root_vars.names = {direct_var_name}
			lines_data[line_index]["parameters"][parameter_name].root_vars.v_types = {"locked"}
		
		else
			lines_data[line_index]["parameters"][parameter_name].root_vars = root_variables[line_index][parameter_name]
		end
		
		-- Figure out whether the parameter is normal or was linked/modified.
		local parameter_type = get_parameter_type(line_index, parameter_name, root_variables, linked_lines)
		lines_data[line_index]["parameters"][parameter_name].type = parameter_type
		
		lines_data[line_index]["parameters"][parameter_name].root_vars.errors = {} -- gets actually defined in lock_lines
	end
end

-- Check if the parameter is normal, locked (constant), linked or simple (linked but only to a simple variable and nothing else)
function get_parameter_type(line_index, parameter_name, root_variables, linked_table)
	if not root_variables[line_index] then return "locked" end -- dummy
	
	--if not lines_info[lines_info_filename][line_index]["Linked lines"] then return "normal" end -- no links defined
	
	local function_name = get_fn_name(line_index)
	--if linked_table and linked_table[function_name] and (not linked_table[function_name][parameter_name]) then return "normal" end -- no links defined for the parameter, but could be locked
	if linked_table and linked_table[function_name] and linked_table[function_name][parameter_name] then return "linked" end -- links to other lines/parameters defined for the parameter
	
	-- some links/variables defined by the user in .csv (might not be for the parameter in question)
	-- check all root variables
	local is_locked = true
	for idx, var_type in ipairs(root_variables[line_index][parameter_name].v_types) do
		
		if var_type == "linked" then return "linked" end -- Linked if any is linked
		if var_type == "linked_simple" then return "linked_simple" end -- Linked_simple if any is Linked_simple -- TODO: check, if any is Linked_simple then all should be Linked_simple or I made a mistake
		if var_type == "compound" then return "compound" end -- Compound if any is compound
		
		is_locked = is_locked and (var_type == "locked") -- Locked if all are locked
	end
	if is_locked then return "locked" end
	
	-- Otherwise normal
	return "normal"
end

-- Recursively get the root parent variables and then the root child variables of those and then root parents of those etc.
function get_linked_functions_recursive(orig_function_name, orig_param_name, original_var_name, links_table, checked_parents)
	db("get_linked_functions_recursive", 5)
	
	-- Initialize tables
	links_table = links_table or {} -- save output
	checked_parents = checked_parents or {} -- save checked names to prevent loops
	
	-- Get the root parent variables this variable references. Only look for simple variables, not locked variables (constants)
	-- allow two lines to reference the same constant without being linked.
	local parent_var_names_tbl = get_root_parent_variables_simple(original_var_name)
	
	-- Iterate over the root parent variables and get the root child function.parameter names for each var_name
	for idx, var_name in ipairs(parent_var_names_tbl) do
		
		-- Prevent loops in future recursions
		if not checked_parents[var_name] then
			checked_parents[var_name] = true
			
			-- Get the root child function.parameter names this variable is used in
			local child_func_names_tbl = get_root_child_functions(var_name)
			
			-- iterate over child names and do the next recursion
			for idx, func_param_name in ipairs(child_func_names_tbl) do
				
				-- prevent checking the original function(s) again
				if not links_table[func_param_name] then
					links_table[func_param_name] = true
					
					-- Get the variable associated with the child function.parameter name
					local function_name, parameter_name = separate_function_parameter(func_param_name)
					local child_variable = get_parameter_variable(function_name, parameter_name)
					
					-- Do the next recursion
					links_table, checked_parents = get_linked_functions_recursive(orig_function_name, orig_param_name, child_variable, links_table, checked_parents)
				end
			end
		end
	end
	
	return links_table, checked_parents
end

-- Get function name and parameter name from function.parameter name
function separate_function_parameter(str)
	return table.unpack(split_string(str, "."))
end

-- Return the variable associated with the parameter of a function
function get_parameter_variable(function_name, parameter_name)
	local fn = F:get_function(function_name)
	local var_name = fn:var_name(parameter_name)
	return var_name
end

-- Lock the lines for fitting other regions
-- Gets run after fitting the local window. Center line is of interest, left stay locked, right lines get unlocked next iteration.
function lock_lines_simple()
	db("lock_lines_simple", 3)
	
	-- Iterates over all spectral lines
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		lock_parameters_simple(line_index)
	end
end

-- Lock the parameters of a line
function lock_parameters_simple(line_index)
	db("lock_parameters_simple", 4)
	
	if lines_data[line_index].type == "dummy" then return end -- dummy function
	
	-- Iterate over line parameters
	for param_name, tbl in pairs(lines_data[line_index].parameters) do
		local var_names = lines_data[line_index]["parameters"][param_name].root_vars.names
		
		-- iterate over root variable names and lock them
		for idx, var_name in ipairs(var_names) do
			F:execute("$" ..var_name.. " = {$" ..var_name.. "}")
		end
	end
end

-- Fits the current line along with any lines linked to it
-- Process only a part of spectrum at a time. Get first line (sorted by wavelength) and fit only that and lines that are in its influence diameter.
-- Also unlock other linked lines and a smaller diameter around them.
function fit_one_line(main_line_index, angle_errors, polyline_values, minimal_data_value)
	db("fit_one_line", 2)
	
	local function_name = lines_data[main_line_index].name
	
	-- Get range in which other (normal) lines influence the current line
	local beginning, ending = get_influence_range(main_line_index)
	
	-- Activate dataset points in the influence diameter (plus extra) of the main line
	select_active_points(beginning, ending)
	
	-- Check if any points are active
	local no_active_points = F:calculate_expr("max(A)") == 0
	
	-- Incorrect range, no points active
	--if (beginning == ending) or (beginning >= endpoint) or (ending <= startpoint) then
	if no_active_points then
		
		-- Exclude the line from processing
		if (lines_data[main_line_index].type ~= "dummy") then
			turn_into_dummy(main_line_index) -- is also done in process_spectrum()
			printe("fit_one_line() | No active datapoints for "..tostring(function_name)..". Turning line into dummy.", 1)
		end
		
		-- Stop for debugging
		if (stop_after_fit_window or stop_after_lock_lines) and (F:input("Stop at line index "..main_line_index.."? [y/n]")  == 'y') then
			print("Stopping the script because of your input")
			stopscript = true
		end
		
		-- Add the local constant into polyline for session output, keeps indexing
		local poly_tbl = {["start"] = beginning, ["ending"] = ending, ["height"] = 0}
		table.insert(polyline_values, poly_tbl)
		
		return
	end
	
	
	----------------------------------------------------------
	-- Fit local secondary and temporary constant 
	-- Local secondary and temporary constant to account for varying background/continuum signal. 
	-- The constant is bound between local minimal data value and maximum defined data value (percentile). 
	-- Otherwise constant is fitted too high because of wide or high lines.
	
	-- Lowest constant bound
	local minimal_data_value_temp = F:calculate_expr("min(y if a)") - minimal_data_value
	if minimal_data_value_temp < 0 then minimal_data_value_temp = 0 end -- physical constraint
	-- Highest constant bound
	local max_constant_value_temp = F:calculate_expr("centile("..tostring(high_constant_bound_percentile)..", y if a)") - minimal_data_value -- percentile
	if max_constant_value_temp < 0 then max_constant_value_temp = 0 end -- physical constraint
	
	-- Constant angle variable, starts from 3pi/2 so that sin is minimal
	F:execute("$constant_variable_local = ~4.712")
	
	-- Binds constant to be fitted between defined percentile and (minimal data value or 0)
	-- equation: constant = (maximum + minimum) / 2 + (maximum - minimum) / 2 * sin(~angle)
	local constant_parameters_temp = tostring((max_constant_value_temp + minimal_data_value_temp) / 2).." + "..tostring((max_constant_value_temp - minimal_data_value_temp) / 2).."*sin($constant_variable_local)"
	
	-- Fit temporary local constant for the main window
	local local_constant_name = get_local_const_name()
	F:execute("%"..local_constant_name.." = Rectangle(height = "..tostring(constant_parameters_temp)..", start = "..tostring(beginning)..", end = "..tostring(ending)..")")
	
	
	----------------------------------------------------------
	
	
	-- dummy function, don't fit lines, but fit the local constant
	local is_dummy = lines_data[main_line_index].type == "dummy"
	
	local main_window_lines
	local secondary_windows_lines = {}
	local local_constant_names = {}
	
	if not is_dummy then 
		main_window_lines = gather_lines_main(main_line_index) -- Format: tbl[func_name][param_name] = true
		local directly_linked_lines_list = gather_linked_lines(main_line_index) -- Format: tbl[func_name] = line_idx
		
		-- TODO: what if another parameter of the secondary linked line is linked to a third line? -- should be diminishing deviation from ideal fit, so not important
		
		-- Activate datapoints for each linked line window
		-- Each linked line gets its own local constant which is only used temporarlily for the fitting and it's value won't be saved.
		-- It can be that multiple closeby secondary lines have local constants overlapping
		local secondary_window_bounds = {}
		for func_name, line_idx in pairs(directly_linked_lines_list) do
			if not is_linked_parameters_finalized(main_line_index, line_idx) then -- don't use window that has already been finalized (or doesn't benefit from fitting again)
				
				local secondary_window_lines, window_start, window_end = activate_secondary_window(beginning, ending, func_name, line_idx) -- Format: tbl[func_name][param_name] = true
				secondary_windows_lines = tableMerge(secondary_windows_lines, secondary_window_lines) -- Format: tbl[func_name][param_name] = true
				
				-- Gather window bounds for creating temporary secondary local constants later
				if window_start and window_end then -- if nil then is inside the main window
					local bounds = {["beginning"] = window_start, ["line_wl"] = lines_info[lines_info_filename][line_idx]["Wavelength (m)"], ["ending"] = window_end}
					table.insert(secondary_window_bounds, bounds)
				end
			end
		end
		
		-- Remove elements from secondary_windows_lines that are in main_window_lines
		for func_name, tbl in pairs(secondary_windows_lines) do
			for param_name, bool in pairs(tbl) do
				if main_window_lines[func_name] and main_window_lines[func_name][param_name] then
					secondary_windows_lines[func_name][param_name] = nil
				end
			end
		end
		
		-- Iterate over secondary windows and add local constants to these.
		-- Make sure the Rectangles don't overlap.
		secondary_window_bounds = merge_linked_windows(secondary_window_bounds)
		for idx, bounds in ipairs(secondary_window_bounds) do
			
			-- Fit temporary local constant for the linked windows
			local local_const_name = get_secondary_local_const_name(idx)
			local infinitesimal_medium = minimal_data_value * 1e-6
			local const_height = F:calculate_expr("min(y if (a and x > "..tostring(bounds.beginning).." and x < "..tostring(bounds.ending).."))") - minimal_data_value + infinitesimal_medium -- infinitesimal protects against Trying to reverse singular matrix error if starting value is 0
			F:execute("%"..local_const_name.." = RectanglePositive(height = ~{"..tostring(const_height).."}, start = "..tostring(bounds.beginning)..", end = "..tostring(bounds.ending)..")")
			F:execute("F += %"..local_const_name)
			
			table.insert(local_constant_names, local_const_name)
		end
		
		
		-- Iterate over linked lines and get the lines of those windows (narrower than main window)
		--secondary_windows_lines = gather_secondary_lines_iterate(directly_linked_lines_list) -- Format: tbl[func_name][param_name] = true
		
		-- Get all the lines and parameters associated with the current one (nearby and linked)
		local lines_params_table = tableMerge(shallowCopy(main_window_lines), secondary_windows_lines) -- Format: tbl[func_name][param_name] = true
		
		-- TODO: unlock lines very close to the main secondary line (diameter * 0.25?) and unlock lines linked to those (don't save vars for those)
		-- TODO: unlock tertiary linked lines (main is linked to line2 and line2 is linked to line3 but main isn't directly linked to line3)?
		
		-- Unlock the variables of those lines
		activate_lines(lines_params_table)
	end
	
	-- Stop for debugging
	if stop_before_fit_window and (F:input("Stop at line index "..main_line_index.." before fitting? [y/n]")  == 'y') then
		print("Stopping the script because of your input")
		stopscript = true
		return
	end
	
	
	-- catch error in case only dummies are to be fitted
	local status, err = pcall(function() 
		F:execute("@0: fit")
		--F:execute("@0: fit") -- fit 2x to avoid local minima
	end)
	if not status then
		
		-- check if all active points are 0
		local min_y = F:calculate_expr("min(y) if a")
		local max_y = F:calculate_expr("max(y) if a")
		if (min_y == 0) and (max_y == 0) then
			printe("fit_one_line() | Failed to fit line name: "..tostring(function_name)..", line type: "..tostring(lines_data[main_line_index].type).." because active points were all 0. Turning line into dummy. Error message: "..tostring(err), 1)
			--turn_into_dummy(main_line_index) -- sometimes well fitted strong line fails when window reaches it, so not a dummy
		
		-- Some other error. Print it only once per series to avoid clogging the log for a systematic line error originating from Lines_info*.csv
		else
			fit_error = "fit_one_line() | Failed to fit line name: "..tostring(function_name)..", line type: "..tostring(lines_data[main_line_index].type)..". Error message: \""..tostring(err).."\""
			if not series_fit_errors[fit_error] then printe(fit_error..". Suppressing this error for other experiments in the series.", -1) end
			series_fit_errors[fit_error] = true
		end
	end
	
	-- TODO: check if sometimes "Singular matrix cannot be reversed" and "Trying to reverse singular matrix" errors are caused because of variable linking
	
	
	-- Stop for debugging
	if stop_after_fit_window and (F:input("Stop at line index "..main_line_index.." after fitting? [y/n]")  == 'y') then
		print("Stopping the script because of your input")
		stopscript = true
		return
	end
	
	----------------------------------------------------------
	-- Calculate value and error of the local constant
	local constant_value_temp = F:calculate_expr("%"..local_constant_name..".height")
	angle_errors.bg_local.value[main_line_index] = constant_value_temp
	if (constant_value_temp == minimal_data_value_temp) or (constant_value_temp == max_constant_value_temp) then -- stopped by the bounds
		angle_errors.bg_local.error[main_line_index] = 0
	
	else -- ordinary fit
		
		-- wrap because sometimes Fityk has a zeroed covariance matrix
		local angle_error = wrapSilent(function() return F:calculate_expr("$constant_variable_local.error") end,
			function(err) printe("fit_one_line() | Failed to get $constant_variable_local.error. main_line_index: "..tostring(main_line_index)..
			", error message: "..tostring(err), 0) 
			end
		)
		
		angle_errors.bg_local.error[main_line_index] = angle_error and math.abs((max_constant_value_temp - minimal_data_value_temp) / 2 * math.cos(constant_value_temp) * angle_error) or nil
	end
	
	-- Add the local constant into polyline for session output
	local poly_tbl = {["start"] = beginning, ["ending"] = ending, ["height"] = constant_value_temp}
	table.insert(polyline_values, poly_tbl)
	
	
	----------------------------------------------------------
	
	
	if not is_dummy then -- also works if line was not dummy before fit failed
		
		-- Lock the variables of main lines
		lock_lines(main_line_index, main_window_lines)
		
		-- Iterate over secondary window lines and lock the parameters without saving the errors
		for line_name, tbl in pairs(secondary_windows_lines) do
			local line_index = get_line_index_by_name(line_name)
			lock_parameters_simple(line_index)
		end
		
		-- TODO: save secondary window local constant if the linked line won't be fitted again
		--if finalized_lines_params[function_name] and finalized_lines_params[function_name][param_name] then end
		
		-- Delete the temporary background constants of secondary windows
		for idx, func_name in ipairs(local_constant_names) do
			F:execute("delete %"..func_name)
		end
	end
	
	-- Stop for debugging
	if stop_after_lock_lines and (F:input("Stop at line index "..main_line_index.." after locking? [y/n]")  == 'y') then
		print("Stopping the script because of stop_after_lock_lines")
		stopscript = true
		return
	end
end

-- Checks all linked window bounds and creates new window ranges for local constants, so that no
-- windows overlap and previously overlapping windows touch instead at the center wavelength of the two linked lines.
-- Function mostly from ChatGPT 4o.
function merge_linked_windows(windows)
	db("merge_linked_windows", 5)
	
    -- Sort windows by their "beginning"
    table.sort(windows, function(a, b)
        return a["beginning"] < b["beginning"]
    end)
	
    local merged = {}
    local i = 1
	
	-- Iterate over windows
    while i <= #windows do
        local current = {
            ["beginning"] = windows[i]["beginning"],
            ["line_wl"] = windows[i]["line_wl"],
            ["ending"] = windows[i]["ending"]
        }
		
		-- Iterate over the windows that follow the current one while there is overlap
        local j = i + 1
        while j <= #windows do
            local next = windows[j]
			
			-- Overlap detected
            if current["ending"] >= next["beginning"] then
				
				-- If next window is fully inside the current one then simply ignore it.
				local next_is_inside_current = current["ending"] >= next["ending"]
				if not next_is_inside_current then
					
					-- Adjust current and next so they touch at midpoint
					local midpoint = (current["line_wl"] + next["line_wl"]) / 2
					current["ending"] = midpoint
					next["beginning"] = midpoint
				end
				
				-- Move to next window for continued comparison
				j = j + 1
			
			-- No overlap, save the window and move on to the next window
            else
                break
            end
        end
		
		-- Save the window and move on to the next one that isn't checked yet
        table.insert(merged, current)
        i = j
    end
	
    return merged
end

-- Check if the parameters of the secondary line that are linked to main line are all finalized (second line doesn't need to be finalized)
function is_linked_parameters_finalized(main_line_idx, second_line_idx)
	local main_line_name = lines_data[main_line_idx].name
	local second_line_name = lines_data[second_line_idx].name
	
	-- Iterate over parameters for the main line, check for links to the second line
	for parameter, _ in pairs(lines_data[main_line_idx].parameters) do
		
		-- Iterate over linked line.params
		if linked_lines[main_line_name] and linked_lines[main_line_name][parameter] then
			for func_param, links_tbl in pairs(linked_lines[main_line_name][parameter]) do
				
				-- Check if the second line parameter is linked to the main line parameter and if that parameter is finalized
				local is_link = (func_param == second_line_name.."."..parameter)
				local param_finalized = (not is_link) or (finalized_lines_params[second_line_name] and finalized_lines_params[second_line_name][parameter] and true) or false
				
				-- At least one of the linked parameters isn't finalized yet -- TODO: check root variables instead 
				if not param_finalized then return false end
			end
		end
	end
	
	return true
end

-- Activate secondary window of the line linked to the main line
function activate_secondary_window(main_window_beginning, main_window_ending, func_name, line_idx)
	local secondary_window_lines = {}
	
	-- Get range in which lines influence the current line
	local beginning2, ending2 = get_influence_range(line_idx)
	
	-- Clip the secondary range, so that it doesn't interfere with the main window
	if (beginning2 >= main_window_beginning) and (ending2 <= main_window_ending) then -- window is inside the main window
		-- skip the linked line
		return secondary_window_lines
	
	elseif (beginning2 >= main_window_beginning) and (beginning2 <= main_window_ending) then -- window interacts with main window, stays on the right
		beginning2 = clip(beginning2, main_window_ending + infinitesimal)
	
	elseif (ending2 >= main_window_beginning) and (ending2 <= main_window_ending) then -- window interacts with main window, stays on the left
		ending2 = clip(ending2, nil, main_window_beginning - infinitesimal)
	
	--elseif beginning2 > main_window_ending then -- normal, window is right of main window
	--elseif ending2 < main_window_beginning then -- normal, window is left of main window
	end
	
	-- Activate dataset points in the influence diameter (no extra) of the line linked to the main line
	activate_points(beginning2, ending2)
	
	-- Gather the lines of the secondary window part that doesn't interact with the main window
	secondary_window_lines = gather_secondary_lines(line_idx, beginning2, ending2) -- Format: tbl[func_name][param_name] = true
	
	return secondary_window_lines, beginning2, ending2
end


-- Get the left and right wavelength of the influence range of the current line
function get_influence_range(line_index)
	db("get_influence_range", 4)
	
	local beginning = lines_info[lines_info_filename][line_index]["Influencing_lines"]["left"]
	local ending = lines_info[lines_info_filename][line_index]["Influencing_lines"]["right"]
	
	if forbid_lines_outside_range then -- TODO: check new code if always must forbid
		beginning = clip(beginning, cut_start, cut_end)
		ending = clip(ending, cut_start, cut_end)
	end
	
	beginning = clip(beginning, startpoint, endpoint)
	ending = clip(ending, startpoint, endpoint)
	
	return beginning, ending
end

--[[
-- Get the left and right wavelength of the influence range of the current line
function get_influence_diameter(line_index, second_order_multiplier)
	db("get_influence_diameter", 4)
	
	local info = lines_info[lines_info_filename][line_index]
	local line_position = info["Wavelength (m)"]
	
	local line_influence_diameter = info["Max influence radius (m)"]
	
	--second_order_multiplier = 1.5 -- multiply influence diameter because influencing line might be influenced by another further away
	local beginning = line_position - line_influence_diameter * second_order_multiplier
	local ending = line_position + line_influence_diameter * second_order_multiplier
	if forbid_lines_outside_range then -- TODO: check new code if always must forbid
		beginning = clip(beginning, cut_start, cut_end)
		ending = clip(ending, cut_start, cut_end)
	end
	
	beginning = clip(beginning, startpoint, endpoint)
	ending = clip(ending, startpoint, endpoint)
	
	return beginning, ending
end
--]]

-- Return a table of lines and parameters that need to be activated for the fitting of the main line. This means lines in its influence range and
-- linked lines with some others closer to the linked line. Don't return lines which have all of their parameters fitted before due to links.
function gather_lines_to_activate(main_line_index, main_window_lines, secondary_window_lines)
	db("gather_lines_to_activate", 3)
	
	-- main_window_lines format: tbl[func_name][param_name] = true
	-- secondary_window_lines format: tbl[line_index] = true
	
	local lines_params_table = shallowCopy(main_window_lines)
	
	-- Iterate over lines in secondary windows
	for line_index, bool in secondary_window_lines do
		
		-- Iterate over parameters
		local function_name = lines_data[line_index].name
		
		-- Iterate over parameters
		for parameter, tbl in pairs(lines_data[line_index].parameters) do
			
			-- Merge tables
			lines_params_table[function_name][parameter] = true
		end
	end
	
	return lines_params_table
end

-- Gather lines within the influence range of the main line
-- Format: tbl[func_name][param_name] = true
function gather_lines_main(line_index)
	db("gather_lines_main", 3)
	
	local lines_params_table = {}
	
	local info = lines_info[lines_info_filename][line_index]
	local main_line_position = info["Wavelength (m)"]
	
	-- Get range in which lines influence the main line
	local beginning, ending = get_influence_range(line_index)
	
	-- Gather ordinary lines in main line influence range
	local influenced_line_indices = get_lines_in_range(lines_info[lines_info_filename], main_line_position, ending) -- use only the current line and lines to the right because others are already fitted and locked
	for line_idx, bool in pairs(influenced_line_indices) do
		local function_name = lines_data[line_idx].name
		lines_params_table[function_name] = {}
		
		-- Get the parameter names of the function and add them to the table
		local param_names = get_parameter_names(function_name)
		for idx, param_name in ipairs(param_names) do
			lines_params_table[function_name][param_name] = true
		end
	end
	
	return lines_params_table
end


-- Gather lines that are linked to the main one
-- Format: tbl[func_name] = line_idx
function gather_linked_lines(line_index)
	db("gather_linked_lines", 3)
	
	local lines_table = {}
	
	-- Gather linked lines
	local original_function_name = lines_data[line_index].name
	if linked_lines[original_function_name] then -- there are links
		
		-- Iterate over linked parameters of the main line
		for main_param_name, links_tbl in pairs(linked_lines[original_function_name]) do
			
			-- Iterate over other lines that are linked to the main line
			for func_param, bool in pairs(links_tbl) do
				
				-- extract function name and parameter
				local func_name, param_name = separate_function_parameter(func_param)
				
				-- Save into lines_table
				lines_table[func_name] = get_line_index_by_name(func_name)
			end
		end
	end
	
	return lines_table
end

-- Gather lines that are in the secondary active windows of lines linked to the main one
-- Format: tbl[func_name][param_name] = true
function gather_secondary_lines_iterate(linked_lines_list)
	db("gather_secondary_lines_iterate", 3)
	
	local lines_params_table = {}
	
	-- Iterate over linked lines and get the tertiary lines of the linked lines windows
	for func_name, line_idx in pairs(linked_lines_list) do
		
		-- Ignore linked lines which have had all of its parameters fitted already
		if not is_all_params_finalized(line_idx) then
			
			-- Get range in which lines influence the current line
			local beginning, ending = get_influence_range(line_idx)
			
			-- Gather lines in secondary line influence range
			local influenced_line_indices = get_lines_in_range(lines_info[lines_info_filename], beginning, ending) -- Format: tbl[line_index] = true
			
			-- Iterate over the lines in the secondary window
			for line_index, bool in pairs(influenced_line_indices) do
				
				local line_name = lines_data[line_index].name
				lines_params_table[line_name] = lines_params_table[line_name] or {}
				
				-- Iterate over parameters for that line and save the line-parameter combo (convert format for line activation and locking)
				for parameter, tbl in pairs(lines_data[line_index].parameters) do
					lines_params_table[line_name][parameter] = true
				end
			end
		end
	end
	
	return lines_params_table
end

-- Gather lines that are in the secondary active window of the line linked to the main one
-- Format: tbl[func_name][param_name] = true
function gather_secondary_lines(line_idx, beginning2, ending2)
	db("gather_secondary_lines", 3)
	
	local lines_params_table = {}
	
	-- Ignore linked lines which have had all of its parameters fitted already
	if is_all_params_finalized(line_idx) then return lines_params_table end
	
	-- Gather lines in secondary line influence range
	local influenced_line_indices = get_lines_in_range(lines_info[lines_info_filename], beginning2, ending2) -- Format: tbl[line_index] = true
	
	-- Iterate over the lines in the secondary window
	for line_index, bool in pairs(influenced_line_indices) do
		
		local line_name = lines_data[line_index].name
		lines_params_table[line_name] = lines_params_table[line_name] or {}
		
		-- Iterate over parameters for that line and save the line-parameter combo (convert format for line activation and locking)
		for parameter, tbl in pairs(lines_data[line_index].parameters) do
			lines_params_table[line_name][parameter] = true
		end
	end
	
	return lines_params_table
end

-- Check if all parameters of a line have been fitted and therefore if the line is fitted
function is_all_params_finalized(line_index)
	local all_params_finalized = true
	local line_name = lines_data[line_index].name
	
	-- Iterate over parameters for that line and save the line-parameter combo
	for parameter, tbl in pairs(lines_data[line_index].parameters) do
		all_params_finalized = all_params_finalized and finalized_lines_params[line_name] and finalized_lines_params[line_name][parameter] and true
	end
	
	return all_params_finalized
end

-- return the index of a line with the given name
function get_line_index_by_name(function_name)
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		local fn_name = get_fn_name(line_index)
		if fn_name == function_name then return line_index end
	end
end


-- Unlock existing lines
function activate_lines(lines_params_table)
	db("activate_lines",2)
	
	-- Iterate over the lines
	for function_name, parameters in pairs(lines_params_table) do
		
		-- Check if line is already created
		local fn = F:get_function(function_name) -- line function
		if fn then 
			
			local line_index = get_line_index_by_name(function_name)
			local is_dummy = lines_data[line_index].type == "dummy"
			if is_dummy then -- is dummy but might be only because of last pixel range, try to fit again
				
				-- TODO: revive dummy if dummy is created with different conditions (not below noise level)
				-- Only check dummies on the right side of the active range
			
			else -- proper line
				-- Iterate over parameters to unlock and unlock them
				for parameter, bool in pairs(parameters) do
					unlock_parameter(line_index, parameter)
				end
			end
		
		else
			printe("activate_lines() | line not created. Function name: "..function_name)
		end
	end
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
-- Also register fitted lines and parameters
-- Gets run after fitting the local window. Center line is of interest, left stay locked, right lines get unlocked next iteration.
function lock_lines(main_line_index, lines_params_table)
	db("lock_lines", 2)
	
	-- Iterate over the lines
	for function_name, parameters in pairs(lines_params_table) do
		lock_line(main_line_index, function_name)
	end
end

-- Lock a spectral line
function lock_line(main_line_index, function_name)
	db("lock_line", 3)
	
	local line_index = get_line_index_by_name(function_name)
	if lines_data[line_index].type == "dummy" then return end -- it's a	dummy function
	
	-- Iterate over line parameters
	for param_name, tbl in pairs(lines_data[line_index]["parameters"]) do
		lock_parameter(main_line_index, function_name, line_index, param_name)
	end
end

-- Lock a parameter
function lock_parameter(main_line_index, function_name, line_index, param_name)
	db("lock_parameter", 4)
	
	if finalized_lines_params[function_name] and finalized_lines_params[function_name][param_name] then return end -- the parameter of the line has been finalized
	
	local var_names = lines_data[line_index]["parameters"][param_name].root_vars.names
	local var_types = lines_data[line_index]["parameters"][param_name].root_vars.v_types
	
	-- iterate over root variable names
	for var_index, root_var_name in ipairs(var_names) do
		lock_variable_save_errors(main_line_index, function_name, line_index, param_name, var_types, var_index, root_var_name)
	end
	
	-- If all root variables of the parameter have been fitted then the parameter is fitted too
	if (line_index == main_line_index) then
		check_all_root_vars_fitted(main_line_index, param_name)
	end
end


-- Lock the variable, save the error and register fitted lines and parameters
function lock_variable_save_errors(main_line_index, function_name, line_index, param_name, var_types, var_index, root_var_name)
	db("lock_variable_save_errors", 5)
	
	if finalized_variables[root_var_name] then return end -- variable has been fitted and finalized
	
	-- If it's a random line then simply lock the variable
	if (main_line_index ~= line_index) then
		F:execute("$" ..root_var_name.. " = {$" ..root_var_name.. "}") -- Lock the variable
		return
	end
	
	local var_type = var_types
	if type(var_types) == "table" then var_type = var_types[var_index] end
	
	if (var_type == "compound") then
		printe("lock_lines() | Locking compound variable: " .. root_var_name)
	end
	
	local var_obj = wrapSilent(function() return F:get_variable(root_var_name) end)
	
	-- Linked variable loses its error after first locking but correctly fitted line is always the leftmost linked line which is always the main line
	
	-- Get the variable error
	local error_value
	if (var_type == "locked") then
		error_value = 0
	
	elseif var_obj:is_simple() then -- can extract error (simple or linked simple)
		
		-- wrap because sometimes Fityk has a zeroed covariance matrix
		error_value = wrapSilent(function() return F:calculate_expr("$"..root_var_name..".error") end,
			function(err) printe("lock_variable_save_errors() | Failed to get $"..tostring(root_var_name).." variable error. main_line_index: "..tostring(main_line_index)..
			", error message: "..tostring(err), 0) 
			end
		)
	
	else -- e.g. compound or linked but not simple
		error_value = nil
	end
	
	-- Save the variable error under all lines that use it
	if (var_type == "linked_simple") or (var_type == "linked") then -- linked and not fitted previously
		
		-- Save the error under all linked lines that use the variable
		save_error_for_variable(root_var_name, error_value)
	
	-- Save the errors for the main line
	else
		lines_data[line_index]["parameters"][param_name]["root_vars"]["errors"][var_index] = error_value
	end
	
	-- Register that the root variable has been fitted
	finalized_variables[root_var_name] = true
	
	-- Lock the variable
	F:execute("$" ..root_var_name.. " = {$" ..root_var_name.. "}")
end

-- Save the error value in the error table under each line and parameter that uses it in lines_data
function save_error_for_variable(root_var_name, error_value)
	
	-- Get lines that use the variable
	for line_index, tbl in pairs(lines_data) do -- Iterate over line indices
		for param_name, tbl2 in pairs(tbl.parameters) do -- Iterate over parameters
			for var_idx, var_name in ipairs(tbl2.root_vars.names) do -- iterate over root variable names
				
				-- Save the error if it's the same variable
				if var_name == root_var_name then
					tbl2["root_vars"]["errors"][var_idx] = error_value
				end
			end
		end
	end
end

-- Check if all root variables of a parameter have been fitted and therefore if the line is fitted
function check_all_root_vars_fitted(line_index, parameter_name)
	local all_vars_fitted = true
	
	-- Iterate over all root variables of the parameter
	local var_names = lines_data[line_index]["parameters"][parameter_name]["root_vars"].names
	for var_index, root_var_name in ipairs(var_names) do
		
		-- Check if each variable is fitted
		all_vars_fitted = all_vars_fitted and finalized_variables[root_var_name]
	end
	
	if all_vars_fitted then
		local function_name = lines_data[line_index].name
		finalized_lines_params[function_name] = finalized_lines_params[function_name] or {}
		finalized_lines_params[function_name][parameter_name] = true
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
	
	-- No active datapoints
	--if beginning == ending then return end
	
	F:execute("@0: A = x > "..tostring(beginning).." and x < "..tostring(ending))
end

-- Only activate points on spectrum
function activate_points(beginning, ending)
	db("activate_points", 4)
	
	-- Select first dataset
	F:execute("use @0")
	
	-- Clip the points between observable spectrum
	beginning = clip(beginning, startpoint, endpoint)
	ending = clip(ending, startpoint, endpoint)
	
	F:execute("@0: A = a or (x > "..tostring(beginning).." and x < "..tostring(ending)..")")
end

-- Only deactivate points on spectrum
function deactivate_points(beginning, ending)
	db("activate_points", 4)
	
	-- Select first dataset
	F:execute("use @0")
	
	-- Clip the points between observable spectrum
	beginning = clip(beginning, startpoint, endpoint)
	ending = clip(ending, startpoint, endpoint)
	
	F:execute("@0: A = a and not (x > "..tostring(beginning).." and x < "..tostring(ending)..")")
end

-- Get a table of line indices which are inside (or on the edge) of the determined range
-- Format: tbl[line_index] = true
function get_lines_in_range(lines_info_table, beginning, ending)
	db("get_lines_in_range",4)
	
	local line_indices = {}
	for line_index, info in ipairs(lines_info_table) do
		local position = info["Wavelength (m)"]
		if (position >= beginning) and (position <= ending) then
			line_indices[line_index] = true
		end
	end
	return line_indices
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
function create_dummy_function(line_index)
	db("create_dummy_function")
	db(line_position)
	
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	local function_type = lines_info[lines_info_filename][line_index]["Function to fit"]
	
	-- Get function name
	local function_name = get_fn_name(line_index)
	
	--local sig_numbers = 6
	--local pos_name = decimalToInteger(line_position, sig_numbers) -- Fityk doesn't allow anything else besides digits, letters and _. Outputs function name in pm.
	
	
	-- gwidth, shape and fwhm might cause trouble if they're 0
	local parameter_names = {"height", "center"}
	if function_type == "Voigt" then -- Voigt
		F:execute("%" .. function_name .. " = Voigt(center = "..tostring(line_position)..", height = 0, gwidth = 1, shape = 1)")
		table.insert(parameter_names, "gwidth")
		table.insert(parameter_names, "shape")
	
	elseif function_type == "VoigtFWHM" then -- FWHM defined Voigt
		F:execute("%" .. function_name .. " = VoigtFWHM(center = "..tostring(line_position)..", height = 0, fwhm = 1, shape = 1)")
		table.insert(parameter_names, "fwhm")
		table.insert(parameter_names, "shape")
	
	elseif function_type == "VoigtApparatus" then -- Apparatus fn defined Voigt
		F:execute("%" .. function_name .. " = VoigtApparatus(center = "..tostring(line_position)..", height = 0, gwidth = 1, shape = 1)")
		table.insert(parameter_names, "gwidth")
		table.insert(parameter_names, "shape")
	
	else -- Gaussian and Lorentzian have same variables
		F:execute("%" .. function_name .. " = Gaussian(center = "..tostring(line_position)..", height = 0, hwhm = 1)")
		table.insert(parameter_names, "hwhm")
	end
	
	-- Register its parameters as fitted and root variables as fitted
	finalized_lines_params[function_name] = finalized_lines_params[function_name] or {}
	for idx, parameter_name in ipairs(parameter_names) do
		
		-- Register its parameters as fitted
		finalized_lines_params[function_name][parameter_name] = true
		
		-- Register its root variables as fitted
		local direct_var_name = get_direct_variable_name(function_name, parameter_name)
		finalized_variables[direct_var_name] = true
	end
	
	-- if line is guessed without any active datapoints then there's error 
	-- guess: empty range
	-- File not loaded or all points inactive.
	-- Instead create a line and add it to F functions
	F:execute("F += %" ..function_name)
end


-- Turn weak lines into dummies. This function is meant to be run after finishing with line fitting
function nullify_lines(polyline_values)
	db("nullify_lines", 2)
	
	-- Iterates over all spectral lines and nullifies them
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		nullify_line(line_index, polyline_values)
	end
end

-- Turn weak line into dummy. This function is meant to be run after finishing with line fitting for the line in question
function nullify_line(line_index, polyline_values)
	db("nullify_line", 3)
	
	-- Skip linked lines
	if is_linked_line(line_index) then return end -- TODO: nullify if all linked lines should be nullified
	
	-- Get function height and area
	local function_name = lines_data[line_index].name
	local fn = F:get_function(function_name) -- line function
	local height, area = wrapSilent(function() return fn:get_param_value("height"), fn:get_param_value("Area") end)
	
	-- Weird line or error somewhere before
	if (not height) or (not area) then return end
	
	-- Get the noise amplitude
	local local_constant_height = polyline_values[line_index].height
	local noise_height = math.max(local_constant_height, global_noise_height)
	
	-- Get the min FWHM bound for the wavelength
	local line_position = lines_info[lines_info_filename][line_index]["Wavelength (m)"]
	local min_FWHM = min_FWHM_function(line_position)
	
	-- Get noise area
	local breadth_multiplier = math.pi -- don't remember where it came
	--local rectangle_width = gwidth / 1.2 * breadth_multiplier -- to hwhm and then get the rectangle width
	local rectangle_width = min_FWHM / 2 * breadth_multiplier
	local noise_area = noise_height * rectangle_width -- get the rectangle area -- F:calculate_expr("x[1]-x[0]") --/ noise_stdev_calibration * detection_threshold_calibration -- minimum area of a detectable line
	
	-- Check if line area/height is stronger than noise threshold
	local area_not_small = (area / noise_area) >= detection_sn_ratio_area
	local height_not_small = (height / noise_height) >= detection_sn_ratio_height
	if area_not_small or height_not_small then return end
	
	-- Line is below noise threshold, turn into dummy
	turn_into_dummy(line_index)
end


-- If any of the parameters of this line are linked then return true
function is_linked_line(line_index)
	for param_name, param_tbl in pairs(lines_data[line_index].parameters) do
		if param_tbl.type == "linked" then return true end
	end
	return false
end

--[[
-- Estimate the local noise level as the average of global noise and polyline local height
function get_noise_estimate(location)
	local noise_level_constant = get_constant_noise_estimate(location)
	
	local noise_level = (noise_level_constant + global_noise_height) / 2
	return noise_level
end

-- Get noise estimate as the local polyline (local continuum is actually global constant + local constant)
function get_constant_noise_estimate(location)
	db("get_constant_noise_estimate", 2)
	local bg_local_fn = F:get_function("bg_local")
	local local_constant = bg_local_fn:value_at(location)
	
	return local_constant
end
--]]

-- Unlock one parameter of one function
function unlock_parameter(line_index, parameter_name)
	db("unlock_parameter", 5)
	
	-- It's a dummy
	if lines_data[line_index].type == "dummy" then return end
	
	-- The parameter has already been fitted and finalized
	local function_name = lines_data[line_index].name
	if finalized_lines_params[function_name] and finalized_lines_params[function_name][parameter_name] then return end
	
	-- Get associated root parent variable names and types
	local variable_names = lines_data[line_index]["parameters"][parameter_name].root_vars.names
	local var_types = lines_data[line_index]["parameters"][parameter_name].root_vars.v_types
	
	-- iterate over parent variable names
	for idx, variable_name in ipairs(variable_names) do
		local variable_type
		if type(var_types) == "table" then variable_type = var_types[idx]
		else variable_type = var_types end
		
		-- Check if the variable has been fitted and finalized
		if not finalized_variables[variable_name] then
			
			-- Unlock the parameter with its value
			if (variable_type == "simple") or (variable_type == "linked_simple") or (variable_type == "linked") then
				F:execute("$" ..variable_name.. " = ~{$" ..variable_name.. "}")
			
			-- Unexpected situation
			elseif (variable_type == "compound") then
				printe("unlock_parameter() | function has double-compound variable: " .. variable_name)
			end
		end
	end
end

-- Lock the parameters of the function without consideration for the variables.
-- Gets run only when nullifying the line
function turn_into_dummy(line_index)
	db("turn_into_dummy",3)
	
	local function_name = lines_data[line_index].name
	finalized_lines_params[function_name] = finalized_lines_params[function_name] or {}
	
	-- Register the line as dummy
	lines_data[line_index].type = "dummy"
	
	local fn = F:get_function(function_name) -- line function
	
	-- Iterate over parameters
	for param_name, tbl in pairs(lines_data[line_index].parameters) do
		local direct_var_name = get_direct_variable_name(function_name, param_name)
		
		-- Register all parameters as fitted
		finalized_lines_params[function_name][param_name] = true
		
		-- Register variable as fitted
		finalized_variables[direct_var_name] = true
		
		-- Register new root variables
		lines_data[line_index]["parameters"][param_name]["root_vars"]["names"] = {direct_var_name}
		lines_data[line_index]["parameters"][param_name]["root_vars"]["v_types"] = {"locked"}
		
		-- Lock the parameter directly (don't touch root variable in case something else references it)
		F:execute("$" ..direct_var_name.. " = {$" ..direct_var_name.. "}")
		
		-- Write height as 0
		if param_name == "height" then
			F:execute("$"..direct_var_name.." = 0")
		end
	end
	
	-- Remove links of the current line
	linked_lines[function_name] = nil
	
	-- Remove links to the current line
	for line_name, tbl in pairs(linked_lines) do
		for para_name, tbl2 in pairs(tbl) do
			for func_para_str, bool in pairs(tbl2) do
				
				-- extract function name and parameter
				local func_name_ref, param_name_ref = separate_function_parameter(func_para_str)
				
				-- Links the current file that's now dummy
				if func_name_ref == function_name then
					linked_lines[line_name][para_name][func_para_str] = nil
				end
			end
		end
	end
end

-- Get direct variable (not root)
function get_direct_variable_name(function_name, param_name)
	local fn = F:get_function(function_name)
	local direct_var_name = fn:var_name(param_name)
	return direct_var_name
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
	
	-- Finds dataset functions
	local functions = F:get_components(0)
	
	
	local errors = {}
	errors.height,errors.center,errors.hwhm,errors.gwidth,errors.shape = {},{},{},{},{}
	errors.local_constant = {}
	
	-- Constant
	local constant_value = F:calculate_expr("%bg.a")
	if (constant_value == minimal_data_value) or (constant_value == max_constant_value) then -- stopped by the bounds
		errors.constant_error = 0
	else -- ordinary fit
		local angle_error = angle_errors.constant_angle_error or 0
		errors.constant_error = math.abs((max_constant_value - minimal_data_value) / 2 * math.cos(constant_value) * angle_error)
	end
	
	-- Iterates over all line indices
	for line_index,_ in ipairs(lines_info[lines_info_filename]) do -- starts at 1. Constant has index 0
		errors = get_line_errors(line_index, errors, max_height_values, angle_errors)
	end
	
	return errors
end


-- Get the errors of one line
-- All errors need to be tracked (nil for non-existing parameters), so that output size would be predictable 
-- (same amount of columns for each line)
function get_line_errors(line_index, errors, max_height_values, angle_errors)
	db("get_line_errors", 2)
	
	local function_name = lines_data[line_index].name
	local function_type = lines_data[line_index].type
		
	-- Skip constant
	if function_name == "bg" then
		return errors
	end
	
	local function_obj = F:get_function(function_name)
	local height = function_obj:get_param_value("height")
	if (function_type == "dummy") or (height == 0) then -- non-existent line, errors are nil
		return errors
	end
	
	
	-- Pass local constant values on
	errors.bg_local = angle_errors.bg_local
	
	local max_h = max_height_values[line_index] or 0
	
	-- Iterate over parameters of the current line
	for parameter_name, tbl in pairs(lines_data[line_index].parameters) do
		local parameter_type = tbl.type
		
		local error_value
		if (parameter_type == "compound") or (parameter_type == "linked") or ((parameter_name == "height") and (height >= max_h)) then -- if (height >= max_h) then min function selected max_height_value or the line is non-existent
			error_value = nil -- undefined error
		
		elseif (parameter_type == "locked") then
			error_value = 0 -- no error
		
		elseif (parameter_type == "linked_simple") then
			local var_index = 1
			error_value = lines_data[line_index]["parameters"][parameter_name]["root_vars"]["errors"][var_index] -- direct error
		
		elseif (parameter_type == "normal") then
			-- wrap saves if error is nil but script tries to calculate error through angle variable, fn still needs to execute to check for vars locked in input file
			error_value = wrapSilent(calculate_normal_error_derivative, nil, line_index, parameter_name, max_height_values) -- calculated complex error (default)
		
		else
			printe("get_line_errors() | Parameter type is unconventional. parameter_type: "..tostring(parameter_type).."line_index: "..tostring(line_index))
		end
		
		-- Some lines use fwhm, some hwhm, ouptput only hwhm because they're directly correlated
		if parameter_name == "fwhm" then
			parameter_name = "hwhm"
			error_value = error_value and error_value / 2
		end
		
		-- Save the error value
		errors[parameter_name][line_index] = error_value
	end
	
	return errors
end

function calculate_normal_error_derivative(line_index, parameter_name, max_height_values)
	db("calculate_normal_error_derivative", 3)
	
	local function_name = lines_data[line_index].name
	local function_type = lines_data[line_index].type
	
	local angle_variable_index = 1
	local angle_var_name = lines_data[line_index]["parameters"][parameter_name]["root_vars"]["names"][angle_variable_index]
	local angle_var_error = lines_data[line_index]["parameters"][parameter_name]["root_vars"]["errors"][angle_variable_index]
	
	if (not angle_var_name) or (not angle_var_error) then
		printe("calculate_normal_error_derivative() | Angle variable is nil from parameter locking. angle_var_name: "..tostring(angle_var_name)..", angle_var_error: "..tostring(angle_var_error)..", line_index: "..tostring(line_index)..", parameter_name: "..tostring(parameter_name), 0)
		--return
	end
	
	-- Get the FWHM bounds
	local function_obj = F:get_function(function_name)
	local line_position = function_obj:get_param_value("center")
	local min_FWHM = min_FWHM_function(line_position)
	local max_FWHM = lines_info[lines_info_filename][line_index]["Max line fwhm (m)"] or infinity
	
	
	local error_value
	if parameter_name == "height" then
		
		-- y_error = max / 2 * cos(angle) * angle_error
		error_value = math.abs((max_height_values[line_index] / 2) * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
	
	
	elseif parameter_name == "center" then
		
		local max_position_shift = lines_info[lines_info_filename][line_index]["Max position shift (m)"]
		if max_position_shift == 0 then -- Center is locked variable
			error_value = 0
		
		elseif max_position_shift < 0 then -- Center is simple variable
			error_value = angle_var_error
		
		else -- Angle variable
			error_value = math.abs(max_position_shift * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
		end
	
	
	elseif parameter_name == "hwhm" then -- Gaussian or Lorentzian
		
		local max_hwhm = max_FWHM / 2 -- 2 * HWHM = FWHM
		local min_hwhm = min_FWHM / 2 -- 2 * HWHM = FWHM
		
		if max_hwhm == 0 then -- hwhm is locked variable
			error_value = 0
		
		elseif max_hwhm >= min_hwhm then -- hwhm is bound with an angle variable
			-- equation: hwhm = (max + min) / 2 + (max - min) / 2 * sin(angle)
			-- y_error = (max - min) / 2 * cos(angle) * angle_error
			error_value = math.abs((max_hwhm - min_hwhm) / 2 * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
		
		else -- hwhm is simple variable
			error_value = angle_var_error
		end
	
	
	-- TODO: check max_Voigt_shape effect
	
	
	elseif parameter_name == "gwidth" then -- Voigt or VoigtApparatus
		
		if (function_type == "VoigtApparatus") then
			error_value = 0 -- locked gwidth
		
		elseif (function_type == "Voigt") then -- ordinary Voigt
			
			if max_FWHM == 0 then -- gwidth is locked variable
				error_value = 0
			
			elseif max_FWHM >= min_FWHM then -- gwidth is bound with an angle variable
				local min_gwidth = get_gwidth(min_FWHM, max_Voigt_shape) -- large shape means small gwidth at same FWHM
				local max_gwidth = get_gwidth(max_FWHM, min_Voigt_shape)
				
				-- equation: gwidth = (max + min) / 2 + (max - min) / 2 * sin(angle)
				-- y_error = (max - min) / 2 * cos(angle) * angle_error
				error_value = math.abs((max_gwidth - min_gwidth) / 2 * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
			
			else -- gwidth is simple variable
				error_value = angle_var_error
			end
		end
	
	
	elseif parameter_name == "fwhm" then -- VoightFWHM
		-- TODO: convert angle_errors[line_index]["gwidth"] to fwhm
		
		if max_FWHM == 0 then -- gwidth is locked variable
			error_value = 0
		
		elseif max_FWHM >= min_FWHM then -- gwidth is bound with an angle variable					
			-- equation: gwidth = (max + min) / 2 + (max - min) / 2 * sin(angle)
			-- y_error = (max - min) / 2 * cos(angle) * angle_error
			error_value = math.abs((max_FWHM - min_FWHM) / 2 * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
		
		else -- gwidth is simple variable
			error_value = angle_var_error
		end
	
	
	elseif parameter_name == "shape" then -- Voigt or VoightApparatus or VoightFWHM
		-- y_error = 5 * cos(angle) * angle_error
		
		-- VoigtApparatus
		if (function_type == "VoigtApparatus") then
			local apparatus_fn = apparatus_function_fwhm(line_position) -- apparatus function at given wavelength
			local gwidth = apparatus_fn / 2 / math.sqrt(math.log(2)) -- from Fityk manual at Voigt function
			local max_VoigtApp_shape = get_shape(max_FWHM, gwidth)
			
			error_value = math.abs(max_VoigtApp_shape / 2 * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
		
		-- Voigt or VoigtFWHM
		else
			error_value = math.abs(max_Voigt_shape / 2 * math.cos(F:calculate_expr("$"..angle_var_name)) * angle_var_error)
		end
	
	end
	
	return error_value
end


-- Writes parameters of the functions into output file.
-- I've concluded that error values are standard errors.
function write_output(data_filename, spectrum_index, errors)
	db("write_output", 1)
	
	-- Initialize the output file
	if not output_initialized then
		output_initialized = true
		
		-- Copy _user_constants.lua to the output (increment index if already exists)
		save_user_constants()
		
		-- Write column headers
		init_output()
	end
	
	local file = io.open(output_path..output_data_name_nr,"a")
	io.output(file)
	
	local chi2 = wrap(function() return F:get_wssr(0) end) -- Weighted sum of squared residuals, a.k.a. chi^2
	local dof = wrapSilent(function() return F:get_dof(0) end) -- Degrees of freedom, requires at least one simple variable (not locked) -- TODO: save DOF for each window
	
	--local functions = F:get_components(0)

	-- Writes dataset info
	local series_id = compile_corrected_series_id()
	io.write(series_id)
	io.write(separator..spectrum_index)
	io.write(separator..chi2)
	io.write(separator..tostring(dof))
	io.write(separator..F:get_function("%bg"):get_param_value("a"))
	io.write(separator..global_noise_height)
	io.write(separator..errors.constant_error)
	
	
	
	F:execute("@+ <") -- Creates second dataset for FWHA calculations
	local FWHA_spectrum_index = F:get_dataset_count() - 1
	F:execute("use @"..tostring(FWHA_spectrum_index)) -- use new dataset
	F:execute("%FWHA = Constant(a = 0)") -- Create a dummy function
	F:execute("F += %FWHA") -- add the function to dataset functions
	
	-- Copies wavelengths into an array
	local wavelength_array = {}
	
	-- Iterates over all spectral lines
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		local function_name = lines_data[line_index].name
		local fn = F:get_function(function_name)
		table.insert(wavelength_array, fn:get_param_value("center"))
	end	
	
	local maximum = 0 -- variable to check smallest wavelength index
	
	-- Iterates over all spectral lines
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		local function_name = lines_data[line_index].name
		local fn = F:get_function(function_name)
		
		-- Get variables
		local height = fn:get_param_value("height")
		local center = fn:get_param_value("center")
		local area = fn:get_param_value("Area")
		local fwhm = fn:get_param_value("FWHM")
		
		
		-- Get variables according to the fitted line type
		local hwhm,gwidth,shape,GFWHM,LFWHM
		local function_type = lines_info[lines_info_filename][line_index]["Function to fit"]
		if function_type == "Voigt" then -- Voigt
			gwidth = math.abs(fn:get_param_value("gwidth"))
			shape = math.abs(fn:get_param_value("shape"))
			GFWHM = fn:get_param_value("GaussianFWHM")
			LFWHM = fn:get_param_value("LorentzianFWHM")
		elseif function_type == "VoigtFWHM" then -- VoigtFWHM
			hwhm = math.abs(fn:get_param_value("fwhm")) / 2 -- saves space and user happiness (output format doesn't change)
			shape = math.abs(fn:get_param_value("shape"))
		elseif function_type == "VoigtApparatus" then -- VoigtApparatus
			gwidth = math.abs(fn:get_param_value("gwidth"))
			shape = math.abs(fn:get_param_value("shape"))
		else -- Gaussian or Lorentzian
			hwhm = math.abs(fn:get_param_value("hwhm"))
		end
		
		local FWHA = get_FWHA(FWHA_spectrum_index, function_type, height, center, hwhm, gwidth, shape, fwhm) -- Full width at half area
		
		-- If there's no peak (peak height is 0) or width is 0 then all parameters are written ""
		if (lines_data[line_index].type == "dummy") or (not height) or (height <= 0) then
			io.write(string.rep(separator, 15)) -- 13 values for Voigt, Gaussian/Lorentzian have 9 values from which 7 overlap the previous ones (+2 fields for local constant)
		
		else -- Else reads errors and writes peak info into output
			-- values
			io.write(separator..tostring(height or ""))
			io.write(separator..tostring(center or ""))
			io.write(separator..tostring(hwhm or ""))
			io.write(separator..tostring(gwidth or ""))
			io.write(separator..tostring(shape or ""))
			io.write(separator..tostring(area or ""))
			io.write(separator..tostring(fwhm or ""))
			io.write(separator..tostring(FWHA or ""))
			io.write(separator..tostring(GFWHM or ""))
			io.write(separator..tostring(LFWHM or ""))
			
			-- standard errors
			io.write(separator..tostring(errors.height[line_index] or ""))
			io.write(separator..tostring(errors.center[line_index] or ""))
			io.write(separator..tostring(errors.hwhm[line_index] or ""))
			io.write(separator..tostring(errors.gwidth[line_index] or ""))
			io.write(separator..tostring(errors.shape[line_index] or ""))
		end
		
		-- Local constant, +2 fields
		io.write(separator..tostring(errors.bg_local.value[line_index] or ""))
		io.write(separator..tostring(errors.bg_local.error[line_index] or ""))
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

-- Initializes output file and write column headers, change path if needed
function init_output()
	db("init_output", 2)
	
	local file = io.open(output_path..output_data_name_nr,"w")
	io.output(file)
	
	-- First header, write line names
	io.write("All lines")
	io.write(string.rep(separator.. "All lines", 6)) -- 6 values for general info
	
	-- Iterates over all spectral lines
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		local fn_type = lines_info[lines_info_filename][line_index]["Function to fit"] -- line type
		local fn_name = lines_data[line_index].name -- line name
		local output_str = separator..tostring(line_index).." "..fn_name.." "..fn_type
		io.write(string.rep(output_str, 17)) -- 17 values for every line: 13 values for Voigt, Gaussian/Lorentzian have 9 values from which 7 overlap the previous ones, +2 for local constant
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
	
	-- Iterates over all spectral lines and writes titles to the output
	for line_index, info in ipairs(lines_info[lines_info_filename]) do
		
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
	
	io.write("\n")
	io.close(file)
end


-- Copy-paste _user_constants.lua to output folder (increment index if already exists)
function save_user_constants()
	
	-- Get the filepath with the first index that isn't used
	local index = get_output_user_constants_idx(1)
	local output_filepath = compile_output_user_constants_filepath(index)
	local input_filepath = info_folder.."_user_constants.lua"
	
	local file_out = io.open(output_filepath, "w")
	io.output(file_out)
	
	-- Copy the lines from input to output
	for line in io.lines(input_filepath) do
		io.write(line)
		io.write("\n")
	end
	
	io.close(file_out)
end

-- Recursive function that finds the first index that isn't used yet for _user_constants.lua in the output
function get_output_user_constants_idx(index)
	local filepath = compile_output_user_constants_filepath(index)
	
	-- Check next index or return the available index
	if file_exists(filepath) then
		return get_output_user_constants_idx(index + 1)
	else
		return index
	end
end

-- Get the filepath with the given index to the _user_constants.lua in the output
function compile_output_user_constants_filepath(index)
	local filepath = output_path.. "_user_constants" -- _ in front to easily find the file in the folder
	if index >= 2 then filepath = filepath.."_"..tostring(index) end -- Add index if "_user_constants.lua" exists
	filepath = filepath..".lua" 
	return filepath
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
		F:execute("%FWHA = VoigtApparatus(center = "..center..", height = "..height..", gwidth = "..gwidth..", shape = "..shape..")")
	
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
function plot_functions(series_id, spectrum_index)
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
	plot_command = plot_command.."] @0 >> \'"..output_path..series_id..separator..tostring(spectrum_index)..".png\'"
	F:execute(plot_command)
end


-- Generate a polyline to simulate the fitted local constants. 
-- This manipulation is done here instead of adding rectangle functions
-- during data fitting because that could increase fitting time.
function create_polyline_local_constant(polyline_values)
	
	-- Add a polyline (local constants) to raise the line functions back to original height. Alternative
	-- is to use Rectangle functions.
	local polyline_str = "%bg_local = Polyline(" .. tostring(-infinity) .. ",0"
	
	-- Sort polyline values by increasing start wavelengths -- they're saved in line_index order anyway
	--local function compare_start(a,b) return (a["start"] < b["start"]) end
	--table.sort(polyline_values, compare_start)
	
	-- Get step locations (wavelengths)
	local locations = {}
	
	-- Construct polyline string
	for idx, value_tbl in ipairs(polyline_values) do
		
		-- Get boundaries of current window
		local current_start = value_tbl.start
		local current_end = value_tbl.ending
		local current_center = (current_start + current_end) / 2
		
		-- Get the bondaries of previous and next windows
		local end_prev = polyline_values[idx - 1] and polyline_values[idx - 1].ending or -infinity
		local center_prev = polyline_values[idx - 1] and (end_prev + polyline_values[idx - 1].start) / 2 or -infinity
		local start_next = polyline_values[idx + 1] and polyline_values[idx + 1].start or infinity
		local center_next = polyline_values[idx + 1] and (start_next + polyline_values[idx + 1].ending) / 2 or infinity
		
		-- if two windows overlap then take the center of the centers of these as boundary (the windows might be different width)
		local use_start = current_start
		local use_end = current_end
		if current_start < end_prev then use_start = (current_center + center_prev) / 2 end
		if current_end > start_next then use_end = (current_center + center_next) / 2 end
		
		-- Initialize before first window
		if idx == 1 then polyline_str = polyline_str .. "," .. tostring(use_start) .. ",0" end -- 0 height from -infinity to here
		
		-- Fill in the gap between the windows
		if current_start > end_prev then
			polyline_str = polyline_str .. "," .. tostring(end_prev) .. ",0"
			polyline_str = polyline_str .. "," .. tostring(current_start) .. ",0"
		end
		
		-- Draw the current window
		polyline_str = polyline_str .. "," .. tostring(use_start) .. "," .. tostring(value_tbl.height)
		polyline_str = polyline_str .. "," .. tostring(use_end) .. "," .. tostring(value_tbl.height)
		
		-- Finalize after last window
		if idx == #polyline_values then polyline_str = polyline_str .. "," .. tostring(use_end) .. ",0" end -- 0 height from here to infinity
	end
	
	-- Finalize polyline string and execute
	polyline_str = polyline_str .. "," .. tostring(infinity) .. ",0)"
	F:execute(polyline_str)
	--F:execute("F += %bg_local") -- not to use if local constant isn't deleted directly after every fitting
end


-------------------------------------------------------------------------------------------------------------
-- Utility functions
-------------------------------------------------------------------------------------------------------------

-- prints if debug mode is active. The lower the priority the sooner it's printed.
-- If the debug message gets repeated multiple times then print the number of repeats
debug_message = nil
debug_count = 1
function db(something, priority)
	priority = priority or 1 -- defaults to 1
	
	-- Message is to be printed
	if (debug_mode >= priority) then
		
		-- Print each message separately
		if not debug_print_message_summary then
			printTable(something)
			return
		end
		
		-- Same message as last time
		if something == debug_message then
			debug_count = debug_count + 1
		
		-- New message
		else
			debug_message = something
			debug_count = 1
			
			-- Print new message in case this is the last debug message and there is no new iteration (message and same message with number of repeats on next line)
			printTable(something)
			
			-- Print the last message and number of times it was run
			if debug_count > 1 then
				printTable(something.." (x"..tostring(debug_count)..")")
			end
		end
	end
end

-- Wraps provided fn in pcall, catches the error and prints it. If second variable is a function then executes it when not status
function wrap(fn, fn_error, ...)
	local results = table.pack(pcall(fn, ...))
	local status = results[1]
	if status then -- return all values except the first one (which is the success flag)
        return table.unpack(results, 2, results.n)
	else
		if type(fn_error) == "function" then fn_error(results[2], ...) end
		print(tostring(results[2])) -- print the error message
    end
end

-- Wraps provided fn in pcall, doesn't print the error
function wrapSilent(fn, fn_error, ...)
	local results = table.pack(pcall(fn, ...))
	if results[1] then
        return table.unpack(results, 2, results.n) -- return all values except the first one (which is the success flag)
    else
		if type(fn_error) == "function" then fn_error(results[2], ...) end
	end
end

-- Wraps provided fn in pcall, catches the error and prints it with user defined string
function wrapVerbose(fn, extra_str, ...)
	local results = table.pack(pcall(fn, ...))
	local status = results[1]
	
	-- return all values except the first one (which is the success flag)
	if status then
        return table.unpack(results, 2, results.n)
    
	-- return false and the error message
	else
        local print_str = extra_str and tostring(extra_str) or ""
		print_str = print_str.." Error message: "..tostring(results[2])
		print(print_str)
    end
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

-- Concatenate two tables
function tableConcat(t1, t2)
    for i=1, tableLength(t2) do
        t1[tableLength(t1) + 1] = t2[i]
    end
    return t1
end

-- Merge two tables (second overwrites first with duplicate keys)
function tableMerge(t1, t2)
    for key, value in pairs(t2) do
        t1[key] = value
    end
    return t1
end

-- Do a shallow copy of the object
function shallowCopy(obj)
	local copy = obj
	if type(obj) == "table" then
		copy = {}
		for key, value in pairs(obj) do
			copy[key] = value
		end
	end
	return copy
end

-- Clip variable between two values
function clip(var, low, high)
	if not low then low = -infinity end
	if not high then high = infinity end
	if low and (var < low) then var = low end
	if high and (var > high) then var = high end
	return var
end

-- Strip given pattern from the string
function strip_string(str, pattern)
	return string.gsub(str, pattern, "")
end

-- LUA can't handle no break space symbols
function strip_nobreakspace(s)
	return strip_string(value, "\194\160") -- LUA's no break space: "\194\160"
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

-- Split string in a robust way and return a table
function split_string(inputstr, sep)
	local t = {} -- output table
	local str_len = string.len(inputstr) -- length of the string
	if str_len == 0 then return t end
	
	-- Iterate over all characters
	local outputstr = "" -- string for adding characters in one element
	for i=1, (str_len + 1)  do
		local char = string.sub(inputstr, i, i) -- read single character
		
		if (i == (str_len + 1)) or (char == sep) then -- end of string or separator, skip character and save outputstr to table
			table.insert(t, outputstr)
			outputstr = "" -- reset field value string
		
		else -- ordinary character, add to outputstr
			outputstr = outputstr .. char
		end
	end
	
	return t
end

-- Split string in a csv file in a robust way and return a table
function split_string_csv(inputstr, sep)
	local t = {} -- output table
	
	local is_string = false -- boolean to write string field into one element in table. If this is true then ignores separators
	local outputstr = "" -- string for adding characters in one element
	
	local str_len = string.len(inputstr) -- length of the string
	if str_len == 0 then return t end
	
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

-- Get all matches of the pattern in the string and return the results in a table
-- It doesn't check the same character twice, so the matches don't overlap in the string.
function gather_matches(str, pattern)
	local match_table = {}
	for result in string.gmatch(str, pattern) do
		table.insert(match_table, result)
	end
	return match_table
end

-- Get all matches of the pattern in the string and return the results in a table
-- It doesn't check the same character twice, so the matches don't overlap in the string.
-- This function expects a pattern that extracts two values
function gather_matches_2(str, pattern)
	local match_table = {}
	for result in string.gmatch(str, pattern) do
		table.insert(match_table, result)
	end
	return match_table
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


-- Test whether files have extension (e.g. ".txt") and remove it
function remove_filename_extension(filename)
	if not filename then return end

	local end_pattern = "^.+(%.[%a%d]-)$" -- string start, any characters (1 or more), [extracted] ., [extracted] alphanumeric characters (0 or more but min amount), string end
	local file_ext = string.match(filename, end_pattern)
	local has_file_end = (file_ext ~= nil)
	if has_file_end then filename = string.gsub(filename, file_ext, "") end -- remove file end
	
	return filename
end



-- Sort the filenames given in Spectra_info*.csv. There might be the index of the first spectrum in the filename, 
-- e.g. one file is "abc.txt", other is "def_0001_x.txt" (contains 200 spectra), third is "def_0201_x.txt".
-- Ordinary sort gives 0,1,100,1001,1002,2,3,871,99... (sorts string).
-- This sort gives 0,1,2,3,99,100,101,871,1001,1002 (sorts number).
-- The function assumes that you get the full filename like "abc.txt" or "abc_cd,e_f_127.txt" but ".txt" can be omitted
function sort_spectra_info_filenames(filename1,filename2)
	db("sort_spectra_info_filenames", 5)
	
	-- Test whether files have extension (e.g. ".txt") and remove it
	filename1 = remove_filename_extension(filename1)
	filename2 = remove_filename_extension(filename2) -- 2nd file might have different extension, remove it too
	
	-- Get the filename format in order to extract index from these
	local id_start1, index1, id_end1 = extract_file_identifier(filename1)
	local nr_of_digits1 = index1 and string.len(index1) or nil
	local id_start2, index2, id_end2 = extract_file_identifier(filename2)
	local nr_of_digits2 = index2 and string.len(index2) or nil
	--print(filename1, id_start1, index1, id_end1)
	--print(filename2, id_start2, index2, id_end2)
	
	-- Errors in matching the filename pattern (no match)
	if (not id_start1) or (not index1) or (not id_end1) or
		(not id_start2) or (not index2) or (not id_end2) 
	then
		--printe("sort_spectra_info_filenames() | 1st filename doesn't match pattern, filename: " .. filename1) -- is reported in extract_file_identifier()
		return
	end
	
	-- The filenames are formatted correctly and there was a match
	
	-- Both filenames match and have (different) indices
	if (id_start1 == id_start2) and (id_end1 == id_end2) and (nr_of_digits1 > 0) and (nr_of_digits2 > 0) then
		-- Convert to number to get rid of leading zeroes, no extracted digits is assumed to be 1
		local filename1_nr = tonumber(index1) or 1
		local filename2_nr = tonumber(index2) or 1
		
		-- Sort according to index digits
		return filename1_nr < filename2_nr
	end
	
	
	-- There's a situation where one filename is direct match (e.g. only one spectrum in series) and other is with _ and index.
	-- Usually last digits of the identifier show crater/point number or such (makes sense to sort), e.g. "abc_P1_001.txt" and "abc_P10.txt"
	-- Remove index and check if there are digits at the end of the identifier and sort by those or otherwise sort filenames directly
	
	
	-- If name contains index and index is preceeded by _ then remove it for comparison
	local clean_id_start1 = id_start1
	local clean_id_start2 = id_start2
	if (nr_of_digits1 > 0) then
		local last_char = string.sub(id_start1, -1)
		if last_char == "_" then clean_id_start1 = string.sub(id_start1, 1, -2) end
	end
	if nr_of_digits2 and (nr_of_digits2 > 0) then
		local last_char = string.sub(id_start2, -1)
		if last_char == "_" then clean_id_start2 = string.sub(id_start2, 1, -2) end
	end
	local name1 = clean_id_start1..id_end1
	local name2 = clean_id_start2..id_end2
	
	-- Check for digits at the end of the filenames
	local pattern_end_digits = "^(.-)(%d*)$" -- str start, any characters (0 or more), [extracted] digits (0 or more), str end
	local root1, digits1 = string.match(name1, pattern_end_digits)
	local root2, digits2 = string.match(name2, pattern_end_digits)
	
	-- The filenames match and only last digits in the identifier are different, sort by those digits
	if root1 and (root1 == root2) then
		-- Convert to number to get rid of leading zeroes, no extracted digits is assumed to be 1
		local digits1_nr = tonumber(digits1) or 1
		local digits2_nr = tonumber(digits2) or 1
		
		-- Sort according to identifier last digits
		return digits1_nr < digits2_nr
	end
	
	
	-- If filename patterns don't match and/or there's no index then sort filenames directly
	return filename1 < filename2
end


-- Extract the identifier (two parts) from the filename in Spectra_info*.csv, 
-- so that experiment index can be extracted from the filename later.
-- The filename must contain index 1 preceded by zeros to match the first spectrum filename in the series.
-- if is_complex_filename then the index must be preceded by _.
function extract_file_identifier(filename)
	db("extract_file_identifier", 6)
	
	-- Reset the global variables
	filename_identifier_start = nil
	filename_identifier_end = nil
	filename_index_digits_nr = nil
	filename_identifier_start_clean = nil
	
	-- remove the extension (e.g. ".txt")
	filename = remove_filename_extension(filename)
	
	-- Extract the filename format
	local id_start, index, id_end
	if is_complex_filename then -- complex filename mode
		-- This part is tricky and messy. The filenames contain _001 or _0001 (hopefully not 2 digits ever) as the index.
		-- However, the indices might be at the end of the file (before extension) or in the middle of the filename.
		-- This means that the identifier contains two parts: beginning and end (potentially empty string).
		-- Unfortunately, the identifier contains _ characters, could contain special characters for LUA, 
		-- and can contain part of the filename also in _0001 format (experimental data like delay time).
		-- Only semi-foolproof way I see to solve this is if the user supplies file names in spectra info
		-- with the first index (e.g. abc_00001 or abc_0001 or abc_001 instead of abc_). 
		-- I'm assuming the index never has 2 digits because it would be very prone to (logical) errors.
		
		-- TODO: what if files are abc_0001_x.txt and abc_0201_x.txt (second file contains spectra starting from index 201)?
		-- TODO: check if filename contains _0001 multiple times, currently last one is chosen as the index
		-- TODO: fix situation when filename contains _0001 multiple times but index isn't the last one
		
		
		-- check if there's _000001 pattern
		local pattern = "^(.+_)(000001)(.*)$" -- str start, [extracted] any characters (1 or more) and _, [extracted] index, [extracted] any characters (0 or more), str end
		id_start, index, id_end = extract_pattern_from_filename(filename, pattern)
		
		-- check if there's _00001 pattern
		if (not id_start) then
			pattern = "^(.+_)(00001)(.*)$" -- str start, [extracted] any characters (1 or more) and _, [extracted] index, [extracted] any characters (0 or more), str end
			id_start, index, id_end = extract_pattern_from_filename(filename, pattern)
		end
		
		-- check if there's _0001 pattern
		if (not id_start) then
			pattern = "^(.+_)(0001)(.*)$" -- str start, [extracted] any characters (1 or more) and _, [extracted] index, [extracted] any characters (0 or more), str end
			id_start, index, id_end = extract_pattern_from_filename(filename, pattern)
		end
		
		-- check if there's _001 pattern
		if (not id_start) then
			pattern = "^(.+_)(001)(.*)$" -- str start, [extracted] any characters (1 or more) and _, [extracted] index, [extracted] any characters (0 or more), str end
			id_start, index, id_end = extract_pattern_from_filename(filename, pattern)
		end
		
		-- Assumes that the filename doesn't contain an index and is a direct match
		if (not id_start) then
			id_start = filename
			index = ""
			id_end = ""
		end
	
	else -- simple filename mode, index is at the end of the filename
		local pattern = "^(.-)(%d*)$" -- str start, any characters (0 or more), [extracted] digits (0 or more), str end
		id_start, index = string.match(filename, pattern)
		id_end = ""
		
		-- Make sure it's the index (index 1), not a part of the identifier
		local length = string.len(index) -- at least 3 digits (001 or 0001)
		local nr = tonumber(index) -- index 1 (001, not 002)
		if (length < 3) or (nr ~= 1) then -- not the index, filename is the direct match
			index = ""
			id_start = filename
		end
	end
	
	-- Error in matching the filename pattern (no match)
	if (not id_start) or (not index) or (not id_end) then
		printe("extract_file_identifier() | filename doesn't match pattern, complex filename mode: " ..tostring(is_complex_filename).. ", filename: " ..filename)
		return nil, nil, nil
	end
	
	-- Output the values into global variables
	filename_identifier_start = id_start
	filename_identifier_end = id_end
	
	-- get number of digits of the filename index
	filename_index_digits_nr = string.len(index)
	
	-- Remove _ if it's the last character in filename_identifier_start
	filename_identifier_start_clean = id_start
	local last_char = string.sub(id_start, -1)
	if (last_char == "_") and filename_index_digits_nr and (filename_index_digits_nr > 0) then filename_identifier_start_clean = string.sub(id_start, 1, -2) end
	
	return id_start, index, id_end
end


-- Extracts filename pattern. If there isn't a match then returns nil-s instead.
function extract_pattern_from_filename(filename, pattern)
	db("extract_pattern_from_filename", 6)
	
	local id_start, index, id_end = string.match(filename, pattern)
	if id_start and index and id_end then
		return id_start, index, id_end
	end
	return nil,nil,nil
end


-- Compile filename search pattern for the series
function compile_filename_pattern(start_id, index_nr, end_id, extension)
	local pattern = compile_filename_pattern_open(start_id, index_nr, end_id)
	
	-- Add file extension
	if extension then
		local safe_extension = get_safe_pattern_string(extension)
		pattern = pattern .. safe_extension
	end
	
	-- Finalize the pattern (string end)
	pattern = pattern .. "$"
	return pattern
end

-- Compile corrected filename search pattern for the series without the extension and file end
function compile_filename_pattern_open(start_id, index_nr, end_id)
	start_id = start_id or filename_identifier_start
	index_nr = index_nr or filename_index_digits_nr
	end_id = end_id or filename_identifier_end
	
	-- Escape special LUA characters
	local safe_start = get_safe_pattern_string(start_id)
	local safe_end = get_safe_pattern_string(end_id)
	
	-- Get filename pattern
	local pattern
	if index_nr and (index_nr > 0) then -- index exists
		local digits_str = string.rep("%d", index_nr)
		pattern = "^" ..safe_start.. "(" ..digits_str.. ")" ..safe_end -- extract digits
	else -- no index
		pattern = "^" ..safe_start..safe_end
	end
	
	return pattern
end

-- Compile the pattern for a corrected spectra filename (e.g. "^abc_def_1-50.txt$" when original first was "^abc_0001_def.txt$")
-- Extracts two items: start spectrum idx and end spectrum idx of the file
function compile_corrected_filename_pattern(start_id_clean, end_id)
	local identifier = compile_corrected_series_id(start_id_clean, end_id)
	local safe_identifier = get_safe_pattern_string(identifier)
	local safe_extension = get_safe_pattern_string(file_end) -- escape special characters like - and +
	
	-- Compile pattern
	local pattern = "^"..safe_identifier -- filename pattern without index, extension and string end
	pattern = pattern .. "_(%d+)%-(%d+)" -- add corrected spectra indices range, same input as data correction output, [extracted] digits (greedy 1 or more), -, [extracted] digits (greedy 1 or more)
	pattern = pattern .. safe_extension .. "$" -- add extension and finalize pattern
	
	return pattern
end

-- Compile the indentifier of a corrected file's name
function compile_corrected_series_id(start_id_clean, end_id)
	start_id_clean = start_id_clean or filename_identifier_start_clean
	end_id = end_id or filename_identifier_end
	local identifier = start_id_clean..end_id
	return identifier
end

-- Search a folder for files that match the provided pattern, if no pattern then return all files
function match_files(path, sort_fn, patterns_or, patterns_and)
	
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
		if patterns_and and (type(patterns_or) == "table") then
			for i,pattern in pairs(patterns_and) do
				bool = bool and string.match(filename, pattern)
			end
		elseif patterns_and then
			bool = bool and string.match(filename, patterns_and)
		end
		
		if bool then 
			table.insert(files, filename)
		end
	end
	
	table.sort(files, sort_fn) -- Sort filenames in ascending order for shot to correlate with file number
	
	return files
end


-- Sort the filenames given in Input_data_corrected folder. E.g. "idStart_idEnd201-250.txt" contains 50 spectra.
-- Ordinary sort gives 0,1,100,1001,1002,2,3,871,99... (sorts string).
-- This sort gives 0,1,2,3,99,100,101,871,1001,1002 (sorts number).
-- The function assumes that you get the full filename like "abc_1-201.txt" or "abc_cd,e_f_127_1-201.txt" but ".txt" can be omitted
-- Only sorts according to first number in corrected files
function sort_corr_filenames_fn(filename1,filename2)
	db("sort_corr_filenames_fn", 5)
	
	-- Identifiers weren't found
	if (not filename_identifier_start_clean) or (not filename_identifier_end) then
		printe("sort_corr_filenames_fn() | Identifiers are nil, start: " ..tostring(filename_identifier_start_clean).. ", end: " ..tostring(filename_identifier_end))
		return
	end
	
	-- Test whether files have extension (e.g. ".txt") and remove it
	--filename1 = remove_filename_extension(filename1)
	--filename2 = remove_filename_extension(filename2) -- 2nd file might have different extension, remove it too
	
	-- Get the pattern and match both filenames
	local pattern = compile_corrected_filename_pattern(filename_identifier_start_clean, filename_identifier_end)
	local f1_digits1, f1_digits2 = string.match(filename1, pattern)
	local f2_digits1, f2_digits2 = string.match(filename2, pattern)
	
	-- Match wasn't found (unexpected)
	if (not f1_digits1) or (not f1_digits2) then
		printe("sort_corr_filenames_fn() | Filename 1 didn't match pattern. Filename: " ..tostring(filename1).. ", pattern: " ..tostring(pattern))
		return
	elseif (not f2_digits1) or (not f2_digits2) then
		printe("sort_corr_filenames_fn() | Filename 2 didn't match pattern. Filename: " ..tostring(filename2).. ", pattern: " ..tostring(pattern))
		return
	end
	
	-- Convert to number to get rid of leading zeroes, no extracted digits is assumed to be 1
	local filename1_nr = tonumber(f1_digits1) or 1
	local filename2_nr = tonumber(f2_digits1) or 1
	
	-- Sort according to first spectrum index
	return filename1_nr < filename2_nr 
end


-- Sort gives 0,1,100,1001,1002,2,3,871,99... This sort gives 0,1,2,3,99,100,101,871,1001,1002
-- The function assumes that you get the full filename like "abc.txt" or "abc_cd,e_f_127.txt" but ".txt" can be omitted
function sort_numerical_filenames_fn(filename1,filename2)
	db("sort_numerical_filenames_fn", 5)
	
	-- Test whether files have extension (e.g. ".txt") and remove it
	filename1 = remove_filename_extension(filename1)
	filename2 = remove_filename_extension(filename2) -- 2nd file might have different extension, remove it too
	
	-- Get the filename format in order to extract index from these
	local nr_of_digits = filename_index_digits_nr
	-- The code shouldn't get this far if any of the global variables is nil
	
	-- There is no index, sort filenames directly
	if nr_of_digits <= 0 then
		return filename1 < filename2
	end
	
	-- Create the search pattern and check if the filenames follow the same pattern
	local pattern = compile_filename_pattern()
	local index1 = string.match(filename1, pattern) -- nil if no match
	local index2 = string.match(filename2, pattern) -- nil if no match
	
	-- If filename patterns don't match then sort filenames directly
	if (not index1) or (not index2) then
		return filename1 < filename2
	end
	
	-- Convert to number to get rid of leading zeroes, no extracted digits is assumed to be 1
	local filename1_nr = tonumber(index1) or 1
	local filename2_nr = tonumber(index2) or 1
	
	-- Sort according to index digits
	return filename1_nr < filename2_nr
end

-- Chcecks lazily if the table is empty
function is_table_empty(tbl)
	for key, val in pairs(tbl) do
		return false
	end
	return true
end


-- Prints every key and value of table
function printTableShallow(tbl)
	if type(tbl) == "table" then
		for key, value in pairs(tbl) do
			if type(key) == "string" then key = "'"..key.."'"end
			if type(value) == "string" then value = "'"..value.."'"end
			print("Key: " .. tostring(key) .. " ; Value: " .. tostring(value))
		end
	else
		print(tostring(tbl))
	end
end

-- Make entire table into string recursively, not the prettiest formatting
function strTableDirty(tbl)
	if type(tbl) == 'table' then
		local s = '{ '
		for k,v in pairs(tbl) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. strTable(v) .. ','
		end
		return s .. '} '
	else
		return tostring(tbl)
	end
end

-- Make entire table into string recursively. Modified from https://gist.github.com/dpino/af37d70554d157bbee289f489945cce5 (print_r.lua)
function strTable(tbl, indent_start, indent_original, indent_addition)
	indent_start = indent_start or ""
	indent_original = indent_original or "    "
	indent_addition = indent_addition or indent_original
	
	local function sub_strTable(tbl, indent)
		local level_str = ""
		
		if (type(tbl) == "table") then
			for pos, val in pairs(tbl) do
				if (type(pos) == "string") then
					pos = "'"..tostring(pos).."'"
				end
				
				if (type(val) == "table") then
					if is_table_empty(val) then
						level_str = level_str..indent.."["..pos.."] = {}"
					else
						level_str = level_str..indent.."["..pos.."] = {"
						level_str = level_str..sub_strTable(val, indent..indent_addition)
						level_str = level_str..indent.."}"
					end
				
				elseif (type(val) == "string") then
					level_str = level_str..indent.."["..pos.."] = '"..val.."'"
				else
					level_str = level_str..indent.."["..pos.."] = "..tostring(val)
				end
			end
		else
			level_str = level_str..indent..tostring(tbl)
		end
		
		return level_str
	end
	
	-- It's table, start recursion
	local str = ""
	if (type(tbl) == "table") then
		str = str.."{"
		str = str..sub_strTable(tbl, indent_start..indent_original, str)
		str = str..indent_start.."}"
	else
		str = tostring(tbl)
	end
	
	return str
end

-- Make entire table into string recursively in a flat format
function strTableFlat(tbl)
	return strTable(tbl, "", " ", "")
end

-- Print entire table contents
function printTable(tbl)
	print(strTable(tbl, "\n", "    "))
end

-- Print entire table contents in the most compact way
function printTableFlat(tbl)
	print(strTableFlat(tbl))
end


-- Print error log (usually uncertain data)
--last_error_msg = nil -- Check previous error message, so that there wouldn't be 100 identical errors in a row.
function printe(str, priority)
	priority = priority or -1 -- by default, print errors even when debugging isn't on

	--if str ~= last_error_msg then -- print only if it's a new error
		db("ERROR: " .. str, priority)
		--last_error_msg = str
	--end
end

-- Check if file exists. Returns false for a directory
function file_exists(filepath)
	local f=io.open(filepath,"r")
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
