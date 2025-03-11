# Spectra analyzer script for Fityk

Author: Jasper Ristkok

Licence: MIT - do whatever you want with the script. It's nice if you mention me if your work is largely based on my script but I won't come looking for you if you don't.

Fityk homepage: [https://fityk.nieto.pl/](https://fityk.nieto.pl/)

If you want to read the code, I advise to read Fityk's [manual](https://fityk.nieto.pl/fityk-manual.html). In the script I assume you have thoroughly read the manual.

## Script features

* The script is plug-and-play, meaning anyone can use it out of the box without installing or configuring additional stuff. 
* Batch processing for HUGE amounts of data (tested with 30 GB of spectra)
* There's 1 experiment mode and batch processing mode
* Spectra series can be input in one file or in many files with only a part of the series spectra in the file
* Every spectra experiment-wise and point-wise correction
* Configurable bounds for every function with default Levenberg-Marquardt (couldn't get MPFIT to work reliably)
* Stopping running script through text file (basically set flag to stop)
* Outputting every parameter of every function and all associated errors (errors are untrustworthy for complex spectra)
* Automatic image output through script
* Variable amounts of fittable Voigt and/or other profiles
* New profile definitions (apparatus function bound Voigt, FWHM-defined Voigt and rectangle profile)
* Modularity and quality of life stuff
* Smaller features not worth mentioning

---

## General info

The script is in "Main script" folder with more specific instructions.
Examples for different input data and the respective outputs are in "Examples" folder.
"Utility scripts" folder contains small scripts to help do things semi-manually. The most useful ones are "Plot_helper.lua" for configuring GUI looks for image output. 

The script is written for spectra files gained from SOLIS or Sophi nXt software using Andor iStar340T ICCD camera and the code accounts for huge amount of data. The files are generic columnar files where 1st column is pixel value and all other columns are different experiments' intensities. Sophi files have only one experiment in one file, so experiment series contains many files.

"analyze_and_plot.lua" is meant to be used with the GUI version. Implementing it through CLI might be faster, but currently the script is plug-and-play, meaning anyone can use it out of the box. Also, the GUI is unresponsive while Fityk is calculating stuff. That's why you won't see progress in the command line output. Although you can see how far the process is by checking the outputs. 

Depending on your computer and how many datapoints and functions you have, the process might take a long time. E.g. with script v3.10, 40 000 px spectra with 150 lines takes about 1.5 minutes/spectrum. The processing time seems to scale exponentially with the number of functions and/or pixels. Also I've noticed that processing time depends also a bit on the shape of the spectra.

The script contains many hacks to get what I want (e.g. plotting, although plotting with scripts isn't (fully) supported). I can't guarantee that there won't be any crashes because I can't test the script with every possible input data. Moreover, everything I write might be critical for the code. Finally, please bear in mind that I'm not a programmer, so the code will be sub-optimal. If you find any bugs or get crashes then please let me know in a way that I can replicate it!

---

## Example folder

I added an example folder in which there are 2 different cases (different spectrometers, samples - different lines, cameras and acquisition programs: Andor Solis and Sophi nXt) with 2 spectra series each, and example input info. For both cases there is an output folder in which you can see the results for those inputs. Also for both examples, the user_constants.lua file with necessary constants is in the Input_info folder for reproducibility. This means the script is ready to be excecuted with the example inputs for testing (although you have to specify your system path in the main script).

In the 656 nm example folder, processing 2 background files + 2 data files, that is, 60 spectra and 23 lines each, took c.a 5 min. This example shows:
* Solis data files
* Background saved as separate files
* Small spectrum (1024 px) with few lines (23)
* High continuum and the local constants taking it into account (local continuum = global constant + local constant)

In the wide spectra example folder, processing 2 data files, that is, 34 spectra and 144 lines each, took c.a 52 min. This example shows:
* Sophi nXt data files
* Large spectrum (40 307 px) with many lines (144)

The times are gained with Intel i5 processor.

---

## Using the script

1. Download and install Fityk.
2. Carefully follow the instructions in _README script.txt and _LIBS analysis tips.txt.
	* Gather input files.
	* Describe how to process the spectra: overwrite working directory variable in analyze_and_plot.lua, modify user_constants.lua and generate three Input_info files.
	* The 1 experiment mode is good for testing out values.
4. Run Fityk and use the script.
	* If you want to plot and draw images from the graphs, you might want to change the look of drawn .png files. Then you have to manually import a spectra to Fityk (in the GUI) and add the number of functions you want to have (or use 1 experiment mode). Plot_helper.lua takes care of latter automatically. Then you have to modify the look of everything (like colours or whether labels are shown), except the ranges of the plot. Finally make sure you click on dataset @0 so that it is selected (highlighted) and then run the analyzing script. 

---

## Tips and tricks

* Make sure to also check "_LIBS analysis tips.txt".
* Plot_helper.lua plots nr_of_lines gaussian functions and a constant. You can colour them as you like the output to be because running analyze_and_plot after that will keep the colours. I like to connect datapoints with a line too. Also if you colour the lines and then in the Gui use GUI => Save Current Config => As Default then Fityk will alway open with that config.
* If you started the script and it won't stop for a long time and you don't want to quit the program (e.g since then you would lose your temporary colourcode), you can write something in the stopscript.txt in the input folder. The script reads the file and if the file isn't empty then the script will exit the loop. Note that when you write something in the file you also have to save the file. Otherwise changes won't be applied.
* Fityk uses only 1 core thread (at least the LUA part). If you want to squeeze more juice out of your computer, run multiple instances of Fityk and the script with different spectra, effectively using multithreading and multiple cores manually. There isn't a native LUA workaround since LUA doesn't support hardware multithreading.
* Example colour scheme: (nr. of function. colour)
	0. snow
	1. maraschino
	2. flora
	3. aqua
	4. strawberry
	5. tangerine
	6. clover
	7. ice
	8. carnation
	9. maraschino
	10. flora
	11. aqua
	12. strawberry
	13. ...
