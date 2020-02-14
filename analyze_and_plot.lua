-- Lua script for Fityk GUI version.
-- Script version: 1.0
-- Author: Jasper Ristkok

--[[
Written for use with LIBS (atomic) spectra gained from SOLIS software
with Andor iStar340T ICCD camera.
The script could possibly be used for other applications but some
adjustments to the code might be needed.
There are comments to simplify understanding the code but
I assume assume that you have read the Fityk manual 
(http://fityk.nieto.pl/fityk-manual.html).

In Fityk the dataset to be plotted needs to be selected, 
however, selecting dataset is a GUI feature and is unavailable 
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


-- Change constants below
----------------------------------------------------------------------
-- Constants, change them
-- How many spectra lines are there?
nr_of_lines=3
-- Where are they in pixels? (only the first nr_of_lines lines are used)
-- By convention in lua, the first index is 1 instead of 0
line_positions={1013,1359,1546,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
-- How far can the peak shift? If array element is non-0, 
-- then bigger shifts are considered lack of peak
-- Writing the value of the corresponding peak as 0 uses the default 30% domain.
line_center_domains={500,15,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0} 
-- Where does the spectra actually start and end? (cutting away the edges) 
start=445
endpoint=1666
-- What are system paths for input folder and output folder
input_path="/Users/jasper/repos/spectra-analyzer/Example/"
output_path="/Users/jasper/repos/spectra-analyzer/Example/Output/"
-- What type of files do you use?
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
----------------------------------------------------------------------
-- Change constants above


-- Deletes all datasets and functions for clean sheet
--answer=F:input("Delete all? [y/n]")
answer='y'
if answer=='y' then 
  series_length=F:get_dataset_count()
  for k=series_length-1,0,-1 do
    F:execute("use @"..k)
    --print("k:"..k)
    functions=F:get_components(k)
    --print("functions:",functions)
    --print("nr of functions:"..#functions)
    for l=#functions-1,0,-1 do
      --print("l:"..l)
      --print("funcs:",functions[l])
      --print("function name:",functions[l].name)
      F:execute("delete %"..functions[l].name)
    end
    F:execute("delete @"..k)
  end
end


-- Block: Saves info file into separate arrays so that @0 is empty.
-- Loads info file, (columns: file nr;exposure time;nr of accumulations;gain;gate width)
F:execute("@+ < "..input_path.."info.txt:1:2..::")
-- Loads data from info file
-- Exposure times
exposures_data=F:get_data(0)
-- Length of info file
first_filenr=exposures_data[0].x
last_filenr=exposures_data[#exposures_data-1].x
-- Nr. of accumulations
accumulations_data=F:get_data(1)
-- Gains
gains_data=F:get_data(2)
-- Gate widths
widths_data=F:get_data(3)
-- Makes 4 arrays
exposures={}
accumulations={}
gains={}
widths={}
-- Iterates over all rows and saves data into lua arrays
for row=0,#exposures_data-1,1 do
  exposures[row]=exposures_data[row].y
  accumulations[row]=accumulations_data[row].y
  gains[row]=gains_data[row].y
  widths[row]=widths_data[row].y
end
-- Deletes info datasets
for n=0,4,1 do
  F:execute("delete @0")
end


-- Initializes output file, change path if needed
file=io.open(output_path.."output.txt","w")
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

-- Always uses only the first dataset.
F:execute("use@0")

-- Loads data from files into memory, finds defined peaks, fits them,
-- exports the data and plots the graphs.
for n=first_filenr,last_filenr,1 do 
  -- Loads 1 file. Change path if needed
  F:execute("@+ <"..input_path..n..file_end..":1:2..::")
  -- Finds nr. of series in file
  series_length=F:get_dataset_count()
  -- Loops over datasets from file. Change path if needed
  for m=1,series_length,1 do
    -- Loads data from info arrays for specific experiment file
    exposure_time=exposures[n-first_filenr]
    nr_of_accumulations=accumulations[n-first_filenr]
    gain=gains[n-first_filenr]
    gate_width=widths[n-first_filenr]
    -- Calculates the real gain of the signal
    actual_gain=3.0955e-11*gain^4-1.45304e-7*gain^3+0.0002454*gain^2-0.129418*gain+13.00316
    division=exposure_time*nr_of_accumulations*actual_gain*gate_width
    
    -- Divides dataset with experiment parameters
    F:execute("Y=y/"..division)
    
    -- Cuts out the edges of the spectra
    F:execute("@0: A = a and not (-1 < x and x < "..start..")")
    F:execute("@0: A = a and not ("..endpoint.." < x and x < 2050)")
    
    -- Line fitting for 1 constant and nr_of_lines Voigt profiles
    F:execute("guess Constant")
    for linenr=1,nr_of_lines,1 do
      F:execute("guess Voigt (center=~"..line_positions[linenr]..")")
      F:execute("@0: fit")
    end
    
    
    -- Block: gives functions 0-height if they are negative or 
    -- center is shifted further than defined in center domains array
    -- Finds dataset functions
    functions=F:get_components(0)
    -- Iterates over functions
    for i=1,nr_of_lines,1 do
      -- If there's no peak (peak<0) or if the line has domains defined 
      -- and the center is not in range then peak is considered absent
      if ((functions[i]:get_param_value("height")<0) or 
      (not(line_center_domains[i]==0) and 
      math.abs(functions[i]:get_param_value("center")-line_positions[i])>line_center_domains[i])) then
        -- Finds height variable for given function
        height_variable=functions[i]:var_name("height")
        F:execute("$"..height_variable.."=0")
        -- Refits the functions
        F:execute("@0: fit")
      end
    end


    -- Block: writes parameters of the functions into output file
    file=io.open(output_path.."output.txt","a")
    io.output(file)
    -- Weighted sum of squared residuals, a.k.a. chi^2
    chi2=F:get_wssr(0)
    -- Degrees of freedom
    dof=F:get_dof(0)
    -- dirty workaround to get constant error covariance
    F:execute("$a_cov=F[0].a.error")
    constant_error=math.sqrt(F:get_variable("a_cov"):value()*chi2/dof)
    -- Writes dataset info
    io.write(n..separator..(m))
    io.write("\t"..chi2)
    io.write("\t"..dof)
    io.write("\t"..functions[0]:get_param_value("a"))
    io.write("\t"..constant_error)
    -- loops over functions
    for i=1,nr_of_lines,1 do
      -- If there's no peak (peak height is 0) then all parameters are written "-"
      if (functions[i]:get_param_value("height")==0) then
        io.write("\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-")
      -- Else reads and writes peak info
      else
        -- Dirty workaroud for getting errors covariances
        F:execute("$height_cov=F["..i.."].height.error")
        F:execute("$center_cov=F["..i.."].center.error")
        F:execute("$gwidth_cov=F["..i.."].gwidth.error") 
        F:execute("$shape_cov=F["..i.."].shape.error") 
        -- Calculates standard errors (form "Curve Fitting" in Fityk manual)
        height_error=math.sqrt(F:get_variable("height_cov"):value()*chi2/dof)
        center_error=math.sqrt(F:get_variable("center_cov"):value()*chi2/dof)
        gwidth_error=math.sqrt(F:get_variable("gwidth_cov"):value()*chi2/dof)
        shape_error=math.sqrt(F:get_variable("shape_cov"):value()*chi2/dof)
        -- Writes data into file
        io.write("\t"..functions[i]:get_param_value("height"))
        io.write("\t"..height_error)
        io.write("\t"..functions[i]:get_param_value("center"))
        io.write("\t"..center_error)
        io.write("\t"..math.abs(functions[i]:get_param_value("gwidth")))
        io.write("\t"..gwidth_error)
        io.write("\t"..math.abs(functions[i]:get_param_value("shape")))
        io.write("\t"..shape_error)
        io.write("\t"..functions[i]:get_param_value("Area"))
        io.write("\t"..functions[i]:get_param_value("FWHM"))
        io.write("\t"..functions[i]:get_param_value("GaussianFWHM"))
        io.write("\t"..functions[i]:get_param_value("LorentzianFWHM"))
      end
    end    
    io.write("\n")
    io.close(file)
    
    
    -- Plots current dataset with functions
    if plot then
      -- Constructs plot command with correct ranges
      plot_command="plot ["
      if x_min then plot_command=plot_command..x_min end
      plot_command=plot_command..":"
      if x_max then plot_command=plot_command..x_max end
      plot_command=plot_command.."] ["
      if y_min then plot_command=plot_command..y_min end
      plot_command=plot_command..":"
      if y_max then plot_command=plot_command..y_max end
      plot_command=plot_command.."] @0 >> "..output_path..n..separator..(m)..".png"
      -- Draws an image from data and functions and saves it to output folder
      F:execute(plot_command)
    end

  
    -- Block: deletes all functions and the dataset
    -- Gets functions for given dataset
    functions=F:get_components(0)
    -- Iterates over functions and deletes functions for current dataset
    for l=#functions-1,0,-1 do
      F:execute("delete %"..functions[l].name)
    end
    -- Deletes dataset
    F:execute("delete @0")
    
    print("Series nr "..(m).." done.")
  end
  
  --[[
  -- Stop at current file for debugging
  answer=F:input("Stop at file "..n.."? [y/n]")
  if answer=='y' then 
    break
  end
  ]]
  
  print("File nr "..n.." done.")
end