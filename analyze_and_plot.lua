-- Lua script for Fityk GUI version.
-- Script version: 1.4
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
nr_of_lines=60

-- Where are they in pixels? (only the first nr_of_lines lines are used)
-- By convention in lua, thhe first index is 1 instead of 0
line_positions=
{
-- Most intense peaks 656nm
972,    --1
1314,   --2
1503.3,   --3 x0.3
-- Other intense peaks
511,     --4
550.5,     --5
713,     --6
1143,    --7
1265.9,    --8x
1346,    --9
1559.7,    --10
-- Smaller intensity or mathematical peaks
452,	--11
466.3,  --12 Mo2
482,	--13
502.6,  --14 Mo2
547,    --15
562,    --16
584,	--17
603,	--18
639,	--19
648.4,  --20 Mo2
650,	--21
669,    --22
696,    --23
700,	--24
760,    --25
812,    --26
824,	--27
855,	--28
864,	--29
911,	--30
916,	--31
935,	--32
948,	--33
1014,	--34
1023,   --35
1044,	--36
1065,   --37
1087,	--38
1105,	--39
1121,   --40
1140,   --41
1155,	--42
1170,	--43
1255,	--44
1267.2, --45x0.2
1288,	--46
1354.6,	--47 Mo2
1363,   --48
1395,   --49
1404.3, --50
1423,   --51
1452,   --52
1497.1, --53x0.2
1499.1, --54x0.2
1527,   --55
1544,   --56
1551,	--57
1569,	--58
1591,	--59
1632	--60 Mo2




--[[
-- Most intense peaks 387nm
612,    --1
980,    --2
1198,   --3
-- Other intense peaks
522,    --4
546,    --5
783,    --6
810,    --7
941,    --8
1022,   --9
1229,   --10
1268,   --11
1326,   --12
1413,   --13
1422,   --14
1526,   --15
1564,   --16
-- Smaller intensity or mathematical peaks
457,    --17
509,    --18
528,    --19
633,    --20
655,    --21
689,    --22
733,    --23
751,    --24
771,    --25
802,    --26
819,    --27
891,    --28
965,    --29
1008,   --30
1031,   --31
1090,   --32
1108,   --33
1280,   --34
1354,   --35
1479,   --36
1595    --37
--]]
}

-- How far can the peak shift? If array element is non-0, 
-- then bigger shifts are considered lack of peak
-- Writing the value of the corresponding peak as -1 uses the default 30% domain.
-- 0 locks the line in place
line_center_domains=
{
--[[
3,	--1 387nm
3,	--2
3,	--3
3,	--4
3,	--5
3,	--6
3,	--7
3,	--8
3,	--9
3,	--10
3,	--11
3,	--12
3,	--13
3,	--14
3,	--15
3,	--16
3,	--17
3,	--18
3,	--19
3,	--20
3,	--21
3,	--22
3,	--23
3,	--24
3,	--25
3,	--26
3,	--27
3,	--28
3,	--29
3,	--30
3,	--31
3,	--32
3,	--33
3,	--34
3,	--35
3,	--36
3,	--37
3,	--38
3,	--39
3,	--40
3,	--41
3,	--42
3,	--43
3,	--44
3,	--45
3,	--46
3,	--47
3,	--48
3,	--49
3,	--50
3,	--51
3,	--52
3,	--53
3,	--54
3,	--55
3,	--56
3,	--57
3,	--58
3,	--59
3	--60
]]
30,	--1 656nm
3,	--2
0.3,	--3
3,	--4
3,	--5
3,	--6
3,	--7
0.2,	--8
3,	--9
3,	--10
3,	--11
0.5,	--12
3,	--13
0.5,	--14
3,	--15
3,	--16
3,	--17
3,	--18
3,	--19
0.5,	--20
3,	--21
3,	--22
3,	--23
3,	--24
3,	--25
3,	--26
3,	--27
3,	--28
3,	--29
3,	--30
3,	--31
3,	--32
3,	--33
3,	--34
3,	--35
3,	--36
3,	--37
3,	--38
3,	--39
3,	--40
0.2,	--41
3,	--42
3,	--43
3,	--44
0.2,	--45
3,	--46
0.5,	--47
3,	--48
3,	--49
3,	--50
3,	--51
3,	--52
0.2,	--53
0.2,	--54
3,	--55
3,	--56
3,	--57
3,	--58
3,	--59
0.5	--60
}

-- How large can the FWHM be? Larger lines are deleted. -1 skips FWHM check.
-- After introducing max_line_gwidths, this variable is rudimentary since you
-- can control funtions' gwidth directly. Write everything here -1.
max_line_widths=
{
-1,	--1
-1,	--2
-1,	--3
-1,	--4
-1,	--5
-1,	--6
-1,	--7
-1,	--8
-1,	--9
-1,	--10
-1,	--11
-1,	--12
-1,	--13
-1,	--14
-1,	--15
-1,	--16
-1,	--17
-1,	--18
-1,	--19
-1,	--20
-1,	--21
-1,	--22
-1,	--23
-1,	--24
-1,	--25
-1,	--26
-1,	--27
-1,	--28
-1,	--29
-1,	--30
-1,	--31
-1,	--32
-1,	--33
-1,	--34
-1,	--35
-1,	--36
-1,	--37
-1,     --38
-1,     --39
-1,     --40
-1,     --41
-1,     --42
-1,	--43
-1,	--44
-1,	--45
-1,	--46
-1,	--47
-1,	--48
-1,	--49
-1,	--50
-1,	--51
-1,	--52
-1,	--53
-1,	--54
-1,	--55
-1,	--56
-1,	--57
-1,     --58
-1,     --59
-1     --60
-- etc.
}

-- Binds gwidths to given maximum gwidth. If corresponding gwidth
-- <=0 then doesn't bind line gwidth
max_line_gwidths=
{
--[[
4,	--1 387nm
4,	--2
4,	--3
4,	--4
4,	--5
4,	--6
4,	--7
4,	--8
4,	--9
4,	--10
4,	--11
4,	--12
4,	--13
5,	--14
4,	--15
5,	--16
8,	--17
4,	--18
4,	--19
4,	--20
11,	--21
4,	--22
7,	--23
4,	--24
4,	--25
5,	--26
4,	--27
5,	--28
7,	--29
4,	--30
8,	--31
8,	--32
4,	--33
6,	--34
8,	--35
4,	--36
7,	--37
]]
80,	--1 656nm
4,	--2
4,	--3
4,	--4
4,	--5
4,	--6
4,	--7
4,	--8
4,	--9
4,	--10
4,	--11
4,	--12
4,	--13
4,	--14
4,	--15
4,	--16
4,	--17
4,	--18
4,	--19
4,	--20
4,	--21
4,	--22
4,	--23
4,	--24
4,	--25
4,	--26
4,	--27
4,	--28
4,	--29
4,	--30
4,	--31
4,	--32
4,	--33
4,	--34
4,	--35
4,	--36
4,	--37
4,	--38
4,	--39
4,	--40
4,	--41
4,	--42
4,	--43
4,	--44
4,	--45
4,	--46
4,	--47
4,	--48
4,	--49
4,	--50
4,	--51
4,	--52
2,	--53
2,	--54
4,	--55
4,	--56
4,	--57
4,	--58
4,	--59
4	--60
}

-- Where does the spectra actually start and end? (cutting away the edges) 
start=445
endpoint=1653

-- What are system paths for input and output folder?
-- Folders have to exist beforehand.
input_path="/Users/jasper/Documents/Magistritöö/Input/"
output_path="/Users/jasper/Documents/Magistritöö/Output/"

-- Change this if you want to use multiple instances of Fityk calculating
-- simultaneously using different inputs / different ranges. 
input_info_name="info.txt"
output_data_name="output.txt"

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

-- If peak is considered wide then how wide is it? -- somewhat rudimentary
guess_initial_gwidth=25

-- Should the peaks be considered wide? -- somewhat rudimentary
wide=false

-- What is the minimal line gwidth? Functions with gwidt lower than here
-- will be considered unphysical and written 0
minimal_gwidth=0.5

-- Do you want to stop for query for continuing after every file? [true/false]
stop=false

-- How much do you want to lower constant according to equation
-- constant_value=minimal_data_value+abs(constant_guess_value-minimal_data_value)*lower_constant
-- or do you just want Fityk to guess constant height 
-- (if former then recommended range is [0,1], if latter then write lower_constant=false).
lower_constant=0.2
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
file_check=nil
experiment_check=nil
stopscript=false

----------------------------------------------------------------------
--Function declarations
------------------------------------------
-- Deletes all datasets and functions for clean sheet
function delete_all()
  series_length=F:get_dataset_count()
  for k=series_length-1,0,-1 do
    F:execute("use @"..k)
    functions=F:get_components(k)
    for l=#functions-1,0,-1 do
      F:execute("delete %"..functions[l].name)
    end
    F:execute("delete @"..k)
  end
end
------------------------------------------
-- Saves info file into separate arrays so that @0 is empty.
-- Loads info file, (columns: file nr;exposure time;nr of accumulations;gain;gate width)
function load_info()
  F:execute("@+ < "..input_path..input_info_name..":1:2..::")
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
  -- Always uses only the first dataset.
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
    exposure_time=exposures[file_index-first_filenr]
    nr_of_accumulations=accumulations[file_index-first_filenr]
    gain=gains[file_index-first_filenr]
    gate_width=widths[file_index-first_filenr]
    -- Calculates the real gain of the signal
    actual_gain=1.120270358187*math.exp(0.0019597049*gain)
    division=exposure_time*nr_of_accumulations*actual_gain*gate_width

    -- Divides dataset with experiment parameters
    F:execute("Y=y/"..division)
    
    -- Cuts out the edges of the spectra
    F:execute("@0: A = a and not (-1 < x and x < "..start..")")
    F:execute("@0: A = a and not ("..endpoint.." < x and x < 2050)")
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
  -- Angle variable (3pi/2)
  F:execute("$shape"..dataset_index.."_"..linenr.."=~0")
  -- shape=sin(~ąngle)
  parameters=parameters..",shape=0.5+0.5*sin($shape"..dataset_index.."_"..linenr..")"
  
  -- Gwidth
  if max_line_gwidths[linenr]>0 then
    -- Angle variable starts from 3pi/2 so that sin is minimal
    F:execute("$gwidth"..dataset_index.."_"..linenr.."=~4.712")
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
  -- if user wants then constant gets an average value of current constant
  -- height and minimal data value
  if lower_constant then
    -- reads defined functions e.g constant
    functions=F:get_components(0)
    F:execute("$min_data_value=min(y if (x>"..start.." and x<"..endpoint.."))")
    constant_guess_value=functions[0]:get_param_value("a")
    minimal_data_value=F:get_variable("min_data_value"):value()
    constant_guess_value=minimal_data_value+math.abs(constant_guess_value-minimal_data_value)*lower_constant
    constant_variable=functions[0]:var_name("a")
    F:execute("$"..constant_variable.."="..constant_guess_value)
  end
  -- Iterates over lines
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
  F:execute("@0: fit")
  print("Experiment: "..file_index..separator..dataset_index)
end
------------------------------------------
-- Gives functions 0-height if they are negative or 
-- center is shifted further than defined in center domains array
function check_functions()
  -- Loops 2 times
  for i=1,2,1 do 
    -- Writes constant as 0 if it's negative
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
    F:execute("@0: fit")
    print("Experiment: "..file_index..separator..dataset_index)
  end
end
------------------------------------------
-- Saves line parameters' errors. It gets errors from $_variable.parameter.error.
-- I've concluded that this value comes from confidence interval of 97%. It
-- doesn't match with standard deviation directly.
function get_errors()
  -- y=a+b*sin(angle) => y_error=d_y/d_angle * angle_error
  -- y_error=b*cos(angle)*angle_error
  for linenr=1,nr_of_lines,1 do
    if functions[linenr]:get_param_value("height")>0 then
      -- Shape
      F:execute("$shape_error=$shape"..dataset_index.."_"..linenr..".error")
      shape_errors[linenr]=math.abs(0.5*math.cos(F:get_variable("shape"..dataset_index.."_"..linenr):value())
      *F:get_variable("shape_error"):value())
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
end
------------------------------------------
-- Writes parameters of the functions into output file.
-- I've concluded that error values come from confidence interval of 97%. They
-- don't match with standard deviation directly.
function write_output()
  file=io.open(output_path..output_data_name,"a")
  io.output(file)
  -- Weighted sum of squared residuals, a.k.a. chi^2
  chi2=F:get_wssr(0)
  -- Degrees of freedom
  dof=F:get_dof(0)
  -- dirty workaround to get constant error covariance
  if (functions[0]:get_param_value("a")==0 or lower_constant) then
    constant_error="-"
  else
    F:execute("$a_cov=F[0].a.error")
    constant_error=F:get_variable("a_cov"):value()
  end
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
------------------------------------------
-- Deletes all functions and the dataset
function delete_dataset()
    -- Gets functions for given dataset
    functions=F:get_components(0)
    -- Iterates over functions and deletes functions for current dataset
    for function_index=#functions-1,0,-1 do
      F:execute("delete %"..functions[function_index].name)
    end
    -- Deletes the dataset
    F:execute("delete @0")
end
----------------------------------------------------------------------
----------------------------------------------------------------------
-- MAIN PROGRAM
-- Loads data from files into memory, finds defined peaks, fits them,
-- exports the data and plots the graphs.

delete_all()
load_info()

-- Asks whether to overwrite and start from scratch or just append
answer=F:input("Instead of appending, overwrite output file? [y/n]")
if answer=='y' then 
  init_output()
end

answer=F:input("Manually check 1 file? [y/n]")
if answer=='y' then 
  file_check=F:input("Number of file: ")
  experiment_check=F:input("Experiment number in the series: ")
end

-- Iterates over files
for n=first_filenr,last_filenr,1 do 
  -- Globalizes the for loop index and checks whether to view 1 file
  if file_check then 
    file_index=file_check
  else
    file_index=n
  end
  
  
  init_data1()
  
  -- Loops over datasets from file.
  for m=1,series_length,1 do
    -- Check whether user wants to stop the script while it's still running
    stopfile=io.open(input_path.."stopscript.txt","r")
    io.input(stopfile)
    content=io.read()
    io.close(stopfile)
    if content then
      stopscript=true
      print("Stopping the script since stopscript.txt isn't empty")
      break
    end
    
    -- Globalizes the for loop index
    dataset_index=m
  
    init_data2()
    fit_functions()
    
    -- Finds dataset functions
    functions=F:get_components(0)
    
    check_functions()
    get_errors()
    
    -- if using 1 experiment view then writes dataset index as the number for output
    if experiment_check then
      dataset_index=experiment_check
    end
    
    write_output()  
    -- Plots current dataset with functions
    if plot then plot_functions() end
    
    if not experiment_check then
      delete_dataset()
    end
    
    print("Experiment: "..file_index..separator..dataset_index.." done.")
  end
  
  -- Stop the loop if using 1 experiment view or user wants to stop the script
  if file_check or stopscript then
    break
  end
  
  -- Stop at current file for debugging
  if stop then
    answer=F:input("Stop at file "..file_index.."? [y/n]")
    if answer=='y' then 
      break
    end
  end
  
  print("File nr "..file_index.." done.")
  collectgarbage("collect")
end