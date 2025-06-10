This readme file describes how to use the script analyze_and_plot.lua to fit lines.

1) Modify the working directory at the start of analyze_and_plot.lua. That is, variables work_folder and info_folder.



2) Modify the user constants in user_constants.lua. The constants are in a separate script in order to save the parameters 
used for that run.



3) Create folder structure as follows: work_folder is the root and contains info_folder, input_path, output_path, corrected_path. 
output_path folder contains sessions_path folder. output_path, corrected_path and sessions_path folders will be created automatically
if they don't exist. 
- info_folder contains info how the script should execute
- input_path contains the input data (spectra and background files)
- output_path will hold the data ouput by the script (fitted line parameters, images of the fit, saved sessions after fitting)
- corrected_path contains spectra after corrections (e.g. wavelengths and gain) to save time when processing data multiple times. 
If there are files from previous executions then the script will skip the data correction phase and will read in the spectra 
from corrected_path instead.


3a) Move the user_constants.lua into info_folder.


3b) Move the input data (spectra and background files if they exist) into input_path folder.


3c) Optional: copy the user_constants.lua into output_path, so that the fitting is reproducible after you change user_constants.lua.



4) Create files that guide the script in info_folder:


4.a) Create Pixel_info*.csv file (* can be any normal characters). That CSV file contains values for each pixel for 
data correction (same amount of rows as in input data). All files corresponding to the wildcard filename are read 
into memory. If there's only one such file, that one is used. Otherwise the one defined in Spectra_info*.csv is used.

The headers/column names must be: ""Measured unit,Wavelength (m),Sensitivity,Additional multiplier,Additional additive".
The column headers need to be the same as (currently) hardcoded in the script.
- Measured unit is same unit that the camera outputs (e.g. pixel 1-1024 or wavelength 200-700 nm).
The measured units have to be the same as in the input data. This column needs to exist with all data filled out.
- Wavelength is the real wavelength corresponding to the measured unit.
The x-axis is overwritten with these values.
- Sensitivity is the multiplier that is used for the y-axis correction at that measured unit.
- Additional multiplier is there just in case, leave it as blank field or 1 by default.
- Additional additive is there just in case, leave it as blank field or 0 by default.

Blank/erroneous fields default to:
local default_values = {
	["Measured unit"] = nil, -- important, needs to be first column in input file
	["Wavelength (m)"] = pixel_info[filename]["Measured unit"][pixel_index], -- defaults to measured unit
	["Sensitivity"] = 1,
	["Additional multiplier"] = 1,
	["Additional additive"] = 0
}

4.b) Create Spectra_info*.csv (* can be any normal characters). There can be multiple files with the 
wildcard * being different and all of those are used.
The file contains info for which data files (spectra) to use and the spectrum-wide y-axis correction. 
That is, all pixels are corrected with these values.
Only these data files are used and fitted that are defined in Spectra_info*.csv files.

The headers/column names must be: "Filename,Pixel correction filename,Lines filename,Background filename,Nr. of spectra accumulations,
Camera pre amplification,Camera gain,Camera gate width (s),Series length,Additional multiplier,Additional additive"
The headers must match the ones used in the script.
- Filename has to match with the start of the data file name. Leave out the file extension (e.g. .asc).
If the input data has multiple files with the beginning of the Filename, followed by a number then all of these will be 
processed as one data series. E.g. Filename "xyz" will result in "xyz_01.asc", "xyz_02.asc" and "xyz_03.asc" being used as subsequent
spectra in the series. This column needs to exist. If data has a blank value then the row is ignored.
- Pixel correction filename will use that Pixel_info*.csv file for pixel-wise correction. 
If only one Pixel_info*.csv is available then that is used regardless of Pixel correction filename.
- Lines filename will use that Lines_info*.csv file for selecting lines to fit.
If only one Lines_info*.csv is available then that is used regardless of Lines filename.
- Background filename will use that data file as the background measurement if the spectra and background are recorded separately.
If there is no background file or you don't want background correction then leave that field empty (two commas in sequence in csv).
If you want to use background correction then use the data filename that has the right background measurement. The script needs the 
file extension (e.g. ".asc") but if it's not provided then the script adds file_end from user_constants.lua.
For the background measurement data file write "Background_info" in the field. This makes the
script skip that file for line fitting. Example: "LIBS_sample_01.asc" has spectrum and "bg.asc" has the background for 
"LIBS_sample_01.asc". Then for the row that contains filename "LIBS_sample" write "bg" in the "Background filename" field and
write "Background_info" in the "Background filename" field for the row which has filename "bg".
- Nr. of spectra accumulations is a number. If the camera summed 3 spectra and then output one spectrum then write 3. The y-axis
is divided by this value.
- Camera pre amplification is the setting for which gain function to use. This must be a number and it will select a function to use
from gain_functions variable defined in user_constants.lua. If the field is empty then it defaults to 1.
- Camera gain is the value used as the camera gain (not real multiplier). This is converted to real multiplier by a gain function in 
gain_functions in user_constants.lua. The right function is selected with the Camera pre amplification field. The y-values of the data
get divided by the output of the gain function.
- Camera gate width (s) is the gate width used in the measurements. The y-values of the specrum are divided by this value.
- Series length holds information about how many spectra are in the measurement series (e.g. if a series of 30 spectra are in three files
LIBS_001.asc, which contains 15 spectra, LIBS_002.asc, which contains 10 spectra, and LIBS_003.asc, which contains 5 spectra, then 
the series lengt is 30). In case there's an error in the input files or data. E.g if LIBS_003.asc is
missing then an error message tells you that there wasn't 30 spectra to process. It's best to then correct the input info. This column needs 
to exist with data filled out.
- Additional multiplier is there just in case, leave it as blank field or 1 by default.
- Additional additive is there just in case, leave it as blank field or 0 by default.

Blank/erroneous fields default to:
local default_values = {
	["Filename"] = nil, -- important
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


4.c) Create Lines_info*.csv file. That file contains all the necessary info about the lines to be fitted.
All files corresponding to the wildcard filename are read into memory.
If there's only one such file, that one is used. Otherwise the one defined in Spectra_info*.csv is used.
Since output file has only one header then processing spectra with different (number of) lines is an issue in the output.
Therefore, the program picks the longest list of lines from those files and outputs that. It's strongly advisable to have
one set of lines for all spectra defined in the Spectra_info file.

The headers/column names must be: "Wavelength (m),To fit (1/0),Fit priority (1 is first),
function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian),Max position shift (m),Max line fwhm (m),Chemical element,
Ionization number (1 is neutrals),E_k (eV),log(A_ki*g_k/?),line index"
- Wavelength (m) is the wavelength the line is at. It's best to consider the actual data instead of the wavelengths from databases.
The line has to be in range of an active datapoint at the time of creation. The range is defined by line function inside Fityk and
I don't know the range value where the line function value is greater than 0. Therefore, it's best to not fit lines outside of the 
dataset. This column needs to exist with data filled out.
- To fit (1/0) must be 1 or 0. This selects whether to use the line or not (don't have to delete rows in input).
- Fit priority (1 is first) sets the order the lines are created. This is relevant when there are overlapping lines. E.g. a strong
and weak line overlap. Then it's best to generate the strong line first and weak line second because at line generation the first line
has larger weight (contributes more to the points), being fitted bigger. If overlapping lines isn't an issue then this field can be
left empty or filled with any number.
- function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian) selects which line function to use for fitting. This can be a string of any
defined Fityk line function. In the future, I will delete the "(0-Voigt; 1-Gaussian; 2-Lorentzian)" part.
The script defines three new line functions: Rectangle, VoigtFWHM and VoigtApparatus. First one is a rectangle function gained with
combining two Sigmoids. Second one is Voigt but gwidth is replaced with FWHM (also dependent on shape). That function is a bit more 
volatile than ordinary Voigt. VoigtApparatus is the Voigt profile which locks the Gaussian part width as the apparatus function. 
I haven't tested it thoroughly but so far, it hasn't produced errors.
- Max position shift (m) is the maximum shift left or right in the x-axis allowed for the line during fitting.
- Max line fwhm (m) is the maximum line width allowed for the line during fitting.
- Chemical element is string for the element the line is associated with. This is used for the name of the line. See also Ionization 
number!
- Ionization number (1 is neutrals) is string for the element the line is associated with. This is used for the name of the line.
The line name and identifier is Chemical_element .. Ionization_number .. "_" .. wavelength (e.g. "Be2_467342"). The resulting string
must not contain any special characters, including spaces. Fityk doesn't allow anything else besides digits, letters and _.
- E_k (eV) is unused and can be omitted.
- log(A_ki*g_k/?) is unused and can be omitted.
- line index is unused and can be omitted.

Blank/erroneous fields default to:
local default_values = {
		["To fit (1/0)"] = 1, -- important
		["Fit priority (1 is first)"] = 1,
		["Wavelength (m)"] = nil, -- important
		["function to fit (0-Voigt; 1-Gaussian; 2-Lorentzian)"] = "Voigt",
		["Max position shift (m)"] = 0,
		["Max line fwhm (m)"] = infinity,
		["Chemical element"] = "_",
		["Ionization number (1 is neutrals)"] = 1,
		["E_k (eV)"] = nil,
		["log(A_ki*g_k/?)"] = nil,
		["line index"] = nil
	}


5) Make sure input is UTF-8! Lua can't handle unicode characters like no break space that e.g. excel sometimes outputs.
This can be done by ctrl+f in e.g. Notepad++ and removing these characters from Excel output csv file.



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
You can delete some rows (experiment series) in Spectra_info.csv and run the script. Then you can rename the file, so that
it doesn't start with "Spectra_info" and create another file with other set of experiment series. Then you can run the other 
instance of Fityk simultaneously on different part of the input data. Make sure to change stopscript_name variable to be
able to stop one instance without stopping the other.



9) Run the script. At the start there are 2 questions. First one allows you to either run the script
in 1 experiment mode or batch processing mode. 

- Batch processing mode. In this mode everything defined in Spectra_info*.csv files is precessed. A spectrum is processed, 
output saved and then the previous fitting data deleted before moving on to the next spectrum.
- 1 experiment mode. In this mode only one experiment (or series) is processed, output written and the script exits before 
deleting the fitting result. This way it's possible to check what's going on.

If you choose 1 experiment mode then you need to insert additional info.
That is, you need to provide the data filename (without extension) that you want to check. Only the root filename is important, 
not series info in the filename. If the filename is e.g. "LIBS_data_0051.asc" then omit the end and write "LIBS_data".
If you inserted the filename correctly and the script finds the data then it asks you the experiment number. That is,
the number of the spectrum in the series. In the previous example it was "51". If you write something that can't be converted
to a number (including blank answer) then all of the spectra in the series are processed.

Finally, the script asks you whether you want to continue. If you made a mistake or changed your mind
then you can safely and quickly stop the script now.

Note that the output file contains uncertainties for every used parameter. However, due to LIBS spectra complexity (multiple 
overlapping lines, heavy noise, continuum), these can't be trusted.
 



10) Stopping the script during execution. If you want the script to stop during processing then ctrl+c would stop the script. 
However, Fityk is frozen during heavy calculations and you can't stop the script that way. To stop the script, write 
something into stopscript.txt in input_info folder and don't forget to save the file. Then during the next processing 
loop (might take a few minutes) the script checks the file and since there is something written, then the script stops.
Stopscript.txt is generated/emptied in the Input_info folder at the start of the script execution.



11) In case of crashes check the code first before abandoning the project! Usually the crash happens because of some simple 
mistake and the fix doesn't take much time. Unfortunately, the script has grown so large that I can't test every nuance 
of it with all different kind of inputs. 

An easier way to debug the code is to set debug variable (in user_constants.lua) to 4. Setting it to 5 is even more verbose 
but is very slow during initialization phase. debug 4 shows the last executed function and then you can zone in on the bug 
with print() statements.



12) Output. The actual local continuum is global constant (min data value) + local constant. The average or median of
the local constants is also a noise level estimate.



13) Optional - use "Fityk output organizer.lua" from utility scripts folder to sum/average/take median of the parameters 
from Fityk output by line identifier. Depending on the amount of data, it might take a minute to process the output.