# Spectra analyzer script for Fityk
Author: Jasper Ristkok


Fityk homepage: [https://fityk.nieto.pl/](https://fityk.nieto.pl/)

If you want to read the code, I advise to read Fityk's [manual](https://fityk.nieto.pl/fityk-manual.html).

There are 2 scripts.
1. "analyze.lua" is foolproof and should work with cfityk.
2. "analyze_and_plot.lua" is meant to be used with the GUI version. 
I can't guarantee that the script will work for all different computers because I'm using GUI through script, athough plotting with scripts isn't fully supported.

The script is written for spectra files gained from SOLIS software using Andor iStar340T ICCD camera. The files are generic columnar files where 1st column is pixel value and all other columns are different experiments.

Also the GUI is unresponsive while Fityk is calculating stuff. That's why you won't see progress in the command line output. Although you can see how far the process is by checking output file or drawn images. Depending on your computer and how many datapoints and functions you have, the process might take a long time. For me (Macbook pro 3,1 GHz Intel Core i5) it took 16 seconds to analyze and draw 16 spectra in the example folder.
---

## Example folder
I added an example folder in which there are 2 spectra series and an example info file. In the folder there is another output folder in which you can see the results for those 2 files.
---

## Using the script

1. Download and install Fityk
2. Put the spectra files and the info file in an input folder.
	* The spectra files have to be named as subsequent integers (e.g. as in the example 37, 38, 39...)
	* Info file has to have 5 columns: file number, exposure time, number of accumulations, gain and gate width. If these parameters do not apply for you, write them as 1-s (except for gain, write gain as 0). The file has to be .txt file.
3. Edit the script through Fityk or with a text editor. Change the constants at the beginning.
4. Run Fityk and use the script.
	* If you want to plot and draw images from the graphs, you have to use "analyze_and_plot.lua". To change the look of drawn .png files you have to manually import a spectra to Fityk (in the GUI) and add the number of functions you want to have. Then you have to modify the look of everything (like colours) except the ranges of the plot. Finally make sure you click on dataset @0 so that it is selected (highlighted) and then run the script. 
