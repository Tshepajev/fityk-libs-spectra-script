This readme file describes how to use the script analyze_and_plot.lua to fit lines.

1) Modify the working directory at the start of analyze_and_plot.lua (lines 44-45). That is, work_folder and info_folder variables.



2) Modify the user constants in _user_constants.lua. The constants are in a separate script in order to save the parameters 
used for that run. You probably need to fine-tune the constants.



3) Create folder structure as follows: work_folder is the root and contains info_folder and input_path.
output_path, corrected_path and sessions_path folders will be created automatically if they don't exist. 
output_path folder contains sessions_path folder. 
- info_folder contains info how the script should execute
- input_path contains the input data (spectra and background files)
- output_path will hold the data ouput by the script (fitted line parameters, images of the fit, saved sessions after fitting)
- corrected_path contains spectra after corrections (e.g. wavelengths and gain) to save time when processing data multiple times. 
If there are files from previous executions then the script will skip the data correction phase and will read in the spectra 
from corrected_path instead.
If the data or something in info_folder changes then the old files in corrected_path might be invalid.
E.g. if you change Pixel_info*.csv contents then also the corrected spectrums would change or if you change process_nr_spectra in
_user_constants.lua then the old filenames of the corrected spectra won't match with the expected names.


3a) Move the _user_constants.lua into info_folder.


3b) Move the input data (spectra and background files if they exist) into input_path folder.



4) Create files that guide the script in info_folder:


4.a) Create Pixel_info*.csv file (* can be any normal characters). That CSV file contains values for each pixel for 
data correction (same amount of rows as in input data). All files corresponding to the wildcard filename are read 
into memory. If there's only one such file, that one is used. Otherwise the one defined in Spectra_info*.csv is used.

The headers/column names are: "Measured unit,Wavelength (m),Sensitivity,Additional multiplier,Additional additive".
If the column is missing (or one field in the column) then the default value is assigned to the missing values.
The columns don't have to be in specific order and most of the columns don't have to exist but the spelling of the headers matters.
"Measured unit" column is mandatory, otherwise the line isn't used.

Blank/erroneous fields default to:
local default_values = {
	["Measured unit"] = nil, -- important
	["Wavelength (m)"] = nil, -- semi-important, defaults to measured unit
	["Sensitivity"] = 1,
	["Additional multiplier"] = 1,
	["Additional additive"] = 0
}

The following describes what each column means/does.
- "Measured unit" is same unit that the camera outputs (e.g. pixel 1-1024 or wavelength 200-700 nm).
The measured units have to be the same as in the input data. This column needs to exist with all data filled out.

- "Wavelength (m)" is the real wavelength corresponding to the measured unit. The x-axis is overwritten with these values. 
Currently, value is assigned by index, so the measured units need to match exactly with the ones in input data files
but in the future there might be interpolation.

- Sensitivity is the multiplier that is used for the y-axis correction at that measured unit.

- Additional multiplier is there just in case, leave it as blank field or 1 by default.

- Additional additive is there just in case, leave it as blank field or 0 by default.


4.b) Create Spectra_info*.csv (* can be any normal characters). There can be multiple files with the 
wildcard * being different and all of those are used.
The file contains info for which data files (spectra) to use and the spectrum-wide y-axis correction. 
That is, all pixels are corrected with these values.
Only the data files are used and fitted that are defined in Spectra_info*.csv files.
All the data from different Spectra_info*.csv files is merged, so it doesn't matter whether you have one large file or many smaller ones.

The headers/column names are: "Filename,Pixel correction filename,Lines filename,Background filename,Series length,Nr. of spectra accumulations,
Camera pre amplification,Camera gain,Camera gate width (s),Additional multiplier,Additional additive"
"Filename" column is mandatory and must be the first column, otherwise the script crashes. 
If the Filename column exists but a field is missing then that row isn't used.
Other columns don't need to be in the same order.
"Pixel correction filename", "Lines filename" and "Series length" should be properly defined unless you know perfectly what you're doing.

Blank/erroneous fields default to:
local default_values = {
	["Filename"] = nil, -- important
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

The following describes what each column means/does.
- "Filename" has to match with the start of the data file name (extension doesn't matter).
If the input data has multiple files with the beginning of the Filename, followed by a number then all of these will be 
processed as one data series. E.g. Filename "xyz_001" will result in "xyz_001.asc", "xyz_002.asc" and "xyz_003.asc" 
being used as subsequent spectra in the series. This column needs to exist. If the field has a blank value then the row is ignored.

is_complex_filename variable in _user_constants.lua is used to check how to extract the experiment series identifier from a filename.
It also determines how you must input the filename in Spectra_info*.csv or when using 1 experiment mode.
If you're using JET LIBS spectra (2024) then this must be set to true, if not then it's optional.

Note that in Spectra_info*.csv you have to either provide a direct match of the filename OR 
you have to provide the entire filename, where the index is 1, preceded by zeros, so it matches the actual 
filename containing the first spectrum of the series (e.g. if index always has 3 digits then the index must be "001"). 
That filename represents the entire experimental series, so index can change but identifier is locked in place.
This could be "abc0001" or "abc_0001_def", second one with the index in the middle of the name must have _ before the index.
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

- "Pixel correction filename" will use that Pixel_info*.csv file for pixel-wise correction. 
If only one Pixel_info*.csv is available then that is used regardless of Pixel correction filename.

- "Lines filename" will use that Lines_info*.csv file for selecting lines to fit.
If only one Lines_info*.csv is available then that is used regardless of Lines filename.

- "Background filename" will use that data file as the background measurement if the spectra and background are recorded separately.
If there is no background file or you don't want background correction then leave that field empty (two commas in sequence in csv).
If you want to use background correction then use the data filename that has the right background measurement. The script needs the 
file extension (e.g. ".asc") but if it's not provided then the script adds file_end from _user_constants.lua.
For the background measurement data file write "Background_info" in the field. This makes the
script skip that file for line fitting. Example: "LIBS_sample_01.asc" has spectrum and "bg.asc" has the background for 
"LIBS_sample_01.asc". Then for the row that contains filename "LIBS_sample" write "bg" in the "Background filename" field and
write "Background_info" in the "Background filename" field for the row which has filename "bg".

- "Series length" holds information about how many spectra are in the measurement series (e.g. if a series of 30 spectra are in three files
LIBS_001.asc, which contains 15 spectra, LIBS_002.asc, which contains 10 spectra, and LIBS_003.asc, which contains 5 spectra, then 
the series lengt is 30). In case there's an error in the input files or data. E.g if LIBS_003.asc is
missing then an error message tells you that there wasn't 30 spectra to process. It's best to then correct the input info. This column needs 
to exist with data filled out.

- "Nr. of spectra accumulations" is a number. If the camera summed 3 spectra and then output one spectrum then write 3. The y-axis
is divided by this value.

- "Camera pre amplification" is the setting for which gain function to use. This must be a number and it will select a function to use
from gain_functions variable defined in _user_constants.lua. If the field is empty then it defaults to 1.

- "Camera gain" is the value used as the camera gain (not real multiplier). This is converted to real multiplier by a gain function in 
gain_functions in _user_constants.lua. The right function is selected with the Camera pre amplification field. The y-values of the data
get divided by the output of the gain function.

- "Camera gate width (s)" is the gate width used in the measurements. The y-values of the specrum are divided by this value.

- "Additional multiplier" is there just in case, leave it as blank field or 1 by default.

- "Additional additive" is there just in case, leave it as blank field or 0 by default.


4.c) Create Lines_info*.csv file. That file contains all the necessary info about the lines to be fitted.
All files corresponding to the wildcard filename are read into memory.

The headers/column names must be: "Wavelength (m),Identificator,Function to fit,To fit (1/0),To output (1/0),
Max position shift (m),Max line fwhm (m),Max influence radius (m),Linked variables"
If the column is missing (or one field in the column) then the default value is assigned to the missing values.
The columns don't have to be in specific order and most of the columns don't have to exist but the spelling of the headers matters.
"Wavelength (m)" column is mandatory, otherwise the line isn't used.

Blank/erroneous fields default to:
local default_values = {
	["Wavelength (m)"] = nil, -- important
	["Identificator"] = "_",
	["Function to fit"] = "Voigt",
	["To fit (1/0)"] = 1,
	["To output (1/0)"] = 1,
	["Max position shift (m)"] = 0,
	["Max line fwhm (m)"] = infinity,
	["Max influence radius (m)"] = default_max_line_influence_radius,
	["Linked variables"] = nil
}

The same output file is written for all different experiments, so the lines and their order must be the same for all experiments. 
This means each index must have the same line: with the same ID and the same line function and the same wavelength.
Otherwise the output headers wouldn't apply for the different line at that index.
So, you should use only one Lines_info*.csv file per script run, unless all Lines_info*.csv files contain the same spectral lines.

The specifics of how the script chooses what Lines_info*.csv file to use is as follows.
If there's only one Lines_info*.csv file in the folder, that one is used, regardless of what's in Spectra_info*.csv.
If there are multiple files in the folder but all rows in all Spectra_info*.csv files define the same lines info file, 
then the defined Lines_info*.csv file is used.
Otherwise only one Lines_info*.csv file is used for all experiments (rows in Spectra_info*.csv files), and the file is the one
that contains the most amount of spectral lines (and rows in the file). 
If there are multiple files that contain the most amount of lines then a random of those is chosen.
The only exception is that when two Lines_info*.csv files reference the same spectral line for each row, then the one of those 
two files which is defined in Spectra_info*.csv is used.
The spectral line is "the same in the two files" if all of the fields "Wavelength (m)", "Function to fit", "Identificator" match 
in the two loaded Lines_info*.csv tables.
Since the lines are checked by index in the tables then also "To fit (1/0)" and "To output (1/0)" must be the same.
So in short, those 5 field values must be identical for all spectral lines in the two files (neither the order of rows in the files 
nor the order of the columns in the files matter because the tables are sorted).
If any one field value in any spectal lines in any files is different then a random file is chosen to represent all experiments.
Ideally, you would use exact copies of the one Lines_info*.csv file and only change the fields "Max position shift (m)", 
"Max line fwhm (m)", "Max influence radius (m)", and "Linked variables".

The following describes what each column means/does.
- "Wavelength (m)" is the wavelength the line is at. This column needs to exist with data filled out. It's best to consider the
actual data instead of the wavelengths from databases. The lines are sorted and created in the order of ascending wavelengths, so, 
although not necessary for the script, it's best to have lines sorted in the file too. 

If you have two lines at exactly same wavelengths then instead add an infinitesimal to one of these. This ensures always the same 
order for the lines and is important for the output file and parameter linking. The line/function name format is "Identificator_000000",
which includes the first 6 significant digits (rounded) of the wavelength. In case of two or more matches of the function name, the
subsequent functions are named with "Identificator_000000_1" format, in which the last number corresponds to how many lines before it 
would have the same name. This way each function has a unique name. The order of linked variables and defined custom variables depends 
on the order of the sorted lines (sort by wavelength and if two wavelengths match then a random one is used first). This is another 
reason to add an infinitesimal.
If there are overlapping lines, e.g. a weak and wide and a strong (high) and narrow line overlap, then it's best to generate the strong 
line first and weak line second (add positive infinitesimal to the weak line) because at line generation the first line has larger 
weight (contributes more to the points close to the location), being fitted higher and probably gets stuck in local minimum even if 
the area of the wide line is larger. 

The line has to be in range of an active datapoint at the time of creation. Otherwise the script will catch the error and will instead 
create a dummy line (locked height 0, width and shape 1). The range is defined by line function inside Fityk and I don't know the 
distance from the line center where the line function value is greater than 0. Therefore, it's best to not fit lines outside of the 
dataset. 


- "Identificator" is a string to distinguish the line. This is used for the name of the line (e.g. "Be1" in "Be1_457270"). 
The resulting string must not contain any special characters, including spaces. Fityk doesn't allow anything else besides digits, 
letters and _.

- "Function to fit" selects which line function to use for fitting. 
This can be a string of any defined Fityk line function (e.g. "Voigt").
The script defines three new line functions: Rectangle, RectanglePositive, VoigtFWHM and VoigtApparatus. 
First one is a rectangle function gained with combining two Sigmoids.
RectanglePositive is the same but with height restricted to positive values and 0.
VoigtFWHM is Voigt but gwidth is replaced with FWHM (also dependent on shape). 
That function is a bit more volatile than ordinary Voigt but is great for intuitive values. 
VoigtApparatus is the Voigt profile which locks the Gaussian part width as the apparatus function at that location. 
The apparatus function is defined by apparatus_function_fwhm() function in _user_constants.lua in Input_info folder.

- "To fit (1/0)" defines whether to use the row in the file or to skip it (you don't have to delete rows in input file).
The spectal line is skipped only if the field is 0, even empty field gets used (defaults to 1).

- "To output (1/0)" defines whether to use resources to fit the line well and to use it in the output file. The spectal line output is 
skipped only if the field is 0, even empty field gets used (defaults to 1).
If it's 0, then the line gets created and fitted if it falls into the influence diameter of another fitted line, but the active window 
doesn't specifically stop on that line, so the line won't be optimally fitted. The field helps if it's an unimportant but prominent 
line which would influence nearby important lines if they were fitted and the current one wasn't created.

- "Max position shift (m)" is the maximum shift (radius) left or right in the x-axis allowed for the line during fitting.

- "Max line fwhm (m)" is the maximum line width allowed for the line during fitting.
If the line has gwidth or hwhm parameter then fwhm is calculated from/to those.

- "Max influence radius (m)" determines the width of the local fitting window for each line. 
Once the moving window reaches that line then the window size is determined by this variable.
All lines within the window (that haven't been finalized yet) are activated and their parameters unlocked and fitted along with the 
current line.
Ideally, the window would span across all datapoints and lines, but each additional variable (and datapoint) to use during fitting 
increases the fit time exponentially.
This is why this field should be as small as possible while still guaranteeing that the line and all interfering lines are in the window.
To be safe, use a larger value than the minimum viable value.
A line is defined to be inside the window if at least the line center is on the boundary of the window.
This field must account for any nearby lines influencing the fitting of the current one.
If the current line is narrow and there are only narrow lines nearby then the influence radius can be small.
If the current line is wide then the influence radius must be respectively wider.
Empirically, a Lorentzian line (wider than Gaussian and Voigt) has height of 1-2 % approximately at 4 FWHM-s distance from the line 
center, so if there are no other lines then the influence range would be 4 * maximum FWHM.
Essentially, influence radius must be (4 * maximum FWHM of the current line + 4 * maximum FWHM of the interfering line).
Exception is when you are observing a weak line but there is a very-very strong line far away. 
Then e.g. 0.1 % of the strong line tail can still influence the observable line and therefore, the influence radius must be larger.
Since the window (and observable line index) moves from left to right (towards higher wavelengths) and a line is locked after the 
window center has passed it, then the lines left of the observable line aren't important when considering influence radius (those have been
already fitted optimally).

- Linked variables is a field to assign the line parameters to certain variables. This can be used to link the parameters of multiple
spectral lines or to initialize custom variable values. E.g. if two lines use the same variable for center parameter then there's 
only one variable that's modified during fitting and both lines always have the same center value. The field is fed into Fityk command 
line for parsing after separating the commands by my script. If it's an empty string (two commas in csv) then it just gets ignored.
E.g. the field can contain "$center_variable = 400e-9; center = 4.57270e-007 + 3e-011 * sin($center_variable); height = abs($height_variable + 5)".
The whitespace characters don't matter. The parameter (of a line) that uses user-defined "Linked variables" won't have it's error estimate 
because it would require heavy string parsing and implementing derivative finding in LUA.

Here's a quick overview of how Fityk uses its variables and function parameters (also see Fityk manual) before continuing Linked variables 
field explanation. A function (line) has multiple parameters. E.g. Gaussian function has parameters height, center and hwhm. Each of these 
parameters has a variable assigned to it. There are 3 types of variables: simple variable (e.g. "~3.5" allows fitting to change the value), 
locked variable a.k.a. constant (e.g. "3.5" doesn't change the value during fitting), and compound variable (e.g. "~3.5 + 2 * $_var" which 
contains multiple variables and is updated if any of these change). If you declare a parameter like "%_function.parameter = ~3.5" then 
Fityk first creates a new variable "$_15 = ~3.5" and then assigns the variable to the parameter "%_function.parameter = $_15". If you assing 
one parameter to another (can be same or different function), then the referenced variable is used for both parameters (e.g. 
"%_function2.parameter2 = %_function.parameter" means than now both parameters use $_15 variable).

The Linked variables field is a string that is fed into Fityk to be parsed, so it's crucial that the format is correct. 
The format can contain multiple expressions, separated by semicolons ; and the whitespace characters don't matter. My script only considers 
two instances of expressions: 
1) custom variable value declaration (it is "$variable =..."), 
2) everything else is concatenated to the function (assumed to be a function parameter and the result is concat("%_current_fn.", expression)).
The variable declaration expressions (option 1) of all lines are fed into Fityk from left to right one by one. All variables of all lines 
are declared before linking parameters (option 2). Only then are the parameters of all lines linked in such a way that dependencies are 
linked first (topologically sorted). It's recommended to use of referencing existing functions and parameters (%_fn.param = 
%_fn2.param + ~1) and therefore variables these depend on rather than creating new variables ("$new = ~1 ; %_fn.param = $new") because I have 
tested that more thoroughly.

If you want to initialize a variable with a custom value then the expression between the semicolons has to start with $ and the next symbol 
has to be an ordinary letter (Fityk can't use some special characters and use caution when using _ because _1 format is already used by 
Fityk). Fityk doesn't want a number directly after the $. Do NOT use variables in "$_1" format (underscore and number after dollar sign)! 
These variables are created by Fityk and this might cause conflicts and unexpected behavior. You can write "~3.5" in a compound variable
to automatically create the referenced new simple variable with the value of 3.5, but it will have a random name.

The custom variable declarations fed directly to Fityk. Standard Fityk syntax applies, so if you write ~ in front of the number when 
initializing a variable (simple variable) then the variable can change during fitting, otherwise it's locked (constant). You can link 
variables this way too (compound variable), the script will initialize variables within an expression (between semicolons) after the 
equation sign first, so that a variable can depend on another variable etc. Note that if a variable already exists then its value won't
be overwritten and that expression instead gets ignored. So, if you want a compound variable with the referenced variable having a custom
value (not the default "~1"), then you have to declare that one first. Note that if you don't intend to use a referenced variable in a 
compound variable anywhere else then you can directly write "~3.5" to initialize it with the value 3.5. This way Fityk automatically creates 
a new simple variable with value of 3.5, but you won't know the name of the variable. The line parameters are linked only after all variables 
of all lines have been initialized. Because of that you mustn't reference line parameters in variable declaration expression (option 1) so 
that the variable would depend on a line parameter (e.g. "$_abc = %H_line.height" wouldn't work because line isn't created yet, but 
"height = $_abc" would for that function).

In the example given in the first paragraph, if they don't already exist, the variables $center_variable and $height_variable are 
created with the value of "~1" (default value, simple variable) by the script. "$center_variable = 400e-9" is done before the 
parameter linking and the variable is created with the custom value. If the variable was created during the creation of some previous spectral 
line then it won't be overwritten now, so make sure you linked everything correctly! Note that the lines are sorted by ascending wavelength, 
not in the order in Lines_info*.csv. If you want to use two lines at the same wavelength then instead add infinitesimal value (e.g. 1e-13 m) 
to the second one. Then everything still works as intended. In the script, since the function name is in [Identificator]_000000 format 
(get_fn_name() rounds the input wavelength) then the lines created later (larger wavelengths) will still have 6 significant digits for 
the wavelength, but it will be in [Identificator]_000000_0 format with the last value showing number of lines with the same name before 
the current one (_1 means there's 1 line with the same name on the left).

For parameter linking expressions, the whitespace right after semicolon is stripped and every string between semicolons (which isn't a 
variable value declaration) is fed straight into Fityk, being preceeded by the function identifier and a dot. In the example, Fityk gets 
"%Be1_457.center = 4.57270e-007 + 3e-011 * sin($center_variable)". If another row in Lines_info*.csv (another line) contains the same 
variable then the both lines/functions are linked by that variable. You can also use function.parameter syntax instead of the variable. 
E.g. "%H_656.center = %D_656.center + 0.18e-9". The linking can be used to e.g. create H line and D line always 0.18 nm left of it, or 
the widths and shapes of the lines could be made to use the same variable (same width and shape). Or e.g. W lines could all use 
theoretical amplitudes, being linked to each other, acting as a group. This parameter linking is a very powerful tool for fitting the 
spectra. For script v4.0, the function.parameter syntax needs the function to be created before (referenced line needs to have lower 
wavelength than this one). In script v4.1+ the order of the linked parameters doesn't matter (references are topologically sorted). 

If you want the linked parameters to follow the automatically defined bounds e.g. by "Max position shift (m)" and "Max line fwhm (m)" 
then you have two options: either you reference another parameter through the function name (Identificator) like described in the H-D
example previously, or you write the full equation that constricts the variable between bounds like described in the Be1_457 example
previously. 

Multiple windows are simultaneously active, so that all linked lines contribute to fitting the variable. The leftmost linked function 
is considered the original (e.g. all are fitted when moving window reaches the original and only the original gets error/uncretainty 
assigned to the variable). If the linked variable has been fitted already then it's locked for other linked lines. 




5) Make sure input is UTF-8! Lua can't handle unicode characters like no break space that e.g. excel sometimes outputs.
This can be done by ctrl+f in e.g. Notepad++ and removing these characters from Excel output csv file.
Another issue with Excel has been that it outputs certain number format like is displayed in the cells. 
E.g. having 4 decimals accuracy and scientific notation is not enough for wavelengths that would need 5-6 decimals.



6) Make sure the input data is correct. I've lost many hours debugging the code when in original experiments one spectrum wasn't saved
or a file was cut before the experiment finished.



7) Optional - prepare Fityk for image output. 
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



8) Optional - prepare for multithreading. Fityk and LUA can't multithread but you can run multiple instances of Fityk.
You can delete some rows (experiment series) in Spectra_info.csv (or add a comma in front, then script assumes there's no
filename and skips the row) and run the script. Then you can rename the file, so that it doesn't start with "Spectra_info" 
and create another file with other set of experiment series. Then you can run the other instance of Fityk simultaneously 
on different part of the input data. Make sure to change stopscript_name variable to be able to stop one instance without 
stopping the other.



9) Run the script. At the start there are 2 questions. First one allows you to either run the script
in 1 experiment mode or batch processing mode. 

- Batch processing mode. In this mode everything defined in Spectra_info*.csv files is processed. A spectrum is processed, 
output saved and then the previous fitting data deleted before moving on to the next spectrum.
- 1 experiment mode. In this mode only one experiment (or series) is processed, output written and the script exits before 
deleting the fitting result. This way it's possible to check what's going on while LUA variables are still in the memory.
Alternative is to open the Fityk session files in the output.

If you choose 1 experiment mode then you need to insert additional info.
That is, you need to provide the data filename (without extension) that you want to check. The filename in this input field
must follow the same logic as in Spectra_info*.csv as described earlier in this file. E.g. If the filename that you want to
use is "LIBS_data_0051.asc" and 0051 is the index of the experiment in the series then write "LIBS_data_0001" and specify the
experiment number in the next query. If you inserted the filename correctly and the script finds the data then it asks 
you the experiment number. That is, the number of the spectrum in the series. In the previous example it was "51". If you 
write something that can't be converted to a number (including blank answer) then all of the spectra in that series are processed.

Finally, the script asks you whether you want to continue. If you made a mistake or changed your mind
then you can safely and quickly stop the script now.

Note that the output file contains uncertainties for every used parameter. However, due to LIBS spectra complexity (multiple 
overlapping lines, heavy noise, continuum), these can't be trusted by default.
 



10) Stopping the script during execution. If you want the script to stop during processing then ctrl+c would stop the script. 
However, Fityk is frozen during heavy calculations and you can't stop the script that way. To stop the script, write 
something into _Stopscript.txt in input_info folder and don't forget to save the file. Then during the next processing 
loop (might take a minute) the script checks the file and since there is something written, then the script stops.
_Stopscript.txt is generated/emptied in the Input_info folder at the start of the script execution.



11) In case of crashes check the code first or contact me before abandoning the project! Usually the crash happens because 
of some simple mistake and the fix doesn't take much time. Unfortunately, the script has grown so large that I can't test 
every nuance of it with all different kind of inputs. Also see "_Troubleshooting.txt" in the readmes folder in Main script folder.
That file contains some info about bugs, crashes and debugging.

An easier way to debug the code is to set debug_mode variable (in _user_constants.lua) to e.g. 3. Setting it to 5 is even more verbose 
but is very slow during initialization phase. debug_mode 3 shows the last executed function and then you can zone in on the bug 
with print() statements.



12) Output. 
* Input_info_corrected folder contains processed spectra which might be useful for other analysis.
* Output folder contains the output file (_Fityk_output.csv) which contains all of the data from the fitting. Two first rows are headers: first row is for line ID, second row is for extracted parameter name. All other rows are for each fitted experiment (in all of the experiment series). The error values can't be trusted if using complex spectra (also explained in Fityk manual), but could prove useful in some cases. 
* Output folder contains the _user_constants.lua copy-pasted from input, so that the data processing would be repeatable.
* Output folder contains images for quick overview of the situation. The images are exactly like the GUI shows when zoomed out, so they might be crowded if using many lines and showing the labels of lines.
* Output folder contains the Sessions folder with the Fityk session before continuing to the next experiment. These are useful to check interactively whether everything was fitted well or to do additional manual work with the spectrum after the fitting.

The actual local continuum is global constant (min data value) + local constant. The average or median of
the local constants is also a noise level estimate.



13) Optional - use "Fityk output organizer.lua" from utility scripts folder to sum/average/take median of the parameters 
from Fityk output by line identifier. Depending on the amount of data, it might take a minute to process the output.