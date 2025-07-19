# Spectra analyzer script for Fityk

Author: Jasper Ristkok

Licence: MIT - do whatever you want with the script. It's nice if you mention me if your work is largely based on my script but I won't come looking for you if you don't.

Fityk homepage: [https://fityk.nieto.pl/](https://fityk.nieto.pl/)

If you want to understand the code, I advise to read the readmes in main script folder and Fityk's [manual](https://fityk.nieto.pl/fityk-manual.html). In the script I assume you have thoroughly read the manual.

This code is available in Github as [fityk-libs-spectra-script](https://github.com/Tshepajev/fityk-libs-spectra-script). The repository also has the Development branch for the latest version of the script but I'm sometimes using it as a backup rather than a proper version, so in that case the code wouldn't work and you'd need to check previous commits.

## Script features

* The script is plug-and-play, meaning anyone can use it out of the box without installing or configuring other stuff than Fityk itself. 
* The script is semi-automatic. You need to fine-tune the instructions for it (input info folder) and then it processes everything automatically.
* The script is also for batch processing for HUGE amounts of data (tested with 30 GB of spectra).
* The parameters of the spectral lines can be linked together under one variable. This allows the use of complex models.
* Configurable bounds for every line function with default Levenberg-Marquardt (couldn't get MPFIT to work reliably).
* Outputting every parameter of every function and all associated standard errors (errors are untrustworthy for complex spectra).
* Automatic image and session output through script.
* There's 1 experiment mode and batch processing mode.
* Every spectra has experiment-wise and point-wise correction.
* Spectra series can be input in one file or in many files with only a part of the series spectra in the file.
* Variable amounts of fittable Voigt and/or other profiles.
* New profile definitions (apparatus function bound Voigt, FWHM-defined Voigt and Rectangle profile).
* Stopping running script through text file (basically set flag to stop).
* Modularity and quality of life stuff.
* Smaller features not worth mentioning.

---

## General info

The script is in "Main script" folder with more specific instructions. Examples for different input data and the respective outputs are in "Examples" folder. "Utility scripts" folder contains small scripts to help do things semi-manually. The most useful ones are "Plot_helper.lua" for configuring GUI looks for image output. 

The script is written for spectra files gained from SOLIS or Sophi nXt software using Andor iStar340T ICCD camera and the code accounts for huge amount of data. The files are generic columnar files where 1st column is pixel value and all other columns are different experiments' intensities. Sophi files have only one experiment in one file, so experiment series contains many files.

"analyze_and_plot.lua" is meant to be used with the GUI version. Implementing it through CLI might be faster, but currently the script is plug-and-play, meaning anyone can use it out of the box. Also, the GUI is unresponsive while Fityk is calculating stuff. That's why you won't see progress in the command line output. Although you can see how far the process is by checking the outputs. 

Depending on your computer and how many datapoints and functions you have, the process might take a long time. E.g. for the provided examples with script v4.3.1, 40 000 px spectra with 150 lines and multiple links between them takes about 5 minutes/spectrum. 22 lines and 1000 px without links took about 6 seconds per spectrum. The processing time seems to scale exponentially with the number of functions and/or active pixels. Having links between functions means having multiple spectral windows active simultaneously, so it slows down processing considerably. Also I've noticed that processing time depends also a bit on the shape of the spectra.

The script reads in instructions for fitting (input info folder), pre-processes the spectra with e.g. spectral sensitivity and saves the corrected spectrum. Then The script generates the lines and links between them. During fitting, there is a spectral window of active points and unlocked lines that moves from left to right (towards higher wavelengths) with the observable line being in the center. The points outside of the window are inactive and the lines outside the window are locked. The window fits also a local constant. The observable line is fitted and its and the local constant's parameters and standard errrors are saved to output. If the observable line is linked to other lines then those lines and tertiary lines around those are activated too with secondary local constants for those secondary windows. Once the fitting is complete and info is extracted then the window moves on to the next line. Finally, the script saves the data to the output file, saves images of the fit, and saves the session for checking the fit afterwards. 

The script contains many hacks to get what I want (e.g. plotting, although plotting with scripts isn't (fully) supported). I can't guarantee that there won't be any crashes because I can't test the script with every possible input data. Moreover, everything I write might be critical for the code. Finally, please bear in mind that I'm not a programmer, so the code will be sub-optimal. If you find any bugs or get crashes then please let me know in a way that I can replicate it!

---

## Example folder

I added an example folder in which there are 2 different cases (different spectrometers, samples - different lines, cameras and acquisition programs: Andor Solis and Sophi nXt) with 2 spectra series each, and example input info. For both cases there is an output folder in which you can see the results for those inputs. Also for both examples, the _user_constants.lua file with necessary constants is in the Input_info folder for reproducibility. This means the script is ready to be excecuted with the example inputs for testing (although you have to specify your system path in the main script).

In the 656 nm example folder, processing 2 background files + 2 data files, that is, 60 spectra and 22 lines each, took c.a 6 min without links and 11 min with links. This example shows:
* Solis data files (many spectra in one file)
* Background saved as separate files
* Small spectrum (1024 px) with few lines (22)
* High continuum and the local constants taking it into account (local continuum = global constant + local constant)
* Links between lines

In the wide spectra example folder, processing 3 data files, that is, 39 spectra and 153 lines each with links between them, took c.a 230 min. This example shows:
* Sophi nXt data files (one spectrum per file - many files)
* Complex filename mode where the spectrum index is in the middle of the filename
* Large spectrum (40 307 px) with many lines (153)
* Links between lines throughout the spectra

The times are gained with Intel i5 processor and one thread (Fityk's limitation). Multithreading is possible if running multiple instances of Fityk and the script with different spectra, effectively using multithreading and multiple cores manually. There isn't a native LUA workaround since LUA doesn't support hardware multithreading.

---

## Using the script

1. Download and install Fityk.
2. Carefully follow the instructions in "_README script.txt" in the "Main script" folder. You can use "Examples" folder as a reference. "_README script.txt" is very important to follow to the point and I expect you to read it. E.g. "_README script.txt" explains what needs to be in the Input_info folder and in the files.
	* Check also "_LIBS analysis tips.txt" and "_Troubleshooting.txt". The latter is there for me in the future and for you in case you want to know or debug why there's some error in Fityk or if something doesn't work as intended.
	* Gather input files.
	* Overwrite working directory variable in analyze_and_plot.lua for the one of your system.
	* Describe how to process the spectra: carefully modify _user_constants.lua and generate three Input_info files. The more carefully you do this step the better the result. With properly fine-tuned instructions the script can do wonders with line fitting.
	* The 1 experiment mode and saved sessions in Output folder are good for testing out values.
3. Launch and configure Fityk looks,
	* Format the GUI to look the way you like. Right click on the main pane and choose configuration. Also, color the datasets and functions the way you like. Finally, click "save current config as default" in GUI dropdown menu. The sessions and saved images look like as you see things in the GUI. To format datasets or functions, you have to manually import a spectra to Fityk (in the GUI) and add the number of functions you want to have (or use 1 experiment mode). Plot_helper.lua takes care of latter automatically. Then you have to modify the look of everything (like colours or whether labels are shown), except the ranges of the plot.
	* Click on dataset @0 so that it is selected (highlighted). If this isn't selected then Fityk crashes when the actually selected dataset is deleted by the script (TODO: check). If this isn't selected then Fityk saves the images of the actually selected dataset.
4. Use the script.
	* Run analyze_and_plot.lua through the GUI.
	* Select yes or no in the input pop-up. Yes is 1 experiment mode, No is batch-processing mode.
	* For 1 experiment mode, type the filename and the experiment number in the series if applicable. The filename has to be in the same format as in Spectra_info*.csv files (see "_README script.txt"). That is, if e.g. using complex filename setting and files of that spectra series are named "492_2X8_R7C3C7_XXXX 2X08 - R7 C3-C7.txt" where "XXXX" is index then you have to write/paste "492_2X8_R7C3C7_0001X 2X08 - R7 C3-C7".
	* The final question asks whether to stop the script before starting processing. This is there just because stopping the script through the file is annoying.
5. Stop the script prematurely.
	* If you want to stop the script before it finishes then write something into _Stopscript.txt in Input_info folder and save the file. This is crucial if you don't want to force quit Fityk (e.g. you haven't saved the GUI configuration). The script exits during the next loop. You don't have to create the file nor empty it yourself, the script takes care of it.
6. Use the outputs.
	* Input_info_corrected folder contains processed spectra which might be useful for other analysis.
	* Output folder contains the output file (_Fityk_output.csv) which contains all of the data from the fitting. Two first rows are headers: first row is for line ID, second row is for extracted parameter name. All other rows are for each fitted experiment (in all of the experiment series). The error values can't be trusted if using complex spectra (also explained in Fityk manual), but could prove useful in some cases. 
	* Output folder contains the _user_constants.lua copy-pasted from input, so that the data processing would be repeatable.
	* Output folder contains images for quick overview of the situation. The images are exactly like the GUI shows when zoomed out, so they might be crowded if using many lines and showing the labels of lines.
	* Output folder contains the Sessions folder with the Fityk session before continuing to the next experiment. These are useful to check interactively whether everything was fitted well or to do additional manual work with the spectrum after the fitting.

---

## Tips and tricks

Please check the examples and read the "_README script.txt" and "_LIBS analysis tips.txt". Also the Fityk's manual and "_Troubleshooting.txt" contain relevant information. 