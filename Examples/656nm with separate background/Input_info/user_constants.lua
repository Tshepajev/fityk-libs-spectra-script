-- This is the configuration file for analyze_and_plot.lua script for Fityk.
-- It's a separate LUA script that will read as global constants defined by user.
-- It's advisable to save the file with the output for reproducibility.


-- User constants (global constants)
-- Constants, change them! The constants need to be global for Fityk to access them because it seems that Fityk runs the script
-- line by line. After every line Fityk forgets local LUA variables so they can't be passed to functions.

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


output_data_name = "Fityk_output"
output_data_end = ".csv"


-- Filename for stopscript. If this file isn't empty then code stops loop after
-- processing current experiment and outputting data.
stopscript_name = "Stopscript.txt"


-- What type of data files do you want to input? If eg .asc is already in info file filenames then write "".
-- Regex will use this in search and will consider . symbol. Don't use other special regex symbols!
file_end = ".asc"


-- When importing text into spreadsheet filename (e.g. 13.5) may be 
-- read as a float. Using different separator (e.g. 13,5) avoids losing
-- "decimal" zeros from the end of the value
separator = ","


-- What separator does the input data use
input_data_separator = ","


-- What character is considered start and end of a string in csv file? E.g. 1, 2, "3,4", 5 would have 4 elements and the third one would be 3,4
csv_string_char = "\"" -- " as string in csv file


-- Filename without the file extension of noise standard deviations file
noise_stdevs_file = "_Noise_stdevs"


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
cut_start = nil
cut_end = nil


-- Pixels between these values (in original measured units (e.g. pixels) if noise_before_sensitivity_correction == true or corrected units (wavelengths) otherwise) 
-- are viewed as noise to calculate minimum line area detection threshold (stdev of those pixel intensities). Don't forget x-axis correction!
-- If either is nil then the start is -infinity or end is +infinity
-- If both are nil then noise is assumed to be 0 and lines aren't excluded when they are noise level.
-- Constant fitting window is determined by these.
noise_estimate_start = 657.712e-9
noise_estimate_end = 657.9215e-9


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
-- each experiment has many pixels. E.g. for 40 000 px per experiment batch process_nr_spectra of 50-100 is good.
process_nr_spectra = 200


-- This table has gain functions to convert from written gain value to actual y-axis correction.
-- "Camera pre amplification" column in Spectra_info*.csv in input info contains the keys for this table.
-- The keys must be numbers
gain_functions = {
	[1] = function(gain) 
		-- Write your function here!
		if (gain < 1500) then
			return 2.116662 * math.exp(0.001938 * gain)
		elseif (gain < 3000) then
			return 3.404075 * math.exp(0.001684 * gain)
		else
			return 6.357094 * math.exp(0.001471 * gain)
		end
	end,
	
	[2] = function(gain) 
		-- Write your function here!
		
	end
}


-----------------------
-- Lines
-----------------------

-- if this is true then lines that are not on active points will be forced as 0-height (disabled).
forbid_lines_outside_range = true


-- The apparatus function of the system when using VoigtApparatus curve. This is the FWHM of Gaussian (GaussianFWHM of apparatus fn)
apparatus_fn_fwhm = 0.0467081e-9


-- What is the minimal line gwidth? This will be Voigt or Gaussian/Lorentzian functions' lower bound.
--minimal_gwidth = 5e-12 -- approx 5 px pparatus fn, this is at shape = 10 
-- What is the minimal line width at half maximum? This will be Voigt or Gaussian/Lorentzian functions' lower bound.
min_FWHM = apparatus_fn_fwhm -- approx 3 px apparatus fn, this is at shape = 10 


-- Estimate for how wide a line can be to still influence the fitting of other points considerably. 
-- This is used to lock/unlock lines when processing only a part of the spectrum at a time.
max_line_influence_diameter = 1.5e-9 -- H line influence 0.75e-9 m


-- What percentile of active data (intensities) is considered as the higher bound for constant?
high_constant_bound_percentile = 10 -- 50 by default


-- The upper bound for shape when using Voigt functions. Having it too high causes potential problems
-- because Voigt can use shape and gwidth interchangeably. If using VoigtFWHM then this must be lower than
-- the interpolated shapes for polynomial approximation (20 currently)
max_Voigt_shape = 15


-- Bound for Voight shape
min_Voigt_shape = 1e-12 -- shape is almost 0 but not quite for FWHM-gwidth conversions


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

-- Polyline gets it's step locations from the edges of the local window with max_line_influence_diameter 
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
plot = true

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


-- Do you want to stop for query for continuing after every file? [true/false]
stop = false


-- Whether to stop the script before lines are added.
stop_before_lines = false
