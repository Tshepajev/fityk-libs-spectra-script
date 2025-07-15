-- Last update is for script v4.2

-- This is the configuration file for analyze_and_plot.lua script for Fityk.
-- It's a separate LUA script that will read as global constants defined by user.
-- It's advisable to save the file with the output for reproducibility.


-- User constants (global constants)
-- Constants, change them! The constants need to be global for Fityk to access them because it seems that Fityk runs the script
-- line by line. After every line Fityk forgets local LUA variables so they can't be passed to functions.
-- All values are by default in SI.

----------------------------------------------------------------------
-- Path and file settings
----------------------------------------------------------------------

-- What are system paths for input and output folder?
-- Fityk really doesn't like special characters anywhere.
-- Leave / or \ at the end of the string, so that a filename can be concatenated directly.
-- Windows path can be both with \ or /. However, \ is special in LUA strings, so it needs to be \\.
input_path = work_folder .. "Input_data/" -- input data (spectra and background files) needs to be here
output_path = work_folder .. "Output/" -- output files (line parameters, images and sessions) are saved here
corrected_path = work_folder .. "Input_data_corrected/" -- Corrected spectra are saved here 
sessions_path = output_path .. "Sessions/" -- sessions after fitting are saved here

-- _SCRIPT_DIR_ return string for where the script was executed -- doesn't work

-- Change this if you want to use multiple instances of Fityk calculating
-- simultaneously using different inputs / different ranges. 
-- MAKE SURE THERE AREN'T ERRORS IN THE INPUT DATA
-- 80 % of errors are because of bad input files, 15 % from bad variables in these settings


output_data_name = "Fityk_output"
output_data_end = ".csv"


-- Filename for stopscript. If this file isn't empty then code stops loop after
-- processing current experiment and outputting data.
stopscript_name = "Stopscript.txt"


-- What type of data files do you want to input? If eg .asc is already in info file filenames then write "".
-- Regex will use this in search and will consider . symbol. Don't use other special regex symbols!
file_end = ".txt"


-- When importing text into spreadsheet filename (e.g. 13.5) may be 
-- read as a float. Using different separator (e.g. 13,5) avoids losing
-- "decimal" zeros from the end of the value
separator = ","


-- What separator does the input data use
input_data_separator = ";"


-- What character is considered start and end of a string in csv file? E.g. 1, 2, "3,4", 5 would have 4 elements and the third one would be 3,4
csv_string_char = "\"" -- " as string in csv file


-- Filename without the file extension of noise standard deviations file
noise_stdevs_file = "_Noise_stdevs"

--[[
This variable is used to check how to extract the experiment series identifier from a filename.
It also determines how you must input the filename in Spectra_info*.csv.
If you're using JET LIBS spectra (2024) then this must be set to true, if not then it's optional.

Note that in Spectra_info*.csv you have to either provide a direct match of the filename OR 
you have to provide the entire filename, where the index is 1, preceded by zeros, so it matches the actual 
filename containing the first spectrum of the series (e.g. if index always has 3 digits then the index must be "001"). 
That filename represents the entire experimental series, so index can change but identifier is locked in place.
This could be "abc0001" or "abc_0001_def" (second one must have _ before the index).
You can but don't have to add an extension (e.g. ".txt"), it gets ignored.

You are expected to input files with the index in them clearly separated. 
E.g. if the index is "001" and the filename is "abc_point2001.txt" then "001" gets extracted properly, 
but if the index is "001" and the filename is "abc_point10001.txt" then "0001" would get extracted (wrong and causes errors).
Ideally you have named the files better during experiments, e.g. "abc_point10_001.txt". There's only so much that the code can reliably do.

If you always have spectrum index at the end of the filename before extension (e.g. "abc255.txt") 
then leave is_complex_filename to false and put "abc001" in Spectra_info*.csv (faster, more foolproof). 

If you might have (but can be at the end) spectrum index in the middle of the filename (e.g. "abc_0255_def_2500_x.txt" with 0255 being index),
then change is_complex_filename to true and put the filename of the first spectrum "abc_0001_def_2500_x" in Spectra_info*.csv.
The index must be 1 and must be preceded by zeros, so it matches the actual filename containing the first spectrum, 
and the index digits must be preceded by _ (different from is_complex_filename = false).
is_complex_filename = true isn't as foolproof, since the filename might contain experimental 
parameters e.g. "abc_delay_001ms.txt", which doesn't contain an index but is a direct filename match.
The algorithm checks for "00001", then "0001" etc. (min 3 digits), until a match is found. If the filename has two matches (error?) then
the last one is chosen as the index location.

If you don't have an index in the filename (e.g. series consists of only one experiment or that one file contains all 
spectra of the series), then just put the filename in Spectra_info*.csv. If you only have filenames without indices then 
is_complex_filename doesn't matter.
--]]
is_complex_filename = false


----------------------------------------------------------------------
-- Input settings
----------------------------------------------------------------------

-- Whether to transform all values in line_positions according to transform_line_positions()?
transform = false
-- How to transform all values in line_positions?
function transform_line_positions(lines_info_filename)
	for idx, value in ipairs(lines_info[lines_info_filename]["Wavelength (m)"]) do
		-- Write your equation here!
		lines_info[lines_info_filename]["Wavelength (m)"][idx] = 1.000059269 * value - 103.47891858
	end
end


----------------------------------------------------------------------
-- Processing settings
----------------------------------------------------------------------

-- These are the bounds for experiments for every file. Minimum is 1 and maximum the nr of experiments in series. These are clipped automatically (also when nil).
start_experiment_nr = nil
end_experiment_nr = nil


-- Where does the spectra actually start and end? Cuts away the edges (wavelength in meters).The spectra is cut after modifying x-values.
-- nil takes first and last pixel as those values (not cutting)
cut_start = 300e-9
cut_end = 760e-9


-- Pixels between these values (in original measured units (e.g. pixels) if noise_before_sensitivity_correction == true or corrected units (wavelengths) otherwise) 
-- are viewed as noise to calculate minimum line area detection threshold (stdev of those pixel intensities). Don't forget x-axis correction!
-- If either is nil then the start is -infinity or end is +infinity
-- If both are nil then noise is assumed to be 0 and lines aren't excluded when they are noise level.
-- Constant fitting window is determined by these.
noise_estimate_start = 560e-9
noise_estimate_end = 640e-9


-- Whether to estimate noise level before or after sensitivity and x-axis correction. Constant fitting window is determined by this.
noise_before_sensitivity_correction = false 


-- This many spectra in one file are averaged pixel-wise before continuing. It's like a moving average on spectra in a file. 
-- The spectrum in question is the center of the moving average and 2*radius + 1 is the diameter. 
-- The radius has to be small enough to fit the moving window into two process_nr_spectra batches, that is max floor(process_nr_spectra / 2). 
moving_average_experiment_radius = 0


-- For debugging and finding lines from noise. This radius (in pixels) will be averaged to get the spectrum.
moving_average_pixels_radius = 0

-- This radius (in files) will be averaged for every experiment (average of same experiment nr) and pixel (average of same pixel) to get the spectrum.
--moving_average_file_radius = 0


-- How many spectra from a series are held in memory simultaneously? This is important when input files have many experiments and/or 
-- each experiment has many pixels. E.g. for 40 000 px per experiment batch process_nr_spectra of 30-60 is good.
process_nr_spectra = 50


-- This table has gain functions to convert from written gain value to actual y-axis correction.
-- "Camera pre amplification" column in Spectra_info*.csv in input info contains the keys for this table.
-- The keys must be numbers
gain_functions = {
	[1] = function(gain)
		-- Write your function here!
		return 1.120270358187 * math.exp(0.0019597049 * gain) 
	end,
	[2] = function(gain) 
		-- Write your function here!
		if (gain < 1500) then
			return 2.116662 * math.exp(0.001938 * gain)
		elseif (gain < 3000) then
			return 3.404075 * math.exp(0.001684 * gain)
		else
			return 6.357094 * math.exp(0.001471 * gain)
		end
	end
}


-----------------------
-- Lines
-----------------------

-- If this is true then lines that are not on active points will be forced as 0-height (disabled). While it's possible to create 
-- and fit lines outside of the dataset, doing it too far from an active point will cause a crash. The distance seems to be
-- related to the line influence range (Fityk's internal parameter, not the one used by me) but I can't quantify it. 
-- Therefore, it's best not to fit lines outside of the dataset unless you know what you're doing.
forbid_lines_outside_range = true


-- The apparatus function of the system when using VoigtApparatus curve. This is the FWHM of Gaussian (GaussianFWHM of apparatus fn)
apparatus_fn_fwhm = 0.044e-9

-- The function format is useful if e.g. apparatus function changes throughout the spectrum. Currently used only by min_FWHM_function().
-- If it's constant then just return a constant value or variable instead of the equation.
apparatus_function_fwhm = function(wavelength)
	-- Write your function here!
	return 1.142857E-04 * wavelength + 1.428571E-12
end

-- What is the minimal line gwidth? This will be Voigt or Gaussian/Lorentzian functions' lower bound.
--minimal_gwidth = 5e-12 -- approx 5 px pparatus fn, this is at shape = 10
 
-- What is the minimal line width at half maximum? This will be Voigt or Gaussian/Lorentzian functions' lower bound.
--min_FWHM = apparatus_fn_fwhm -- approx 3 px apparatus fn, this is at shape = 10 

-- What is the minimal line width at half maximum? This will be Voigt or Gaussian/Lorentzian functions' lower bound.
-- The function format is useful if min_FWHM (e.g. apparatus function) changes throughout the spectrum.
-- If it's constant then just return a constant value or variable instead of the equation.
min_FWHM_function = function(wavelength)
	-- Write your function here!
	return apparatus_function_fwhm(wavelength)
end


-- Estimate for how wide a line can be to still influence the fitting of other points considerably. 
-- This is used to lock/unlock lines when processing only a part of the spectrum at a time.
-- It should be as small as possible to avoid long fitting times
-- Minimal real influence is 4 * FWHM for the Lorentzian (height is 1-2% of max) but also depends on nearby lines.
-- If a nearby line is of same width then real influence would be 8 * FWHM.
-- If a nearby line is wider then the influence radius should be wider respectively, to contain the center of the other line.
default_max_line_influence_radius = 1e-9 -- 1 nm


-- What percentile of active data (intensities) is considered as the higher bound for constants? This applies currently only for
-- local constants, since global constant is bound by minimal data value. Having this lower than 50 % is beneficial when there are
-- un-fitted lines and the constant would be fitted higher than necessary to account for the lines. 
high_constant_bound_percentile = 50 -- 50 by default


-- The upper bound for shape when using Voigt functions. Having it too high causes potential problems
-- because Voigt can use shape and gwidth interchangeably. If using VoigtFWHM then this must be lower than
-- the interpolated shapes for polynomial approximation (20 currently)
max_Voigt_shape = 15


-- Bound for Voight shape
min_Voigt_shape = 1e-12 -- shape is almost 0 but not quite for FWHM-gwidth conversions


-- Whether to write all lines at or near noise level as 0-height in output files? Doing makes it easier to 
-- distinguish sketchy lines in later data analysis, but this also loses some information. 
-- If this is true then it applies also for nullify_weak_lines_visual.
nullify_weak_lines_data = true

-- Whether to write all lines at or near noise level as 0-height for output images and sessions? Doing makes 
-- the plots and sessions more clean and clear, but this also loses some information.
nullify_weak_lines_visual = false

-- The line has to have at least this many times higher amplitude or area than the noise or it will be turned into dummy.
-- Very low amplitude but wide line can still have large area and be easily fitted through the noise.
-- Line is turned into dummy only if both parameters are worse than noise.
-- Area noise estimate takes the global noise or local constant and calculates the area of rectangle with min_FWHM_function() width. 
-- Usually the lines are considerably thicker than min_FWHM_function() width.
detection_sn_ratio_height = 3
detection_sn_ratio_area = 4


-----------------------
-- Unused
-----------------------

-- What percentile of active data minus the minimal active data is considered as the lowest line height. 
-- If line height is lower than centile(x,y) - min(y) then it's considered non-existent
--height_percentile_of_existing_lines = 35


-- How much do you want to lower constant upper bound according to equations
-- max = minimal_data_value+(median_data_value-minimal_data_value)*lower_constant
-- and
-- constant_value = (max+min)/2+(max-min)/2*sin(~angle)
-- or do you just want Fityk to guess constant height between min and median values 
-- (if former then recommended range is [0,1], if latter then write lower_constant = false).
--lower_constant = 0.5


-- For calculation speed, approximately how many pixels are active for line fitting simultaneously
--fit_nr_pixels = 500


-- If using a line as Lorentzian (see use_as_Lorentzian) then what are it's gwidth bounds?
-- You can experiment with one Voigt line keeping FWHM constant if converting from normal
-- line gwidth
--min_Voigt_gwidth = 6e-12


-- The smallest area I determined for a detectable line
--detection_threshold_calibration = 1e-9


-- The standard deviation of noise for previous value
--noise_stdev_calibration = 5.47e6

-- the index of a pixel that is signal for sensitivity value finding
--non_noise_sensitivity_px = 500 

-- Polyline gets it's step locations from the edges of the local window with default_max_line_influence_radius 
-- size. However, when lines are close then polyline coordinates overlap and the polyline steps aren't 
-- centered around the lines. The step widths are divided with narrower_polyline_step.
--narrower_polyline_step = 3



----------------------------------------------------------------------
-- Output settings
----------------------------------------------------------------------

-- Whether to overwrite existing corrected spectra and skip fitting, only outputting corrected spectra
only_correct_spectra = false


-- Save the session after fitting in case there's bad fit
save_sessions = true


-- To plot or not to plot [true/false]?
plot = false

-- What are the plotting ranges? Use false or nil to use automatic ranges
-- Values are multiplier for padding with pixels. E.g. for 1000 px and x_min = 0.1 would mean padding of 100 px.
-- e.g. x_min = false x_max = 0.05 y_min = 0.1 y_max = false
pad_x_min = 0.15
pad_x_max = 0.1
pad_y_min = nil
pad_y_max = nil



----------------------------------------------------------------------
-- Debugging
----------------------------------------------------------------------

-- If this is true then it prints everywhere the location of the code to debug where the code ends up
-- because LUA/Fityk is incredibly useless in error locations here
-- Verbosity: -1 is disabled, 0 is most basic feedback, up to 5 which prints every debug message
debug_mode = -1

-- Whether to print each debug message (e.g. prints 15 lines of same message) or 
-- to print the message and print the message with the total number of times it was printed on the next line.
-- If it's true then prints 2 lines for every distinct consecutive message string (message, message (x number)), 
-- but doesn't finalize in case of crash, so the last message doesn't show how many times it was printed.
debug_print_message_summary = false


-- Do you want to stop for query for continuing after every file? [true/false]
stop_after_file = false


-- Whether to stop the script after data correction and before lines are added. [true/false]
stop_before_lines = false


-- Whether to stop the script after lines are created and before fitting. [true/false]
stop_before_fitting = false

-- Do you want to stop for query for continuing before every window fitting? [true/false]
stop_before_fit_window = false

-- Do you want to stop for query for continuing after every window fitting? [true/false]
stop_after_fit_window = false


-- Do you want to stop for query for continuing after every time lines are locked after fitting? [true/false]
stop_after_lock_lines = false