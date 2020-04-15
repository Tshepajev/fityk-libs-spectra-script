-- Lua script for Fityk.
-- Script version: 1.2 - might be outdated
-- Author: Jasper Ristkok

-- Written for use with LIBS (atomic) spectra gained from SOLIS software
-- with Andor iStar340T ICCD camera.
-- The script could possibly be used for other applications but some
-- adjustments to the code might be needed.
-- There are comments to simplify understanding the code but
-- I assume assume that you have read the Fityk manual 
-- (http://fityk.nieto.pl/fityk-manual.html).


-- Change constants below
----------------------------------------------------------------------
-- Constants, change them
-- How many spectra lines are there?
nr_of_lines=21
-- Where are they in pixels? (only the first nr_of_lines lines are used)
-- By convention in lua, thhe first index is 1 instead of 0
line_positions={
973,    --1
1314,   --2
1504,   --3
483,    --4
510,    --5
553,    --6
639,    --7
651,    --8
714,    --9
866,    --10
913,    --11
1046,   --12
1105,   --13
1156,   --14
1253,   --15
1267,   --16
1355,   --17
1451,   --18
1553,   --19
1595,   --20
1634}   --21
-- How far can the peak shift? If array element is non-0, 
-- then bigger shifts are considered lack of peak
-- Writing the value of the corresponding peak as -1 uses the default 30% domain.
-- 0 locks the line in place
line_center_domains={
40,     --1
3,      --2
3,      --3
3,      --4
6,      --5
3,      --6
3,      --7
3,      --8
3,      --9
3,      --10
3,      --11
3,      --12
3,      --13
3,      --14
3,      --15
3,      --16
3,      --17
3,      --18
30,     --19
3,      --20
3}      --21
-- How large can the FWHM be? Larger lines are deleted. -1 skips FWHM check.
max_line_widths={
-1,     --1
-1,     --2
-1,     --3
-1,     --4
-1,     --5
-1,     --6
-1,     --7
-1,     --8
-1,     --9
-1,     --10
-1,     --11
-1,     --12
-1,     --13
-1,     --14
-1,     --15
-1,     --16
-1,     --17
-1,     --18
-1,     --19
-1,     --20
-1}     --21
-- Binds gwidths to given maximum gwidth. If corresponding gwidth
-- <=0 then doesn't bind line gwidth
max_line_gwidths={
50,     --1
15,     --2
15,     --3
15,     --4
40,     --5
15,     --6
15,     --7
15,     --8
15,     --9
15,     --10
15,     --11
15,     --12
15,     --13
15,     --14
15,     --15
15,     --16
15,     --17
15,     --18
40,     --19
15,     --20
15}     --21
-- Where does the spectra actually start and end? (cutting away the edges) 
start=445
endpoint=1662
-- What are system paths for input folder and output folder
input_path="/Users/jasper/Documents/Magistritöö/Koos/"
output_path="/Users/jasper/Documents/Magistritöö/Output/"
-- What type of files do you use?
file_end=".asc"
-- When importing text into spreadsheet filename (e.g. 13.5) may be 
-- read as a float. Using different separator (e.g. 13,5) avoids losing
-- "decimal" zeros from the end of the value
separator=","
-- If peak is considered wide then how wide is it?
guess_initial_gwidth=25
-- Should the peaks be considered wide?
wide=false
-- What is the minimal line gwidth? Functions with gwidt lower than here
-- will be considered unphysical and written 0
minimal_gwidth=0.3
----------------------------------------------------------------------
-- Change constants above


--Global variable initializations
first_filenr=nil
last_filenr=nil
exposures=nil
acc_nrs=nil
gains=nil
widths=nil
center_error="-"
center_errors={}
gwidth_errors={}
shape_errors={}

----------------------------------------------------------------------
--Function declarations
------------------------------------------
-- Deletes all datasets and functions
function delete_all(with_info)
  -- Default argument value
  if with_info==nil then with_info=true end
  -- Whether to delete all or leave info datasets  
  if with_info then
    final_dataset=0
  else
    final_dataset=4
  end
  series_length=F:get_dataset_count()
  for k=series_length-1,final_dataset,-1 do
    F:execute("use @"..k)
    functions=F:get_components(k)
    for l=#functions-1,0,-1 do
      F:execute("delete %"..functions[l].name)
    end
    F:execute("delete @"..k)
  end
end
------------------------------------------
-- Loads info file
-- (columns: file nr;exposure time;nr of accumulations;gain;gate width)
function load_info()
  F:execute("@+ < "..input_path.."info.txt:1:2..::")
  -- Finds first and last file number
  files=F:get_data(0)
  first_filenr=files[0].x
  last_filenr=files[#files-1].x
  -- Loads data from info file
  exposures=F:get_data(0)
  acc_nrs=F:get_data(1)
  gains=F:get_data(2)
  widths=F:get_data(3)
end
------------------------------------------
-- Initializes output file, change path if needed
function init_output()
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
end
------------------------------------------
-- Loads file and initializes data
function init_data()
  -- Loads 1 file. Change path if needed
  F:execute("@+ <"..input_path..file_index..file_end..":1:2..::")
  -- Loads data from info file for specific experiment file
  exposure_time=exposures[file_index-first_filenr].y
  nr_of_accumulations=acc_nrs[file_index-first_filenr].y
  gain=gains[file_index-first_filenr].y
  gate_width=widths[file_index-first_filenr].y
  -- Calculates the real gain of signal
  actual_gain=3.0955e-11*gain^4-1.45304e-7*gain^3+0.0002454*gain^2-0.129418*gain+13.00316
  division=exposure_time*nr_of_accumulations*actual_gain*gate_width
  -- Finds nr. of series in file, includes 4 info sets
  series_length=F:get_dataset_count()
end
------------------------------------------
-- Initiates dataset
function init_dataset()
-- Divides datasets with experiment parameters
F:execute("use @"..dataset_index)
F:execute("Y=y/"..division)
-- Cuts out the edges of the spectra
F:execute("@"..dataset_index..": A = a and not (-1 < x and x < "..start..")")
F:execute("@"..dataset_index..": A = a and not ("..endpoint.." < x and x < 2050)")
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
    -- Center is inside given domain
    -- center=line_position+domain*sin(~angle)
    parameters=parameters..line_positions[linenr].."+"..
    line_center_domains[linenr].."*sin($center"..dataset_index.."_"..linenr..")"
  end
  
  -- Shape
  -- Angle variable
  F:execute("$shape"..dataset_index.."_"..linenr.."=~0")
  -- shape=sin(~ąngle)
  parameters=parameters..",shape=0.5+0.5*sin($shape"..dataset_index.."_"..linenr..")"
  
  -- Gwidth
  if max_line_gwidths[linenr]>0 then
    -- Angle variable
    F:execute("$gwidth"..dataset_index.."_"..linenr.."=~0")
    -- If there's substantial line broadening, guess wider functions
    if wide then
      -- gwidth=initial_gwidth+initial_gwidth*sin(~ąngle)
      parameters=parameters..",gwidth="..guess_initial_gwidth.."+"..
      guess_initial_gwidth.."*sin($gwidth"..dataset_index.."_"..linenr..")"
    else
      -- gwidth=1+max_width*sin(~ąngle)
      parameters=parameters..",gwidth=0.5+"..
      max_line_gwidths[linenr].."*sin($gwidth"..dataset_index.."_"..linenr..")"
    end
  end
  
  parameters=parameters..")"
  return parameters
end
------------------------------------------
-- Line fitting for 1 constant and nr_of_lines Voigt profiles
-- Checks whether domain is negative, 0 or a positive value.
-- In the latter case, highest peak is found in range and then center
-- gets locked in place.
function fit_functions()
  F:execute("guess Constant")
  for linenr=1,nr_of_lines,1 do
    -- Globalizes linenr from for loop for variable naming
    line_index=linenr
    guess_parameters=guess_parameter_constructor(line_index)
    -- Possible error catching (if peak outside of the range)
    status, err = pcall(function() F:execute("guess Voigt "..guess_parameters) end)    
    -- Catch error
    if (not status) then
      -- Make dummy function for indexing
      F:execute("guess Voigt (center="..line_positions[linenr]..",height=0)")
      print("Error: " .. err)
    end
  end
  F:execute("@"..dataset_index..": fit")
  print("Experiment: "..file_index..separator..(dataset_index-3))
end
------------------------------------------
-- Gives functions 0-height if they are negative or 
-- center is shifted further than defined in center domains array
function check_functions()
  for i=1,2,1 do 
    -- Writes constant 0 if it's negative
    if (functions[0]:get_param_value("a")<0) then
      constant_variable=functions[0]:var_name("a")
      F:execute("$"..constant_variable.."=0")
    end
    -- Iterates over functions
    for i=1,nr_of_lines,1 do
      -- Checks if line has negative height
      negative_height=(functions[i]:get_param_value("height")<0)
      -- Checks if line is too wide
      if max_line_widths[i]<0 then
        too_wide=false
      else
        gaussian_width=(functions[i]:get_param_value("GaussianFWHM"))
        lorentzian_width=(functions[i]:get_param_value("LorentzianFWHM"))
        too_wide=(math.abs(gaussian_width)>max_line_widths[i] or 
        math.abs(lorentzian_width)>max_line_widths[i])
      end
      -- Checks line center position
      too_far=(math.abs(functions[i]:get_param_value("center")-line_positions[i])>line_center_domains[i])
      -- Checks line gwidth in respect to the minimal gwidth
      too_thin=((math.abs(functions[i]:get_param_value("gwidth"))-minimal_gwidth)<0)
      -- If there's no peak (peak<0) or if the line has domains defined 
      -- and the center is not in range 
      -- or line is too wide then peak is considered absent
      if (negative_height or too_wide or too_far or too_thin) then
        -- Finds height variable for given function
        height_variable=functions[i]:var_name("height")
        F:execute("$"..height_variable.."=0")
      end
    end
    -- Refits the functions
    F:execute("@"..dataset_index..": fit")
    print("Experiment: "..file_index..separator..(dataset_index-3))
  end
end
------------------------------------------
-- Saves line parameters' errors
function get_errors()
  -- y=a+b*sin(angle) => y_error=d_y/d_angle * angle_error
  -- y_error=b*cos(angle)*angle_error
  for linenr=1,nr_of_lines,1 do
    if functions[linenr]:get_param_value("height")>0 then
      -- Shape
      F:execute("$shape_error=$shape"..dataset_index.."_"..linenr..".error")
      shape_errors[linenr]=math.cos(F:get_variable("shape"..dataset_index.."_"..linenr):value())
      *F:get_variable("shape_error"):value()
      -- Center
      if line_center_domains[linenr]>0 then
        F:execute("$center_error=$center"..dataset_index.."_"..linenr..".error")
        center_errors[linenr]=line_center_domains[linenr]*math.cos(
        F:get_variable("center"..dataset_index.."_"..linenr):value())
        *F:get_variable("center_error"):value()
      end
      -- Gwidth
      if max_line_gwidths[linenr]>0 then
        if wide then
          F:execute("$gwidth_error=$gwidth"..dataset_index.."_"..linenr..".error")
          gwidth_errors[linenr]=guess_initial_gwidth*math.cos(
          F:get_variable("gwidth"..dataset_index.."_"..linenr):value())
          *F:get_variable("gwidth_error"):value()
        else
          F:execute("$gwidth_error=$gwidth"..dataset_index.."_"..linenr..".error")
          gwidth_errors[linenr]=max_line_gwidths[linenr]*math.cos(
          F:get_variable("gwidth"..dataset_index.."_"..linenr):value())
          *F:get_variable("gwidth_error"):value()
        end
      end
    end
  end
end
------------------------------------------
-- Writes parameters of the functions into output file
function write_output()
  file=io.open(output_path.."output.txt","a")
  io.output(file)
  -- Weighted sum of squared residuals, a.k.a. chi^2
  chi2=F:get_wssr(dataset_index)
  -- Degrees of freedom
  dof=F:get_dof(dataset_index)
  -- dirty workaround to get constant error
  if functions[0]:get_param_value("a")==0 then
    constant_error="-"
  else
    F:execute("$a_error=F[0].a.error")
    constant_error=F:get_variable("a_error"):value()
  end    
  -- Writes dataset info
  io.write(file_index..separator..(dataset_index-3))
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
      -- shape_errors array comes from guess_parameter_constructor()
      shape_error=shape_errors[i]
  
      -- Checks center error from calculations
      -- If domains are specified then center_errors array comes 
      -- from guess_parameter_constructor()
      if line_center_domains[i]<0 then
        F:execute("$center_error=F["..i.."].center.error")
        center_error=F:get_variable("center_error"):value()
      elseif line_center_domains[i]==0 then
        center_error="locked"
      else
        center_error=center_errors[i]
      end
      
      -- Checks gwidth error from calculations
      -- If max gwidth is specified then gwidth_errors array comes from guess_parameter_constructor()
      if max_line_gwidths[i]>0 then
        gwidth_error=gwidth_errors[i]
      else
        F:execute("$gwidth_error=F["..i.."].gwidth.error")
        gwidth_error=F:get_variable("gwidth_error"):value()
      end
      
      -- Dirty workaroud for getting errors
      F:execute("$height_error=F["..i.."].height.error")
      -- Finds standard error (form "Curve Fitting" in Fityk manual)
      height_error=F:get_variable("height_error"):value()

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
----------------------------------------------------------------------
----------------------------------------------------------------------
-- MAIN PROGRAM
-- Loads data from files into memory, finds defined peaks, fits them and exports the data.

delete_all()
load_info()

-- Asks whether to overwrite and start from scratch or just append
  answer=F:input("Instead of appending, overwrite output file? [y/n]")
  if answer=='y' then 
    init_output()
  end
  


-- Iterates over files
for n=first_filenr,last_filenr,1 do 
  -- Globalizes the for loop index
  file_index=n
  init_data() 
  
  -- Iterates over all series in file
  for m=4,series_length-1,1 do
    -- Globalizes the for loop index
    dataset_index=m  
    init_dataset()
    fit_functions()

    -- Finds dataset functions
    functions=F:get_components(dataset_index)
    
    check_functions()
    get_errors()
    write_output()    
    print("Series nr "..(dataset_index-3).." done.")
    --if m==5 then break end -- debug break
  end
  
  -- Stop at current file for debugging
  answer=F:input("Stop at file"..file_index.."? [y/n]")
  if answer=='y' then 
    break
  end

  delete_all(false)
  print("File nr "..file_index.." done.")
end