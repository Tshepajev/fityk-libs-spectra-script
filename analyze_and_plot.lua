-- Lua script for Fityk GUI version.
-- Script version: 1.9
-- Author: Jasper Ristkok
-- GitHub: https://github.com/Tshepajev/fityk-libs-spectra-script

--[[
Written for use with LIBS (atomic) spectra gained from SOLIS software
with Andor iStar340T ICCD camera.
The script could possibly be used for other applications but some
adjustments to the code might be needed. Note that the script is
written for Fityk default settings (Fityk v 1.3.1).
There are comments to simplify understanding the code but
I assume assume that you have read the Fityk manual 
(http://fityk.nieto.pl/fityk-manual.html).

In Fityk the dataset to be plotted needs to be selected, 
however, selecting dataset for plotting is a GUI feature and is unavailable 
for scripts. Still, @0 is selected by default. Plotting uses this feature.
In case you can't get images drawn the right way, try to click 
dataset @0  in the data tab(so that it highlighted).

However, plotting uses the appearance that you have in the GUI.
Therefore, if you want datapoints to be connected with lines
you have to check "line" box in the GUI. Also if you make 1 dataset and
add nr_of_lines functions, you can colour them. These colours will
remain the same on drawn images. In other words: make 1 dataset the
way you want it to look, click on the dataset @0 and then run the script.
]]


-- CHANGE CONSTANTS BELOW!
----------------------------------------------------------------------
-- Constants, change them!

-- What region to use? Pixels before start and after endpoint are left out
start=435
endpoint=1679

-- What are system paths for input and output folder?
-- Folders have to exist beforehand.
input_path="/Users/jasper/repos/fityk-libs-spectra-script/Examples/387nm_Mo_example/Input/"
output_path="/Users/jasper/repos/fityk-libs-spectra-script/Examples/387nm_Mo_example/"

-- Change this if you want to use multiple instances of Fityk calculating
-- simultaneously using different inputs / different ranges. 
-- MAKE SURE THERE AREN'T ERRORS IN THE INPUT DATA
-- (input columns: file nr;pre-amp;exposure time;nr of accumulations;gain;gate width;
-- additional multiplier)
input_info_name="Info.csv"
-- (input columns: file nr;sensitivity;additional multiplier)
input_sensitivity_name="Sensitivity.csv"
output_data_name="Output.txt"

-- Filename for stopscript. If this file isn't empty then code stops loop after
-- processing current experiment and outputting data.
stopscript_name="stopscript.txt"

-- What type of spectra files do you want to input?
file_end=".asc"

-- When importing text into spreadsheet filename (e.g. 13.5) may be 
-- read as a float. Using different separator (e.g. 13,5) avoids losing
-- "decimal" zeros from the end of the value
separator=","

-- To plot or not to plot [true/false]?
plot=true

-- What are the plotting ranges? Use false to use automatic ranges
-- e.g. x_min=false x_max=500 y_min=0.5 y_max=false
x_min=start-(endpoint-start)/10
x_max=endpoint+(endpoint-start)/10
y_min=false
y_max=false

-- If peak is considered wide then how wide is it? -- rudimentary
guess_initial_gwidth=25

-- Should the peaks be considered wide? -- rudimentary
wide=false

-- What is the minimal line gwidth? This will be Voigt functions' lower bound.
minimal_gwidth=0.5

-- Do you want to stop for query for continuing after every file? [true/false]
stop=false

-- How much do you want to lower constant's upper bound according to equations
-- max=minimal_data_value+(median_data_value-minimal_data_value)*lower_constant
-- and
-- constant_value=(max+min)/2+(max-min)/2*sin(~angle)
-- or do you just want Fityk to guess constant height between min and median values?
-- If former then recommended range is [0,1], if latter then write lower_constant=false.
lower_constant=0.1

-- How many spectra lines are there? Script checks this nr of elements in the next lists.
-- This means lists may be larger but not smaller than this.
nr_of_lines=8

-- Whether to transform all values in line_positions according to shift_line_positions()?
transform=true
-- How to transform all values in line_positions?
function shift_line_positions(line_pos)
    for i=1,#line_pos do
      -- Write your equation here!
      --e.g: line_pos[i]=(0.16*line_pos[i]+639)*60-38768
      line_pos[i]=line_pos[i]
    end
    return line_pos
end

-- If using a line as Lorentzian (see use_as_Lorentzian) then what are it's gwidth bounds?
-- You can experiment with one Voigt line keeping FWHM constant if converting from normal
-- line gwidth
min_Lorentz_gwidth=5e-7
max_Lorentz_gwidth=5e-5

-- What lines (index, same as following line_positions) to write effectively as Lorentz,
-- locking shape=1e6. Shape actually shouldn't be bound [0:1] but [0:infinity]. The 
-- problem is that since gwidth and shape aren't independent they get stuck in local 
-- minimas (gwidth=10.2,shape=1 fits as good as gwidth=0.014,shape=1000). However shape=1
-- is half-Gaussian, half-Lorentzian but shape=1000 is almost pure Lorentzian. If you
-- don't want to use it, write use_as_Lorentzian=false
use_as_Lorentzian=
{
  1,
  4
}

-- Where are spectra lines in pixels? (only the first nr_of_lines lines are used)
-- By convention in lua, the first index is 1 instead of 0
line_positions=
{
441,  --1
445,	--2
449,  --3
457,  --4
465,  --5
470,  --6
476,	--7
485,	--8
489,  --9
499  --10
}


-- How far can the peak shift? This will bind line to its location +/- radius 
-- defined here. Writing the value of the corresponding peak as -1 doesn't 
-- use script bounds (uses the Fityk's default 30% domain).
-- 0 locks the line in place
line_center_domains=
{
3,  --1
3,  --2
3,  --3
3,  --4
3,  --5
3,  --6
3,  --7
3,  --8
3,  --9
3  --10
}


-- Binds gwidths to given maximum gwidth. If corresponding gwidth
-- <=0 then doesn't bind line gwidth
max_line_gwidths=
{
4,  --1
4,  --2
4,  --3
4,  --4
4,  --5
4,  --6
4,  --7
4,  --8
4,  --9
4  --10
}
----------------------------------------------------------------------
-- CHANGE CONSTANTS ABOVE!


-- Global variable initializations
-- I know it's a bad habit... now, a year after starting with the code
first_filenr=nil
last_filenr=nil
pre_amps=nil
exposures=nil
acc_nrs=nil
gains=nil
widths=nil
file_multipliers=nil
spectra_multiplier=nil

minimal_data_value=nil
median_data_value=nil
center_error="-"
constant_error=nil
center_errors={}
gwidth_errors={}
shape_errors={}
height_errors={}
file_check=nil
experiment_check=nil
stopscript=false

----------------------------------------------------------------------
--Function declarations
------------------------------------------
-- Deletes all variables
function delete_variables()
  variables=F:all_variables()
  for i=#variables-1,0,-1 do
    F:execute("delete $"..variables[i].name)
  end
end
------------------------------------------
-- Deletes all functions for dataset
function delete_functions(dataset_i)
  functions=F:get_components(dataset_i)
  for function_index=#functions-1,0,-1 do
    F:execute("delete %"..functions[function_index].name)
  end
end
------------------------------------------
-- Deletes dataset with given index, does NOT delete variables
function delete_dataset(dataset_i)
  delete_functions(dataset_i)
  -- Deletes the dataset
  F:execute("delete @"..dataset_i)
end
------------------------------------------
-- Deletes all datasets, functions and variables for clean sheet
-- equivalent to F:execute("reset")
function delete_all()
  -- Deletes datasets
  series_length=F:get_dataset_count()
  for dataset_i=series_length-1,0,-1 do
    F:execute("use @"..dataset_i)
    delete_dataset(dataset_i)
  end
  delete_variables()
end
------------------------------------------
-- Saves info file into separate arrays so that @0 is empty.
-- Loads info file for file-wise operations, 
-- (columns: file nr;pre-amp;exposure time;nr of accumulations;gain;
-- gate width;additional multiplier)
-- Additionally loads sensitivity info file for point-wise operations 
-- (columns: file nr;sensitivity;additional multiplier)
function load_info()
	-- Loads data from file info file (file-wise correction)
  F:execute("@+ < "..input_path..input_info_name..":1:2..::")
  -- Pre amplification
  pre_amp_data=F:get_data(0)
  -- Length of info file
  first_filenr=pre_amp_data[0].x
  last_filenr=pre_amp_data[#pre_amp_data-1].x
  -- Exposure times
  exposures_data=F:get_data(1)
  -- Nr. of accumulations
  accumulations_data=F:get_data(2)
  -- Gains
  gains_data=F:get_data(3)
  -- Gate widths
  widths_data=F:get_data(4)
  -- Additional multipliers
  additional_file_multipliers=F:get_data(5)
  -- Makes 6 arrays
  pre_amps={}
  exposures={}
  accumulations={}
  gains={}
  widths={}
  file_multipliers={}
  -- Iterates over all rows for file-wise data and saves data into lua arrays
  for row=0,#pre_amp_data-1,1 do
    pre_amps[row]=pre_amp_data[row].y
    exposures[row]=exposures_data[row].y
    accumulations[row]=accumulations_data[row].y
    gains[row]=gains_data[row].y
    widths[row]=widths_data[row].y
    file_multipliers[row]=additional_file_multipliers[row].y
  end
  -- Deletes info datasets
  F:execute("reset")
  
  -- Loads data from sensitivity info file (point-wise correction), 
  -- assumes that the first pixel is 0 like in the spectra
  F:execute("@+ < "..input_path..input_sensitivity_name..":1:2..::")
  -- Sensitivity data
  sensitivities=F:get_data(0)
  -- Additional point-wise multiplier - for backup
  additional_point_multipliers=F:get_data(1)
  -- Makes an array
  spectra_multiplier={}
  -- Iterates over all rows for point-wise data and saves data into lua arrays
  for row=0,#sensitivities-1,1 do
    spectra_multiplier[row]=sensitivities[row].y*additional_point_multipliers[row].y
  end
  -- Deletes info datasets
  F:execute("reset")
  
  -- Always uses only the first dataset (plotting hack).
  F:execute("use@0")
end
------------------------------------------
-- Initializes output file, change path if needed
function init_output()
  file=io.open(output_path..output_data_name,"w")
  io.output(file)
  io.write("Experiment nr")
  io.write("\tCHI^2")
  io.write("\tDegrees of freedom")
  io.write("\tConstant")
  io.write("\tConstant error")
  for i=1,nr_of_lines,1 do
    io.write("\tVoigt"..i.." height")
    io.write("\tVoigt"..i.." height error")
    io.write("\tVoigt"..i.." center")
    io.write("\tVoigt"..i.." center error")
    io.write("\tVoigt"..i.." gwidth")
    io.write("\tVoigt"..i.." gwidth error")
    io.write("\tVoigt"..i.." shape")
    io.write("\tVoigt"..i.." shape error")
    io.write("\tVoigt"..i.." Area")
    io.write("\tVoigt"..i.." FWHM")
    io.write("\tVoigt"..i.." GaussianFWHM")
    io.write("\tVoigt"..i.." LorentzianFWHM")
  end
  io.write("\n")
  io.close(file)
end
------------------------------------------
-- Data initialization before looping over datasets
function init_data1()
  if experiment_check then
    -- Loads 1 experiment from file
    F:execute("@+ <"..input_path..file_index..file_end..":1:"..(experiment_check+1).."::")
  else
    -- Loads 1 file. Change path if needed
    F:execute("@+ <"..input_path..file_index..file_end..":1:2..::")
  end
  -- Finds nr. of series in file
  series_length=F:get_dataset_count()
end
------------------------------------------
-- Data initialization while looping over datasets
function init_data2()  
	-- Loads data from info arrays for specific experiment file
	-- exposure_time=exposures[file_index-first_filenr]
	pre_amp=pre_amps[file_index-first_filenr]
	nr_of_accumulations=accumulations[file_index-first_filenr]
	gain=gains[file_index-first_filenr]
	gate_width=widths[file_index-first_filenr]
	additional_multiplier=file_multipliers[file_index-first_filenr]
	-- Calculates the real gain of the signal (from experiments)
	actual_gain=1.120270358187*math.exp(0.0019597049*gain)
	-- Compiles a constant to divide current spectrum with it
	multiplier=additional_multiplier/(pre_amp*gate_width*nr_of_accumulations*actual_gain)--/exposure_time
	
	-- Multiplies dataset with experiment parameters
	F:execute("Y=y*"..multiplier)
	
	-- Multiplies points in dataset with sensitivity and additional point-wise multipliers.
	-- Also does error catching in case input sensitivity has nil values.
  for row=0,#spectra_multiplier,1 do
    status, err = pcall(function()
      F:execute("Y["..row.."]=y["..row.."]*"..spectra_multiplier[row])
    end)
    if status == false then
      print("Error: " .. err)
    end
  end
	
	-- Cuts out the edges of the spectra
	F:execute("@0: A = a and not (-1 < x and x < "..start..")")
	F:execute("@0: A = a and not ("..endpoint.." < x and x < 2050)")
end
------------------------------------------
-- Subroutine for guess_parameter_constructor() and get_errors()
-- Checks whether current line index is in use_as_Lorentzian array
function is_Lorentzian(linenr)
	for i=1,#use_as_Lorentzian do
		if use_as_Lorentzian[i]==linenr then 
			return true
		end
 	end
 	return false
end

------------------------------------------
-- Subroutine for fit_functions()
-- Constructs string for parameters to be used with "guess Voigt"
function guess_parameter_constructor(linenr)
  local parameters="(center="
  
  -- Center
  if line_center_domains[linenr]==0 then
    -- Center is locked variable
    parameters=parameters..line_positions[linenr]
  elseif line_center_domains[linenr]<0 then
    -- Center is simple variable
    parameters=parameters.."~"..line_positions[linenr]
  else
    -- Angle variable
    F:execute("$center"..dataset_index.."_"..linenr.."=~0")
    -- Center is inside given domain e.g it's a compound variable
    -- center=line_position+domain*sin(~angle)
    parameters=parameters..line_positions[linenr].."+"..
      line_center_domains[linenr].."*sin($center"..dataset_index.."_"..linenr..")"
  end
  
  -- gwidth angle variable, starts from 3pi/2 so that sin is minimal
	F:execute("$gwidth"..dataset_index.."_"..linenr.."=~4.712")
  -- If this line should be considered Lorentzian, then locks shape as 1e6 and leaves
  -- gwidth unbound
	if use_as_Lorentzian and is_Lorentzian(linenr) then
		-- shape
		parameters=parameters..",shape=1e6"
		
		-- gwidth
		-- gwidth=max_width+(max_width-min_width)/2*(sin(~ąngle)-1)
		parameters=parameters..",gwidth="..max_Lorentz_gwidth.."+"..
					((max_Lorentz_gwidth-min_Lorentz_gwidth)/2).."*(sin($gwidth"..
					dataset_index.."_"..linenr..")-1)"
	else
		--shape
		-- Angle variable (3pi/2)
		F:execute("$shape"..dataset_index.."_"..linenr.."=~0")
		-- shape=0.5+0.5*sin(~ąngle) (binds it from 0 to 1)
		parameters=parameters..",shape=0.5+0.5*sin($shape"..dataset_index.."_"..linenr..")"
		
		-- gwidth
		if max_line_gwidths[linenr]>0 then
			-- If there's substantial line broadening, guess wider functions
			if wide then
				-- gwidth=initial_gwidth+(initial_gwidth-min_gwidth)/2*(sin(~ąngle)-1)
				parameters=parameters..",gwidth="..guess_initial_gwidth.."+"..
					((guess_initial_gwidth-minimal_gwidth)/2).."*(sin($gwidth"..
					dataset_index.."_"..linenr..")-1)"
			else
				-- gwidth=max_width+(max_width-min_width)/2*(sin(~ąngle)-1)
				parameters=parameters..",gwidth="..max_line_gwidths[linenr].."+"..
					((max_line_gwidths[linenr]-minimal_gwidth)/2).."*(sin($gwidth"..
					dataset_index.."_"..linenr..")-1)"
			end
		end
	end
  
  -- Maximum data value
  F:execute("$max_data_value=max(y if (x>"..start.." and x<"..endpoint.."))")
  max_data_value=F:get_variable("max_data_value"):value()
  
  -- Forces height to be positive
  F:execute("$height_variable"..dataset_index.."_"..linenr.."=~"..max_data_value)
  -- height=abs(height_variable)
  parameters=parameters..",height=abs($height_variable"..dataset_index.."_"..linenr..")"
  
  parameters=parameters..")"
  return parameters
end
------------------------------------------
-- Line fitting for 1 constant and nr_of_lines Voigt profiles
function fit_functions()
  -- Constant tries to account for wide H-line. The constant is bound between minimal data value
  -- and median data value. Otherwise constant is fitted too high because of wide H-line.
  -- Lowest constant bound
  F:execute("$min_data_value=min(y if (x>"..start.." and x<"..endpoint.."))")
  minimal_data_value=F:get_variable("min_data_value"):value()
  if minimal_data_value<0 then minimal_data_value=0 end
  -- Highest constant bound
  F:execute("$median_data_value=centile(50, y if (x>"..start.." and x<"..endpoint.."))")
  median_data_value=F:get_variable("median_data_value"):value()
  if median_data_value<0 then median_data_value=0 end
  -- Constant angle variable
  F:execute("$constant"..dataset_index.."=~0")
  
  -- if user wants then constant gets a value between certain relative value and 
  -- minimal data value
  if lower_constant then
    max_constant_value=minimal_data_value+(median_data_value-minimal_data_value)*lower_constant
    -- constant=(max+min)/2+(max-min)/2*sin(~angle)
    constant_parameters=((max_constant_value+minimal_data_value)/2).."+"..
      ((max_constant_value-minimal_data_value)/2).."*sin($constant"..dataset_index..")"
  -- Else binds constant to be fitted between median and minimal data value
  else
    -- constant=(median+min)/2+(median-min)/2*sin(~angle)
    constant_parameters=((median_data_value+minimal_data_value)/2).."+"..
      ((median_data_value-minimal_data_value)/2).."*sin($constant"..dataset_index..")"
  end
  F:execute("guess Constant(a="..constant_parameters..")")
  
  -- Iterates over lines
  for linenr=1,nr_of_lines,1 do
    -- Globalizes linenr from for loop for variable naming
    line_index=linenr
    guess_parameters=guess_parameter_constructor(line_index)
    -- Possible error catching (if peak outside of the range)
    status, err = pcall(function() F:execute("guess Voigt "..guess_parameters) end)    
    -- Catch error
    if (not status) then
      -- Make dummy function for maintaining indexing
      F:execute("guess Voigt (center="..line_positions[linenr]..",height=0)")
      print("Error: " .. err)
    end
  end
	
	-- Double fitting for against possible getting stuck in local minima
  F:execute("@0: fit")
  F:execute("@0: fit")
  print("Experiment: "..file_index..separator..dataset_index)
end
------------------------------------------
-- Saves line parameters' errors. It gets errors from $_variable.parameter.error.
-- I've concluded that this value is the standard error for that parameter.
function get_errors()
  -- y=a+b*sin(angle) => y_error=d_y/d_angle * angle_error
  -- y_error=b*cos(angle)*angle_error
  for linenr=1,nr_of_lines,1 do
    if functions[linenr]:get_param_value("height")>0 then
      -- Height
      -- y_error=height_error since abs value in the end gives the derivative as 1
      F:execute("$height_error=$height_variable"..dataset_index.."_"..linenr..".error")
      height_errors[linenr]=math.abs(F:get_variable("height_error"):value())
      
			-- Shape
			-- If this line is Lorentzian and shape is locked, then error=0
			if use_as_Lorentzian and is_Lorentzian(linenr) then
				shape_errors[linenr]=0
			else
				F:execute("$shape_error=$shape"..dataset_index.."_"..linenr..".error")
				shape_errors[linenr]=math.abs(0.5*math.cos(F:get_variable("shape"..dataset_index.."_"..linenr):value())
				*F:get_variable("shape_error"):value())
			end

      -- Center
      if line_center_domains[linenr]>0 then
        F:execute("$center_error=$center"..dataset_index.."_"..linenr..".error")
        center_errors[linenr]=math.abs(line_center_domains[linenr]*math.cos(
        F:get_variable("center"..dataset_index.."_"..linenr):value())
        *F:get_variable("center_error"):value())
      end
      
      -- Gwidth
      if max_line_gwidths[linenr]>0 then
        if wide then
          F:execute("$gwidth_error=$gwidth"..dataset_index.."_"..linenr..".error")
          gwidth_errors[linenr]=math.abs((guess_initial_gwidth-minimal_gwidth)/2*math.cos(
          F:get_variable("gwidth"..dataset_index.."_"..linenr):value())
          *F:get_variable("gwidth_error"):value())
        else
          F:execute("$gwidth_error=$gwidth"..dataset_index.."_"..linenr..".error")
          gwidth_errors[linenr]=math.abs((max_line_gwidths[linenr]-minimal_gwidth)/2*math.cos(
          F:get_variable("gwidth"..dataset_index.."_"..linenr):value())
          *F:get_variable("gwidth_error"):value())
        end
      end
    end
  end
  -- dirty workaround to get constant standard error
	F:execute("$constant_error=$constant"..dataset_index..".error")
	constant_error=math.abs((median_data_value-minimal_data_value)/2*math.cos(
		F:get_variable("constant"..dataset_index):value())*
		F:get_variable("constant_error"):value())
end
------------------------------------------
-- Writes parameters of the functions into output file.
-- I've concluded that error values are standard errors.
function write_output()
  file=io.open(output_path..output_data_name,"a")
  io.output(file)
  -- Weighted sum of squared residuals, a.k.a. chi^2
  chi2=F:get_wssr(0)
  -- Degrees of freedom
  dof=F:get_dof(0)

  -- Writes dataset info
  io.write(file_index..separator..dataset_index)
  io.write("\t"..chi2)
  io.write("\t"..dof)
  io.write("\t"..functions[0]:get_param_value("a"))
  io.write("\t"..constant_error)
  -- loops over functions
  for i=1,nr_of_lines,1 do
    -- If there's no peak (peak height is 0) then all parameters are written "-"
    if (functions[i]:get_param_value("height")<=0) then
      io.write("\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-")
    -- Else reads and writes peak info
    else
      -- shape_errors array comes from get_errors()
      shape_error=shape_errors[i]
  
      -- Checks center error from calculations
      -- If domains are specified then center_errors array comes from get_errors()
      if line_center_domains[i]<0 then
        F:execute("$center_error=F["..i.."].center.error")
        center_error=F:get_variable("center_error"):value()
      elseif line_center_domains[i]==0 then
        center_error="locked"
      else
        center_error=center_errors[i]
      end
      
      -- Checks gwidth error from calculations
      -- If max gwidth is specified then gwidth_errors array comes from get_errors()
      if max_line_gwidths[i]>0 then
        gwidth_error=gwidth_errors[i]
      else
        F:execute("$gwidth_error=F["..i.."].gwidth.error")
        gwidth_error=F:get_variable("gwidth_error"):value()
      end
      
      -- Height error isn't anymore a simple variable since I bound it to positive values
      height_error=height_errors[i]
      
      -- Writes data into file
      io.write("\t"..functions[i]:get_param_value("height"))
      -- standard error
      io.write("\t"..height_error)
      io.write("\t"..functions[i]:get_param_value("center"))
      -- standard error
      io.write("\t"..center_error)
      io.write("\t"..math.abs(functions[i]:get_param_value("gwidth")))
      -- standard error
      io.write("\t"..gwidth_error)
      io.write("\t"..math.abs(functions[i]:get_param_value("shape")))
      -- standard error
      io.write("\t"..shape_error)
      io.write("\t"..functions[i]:get_param_value("Area"))
      io.write("\t"..functions[i]:get_param_value("FWHM"))
      io.write("\t"..functions[i]:get_param_value("GaussianFWHM"))
      io.write("\t"..functions[i]:get_param_value("LorentzianFWHM"))
    end
  end    
  io.write("\n")
  io.close(file)
end
------------------------------------------
-- Draws a plot of the dataset @0 and all it's functions the way
-- it's rendered on the GUI
function plot_functions()
  -- Constructs plot command with correct ranges
  plot_command="plot ["
  if x_min then plot_command=plot_command..x_min end
  plot_command=plot_command..":"
  if x_max then plot_command=plot_command..x_max end
  plot_command=plot_command.."] ["
  if y_min then plot_command=plot_command..y_min end
  plot_command=plot_command..":"
  if y_max then plot_command=plot_command..y_max end
  plot_command=plot_command.."] @0 >> "..output_path..file_index..separator..dataset_index..".png"
  -- Draws an image from data and functions and saves it to output folder
  F:execute(plot_command)
end
----------------------------------------------------------------------
----------------------------------------------------------------------
-- MAIN PROGRAM
-- Loads data from files into memory, finds defined peaks, fits them,
-- exports the data and plots the graphs.

-- Shifts all line positions according to user defined equation
if transform then 
  line_positions=shift_line_positions(line_positions)
end


-- Cleans Fityk-side from everything. Equivalent to delete_all().
F:execute("reset")

-- Asks whether to overwrite and start from scratch or just append
answer=F:input("Instead of overwriting, append to the output file? [y/n]")
if answer=='n' then 
  init_output()
end

-- Asks whether to use 1 experiment mode (good for debugging or line finding)
answer=F:input("Manually check 1 file? [y/n]")
if answer=='y' then 
  file_check=F:input("Number of file: ")
  experiment_check=F:input("Experiment number in the series: ")
end

-- Loads info and sensitivity into LUA arrays
load_info()

-- Iterates over files
for n=first_filenr,last_filenr,1 do 
  -- Globalizes the for loop index and checks whether to view 1 file
  if file_check then 
    file_index=file_check
  else
    file_index=n
  end
  
  -- Loads all spectra from file (or 1 spectra if using 1 experiment mode)
  init_data1()
  
  -- Loops over datasets from file.
  for m=1,series_length,1 do
    -- Check whether user wants to stop the script while it's still running
    stopfile=io.open(input_path..stopscript_name,"r")
    io.input(stopfile)
    content=io.read()
    io.close(stopfile)
    if content then
      stopscript=true
      print("Stopping the script since "..stopscript_name.." isn't empty")
      break
    end
    
    -- Globalizes the for loop index
    dataset_index=m
  	
  	-- Processes spectra with info and sensitivity data
    init_data2()
    
    -- Generates and fits functions
    fit_functions()
    
    -- Finds dataset functions
    functions=F:get_components(0)
    
    -- Saves functions' errors into arrays
    get_errors()
    
    -- if using 1 experiment view then writes dataset index as the number for output
    if experiment_check then
      dataset_index=experiment_check
    end
    
    -- Writes data into output file
    write_output()  
    
    -- Plots current dataset with functions
    if plot then plot_functions() end
    
    if not experiment_check then
      delete_dataset(0)
      -- Deletes all variables. This wasn't done with deleting functions and
    	-- it kept hogging resources. Now long processes take c.a 60x less time
    	delete_variables()
    end
    
    print("Experiment: "..file_index..separator..dataset_index.." done.")
  end
  
  -- Stop the loop if using 1 experiment view or user wants to stop the script
  if file_check or stopscript then
    break
  end
  
  print("File nr "..file_index.." done.")
  
  -- Stop at current file for debugging
  if stop then
    answer=F:input("Stop at file "..file_index.."? [y/n]")
    if answer=='y' then 
      break
    end
  end
  
  
  -- Resets all Fityk-side info (not LUA-side, that holds all necessary info)
  F:execute("reset")
  
  --[[ Not needed anymore. Culprit of slowing down (and RAM hogging) was that 
  -- variables didn't get deleted with functions.
  -- Garbage collection
  -- https://stackoverflow.com/questions/28320213/why-do-we-need-to-call-luas-collectgarbage-twice
  collectgarbage("collect")
  collectgarbage("collect")
  print(collectgarbage("count"))
  --]]
end