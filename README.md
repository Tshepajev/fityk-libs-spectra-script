# Spectra analyzer script for Fityk

Author: Jasper Ristkok


Fityk homepage: [https://fityk.nieto.pl/](https://fityk.nieto.pl/)

If you want to read the code, I advise to read Fityk's [manual](https://fityk.nieto.pl/fityk-manual.html).

There are 2 scripts.

1. "analyze.lua" is foolproof and should work with cfityk. However, I primarily use the next one so analyze.lua might be behind in features.
2. "analyze_and_plot.lua" is meant to be used with the GUI version. I can't guarantee that the script will work for all different computers because I'm using GUI through script, athough plotting with scripts isn't (fully) supported.

The script is written for spectra files gained from SOLIS software using Andor iStar340T ICCD camera. The files are generic columnar files where 1st column is pixel value and all other columns are different experiments.

Also the GUI is unresponsive while Fityk is calculating stuff. That's why you won't see progress in the command line output. Although you can see how far the process is by checking the output file or drawn images. Depending on your computer and how many datapoints and functions you have, the process might take a long time. 

For me (Macbook pro 3,1 GHz Intel Core i5, using 1 instance of Fityk (a.k.a 25% of CPU power)) it took 16 seconds to analyze and draw 16 spectra in the example folder. Using analyze_and_plot script v1.3 with 36 Voigt functions and a constant, the script processed 72 experiments in 84 minutes. The processing time probably scales exponentially with the number of functions.

---

## Example folder

I added an example folder in which there are 2 different cases with 3 spectra series and an example info file. For the both cases there is an output folder in which you can see the results for those files.

---

## Using the script

1. Download and install Fityk
2. Put the spectra files, info file and stopscript.txt in an input folder.
	* The spectra files have to be named as subsequent integers (e.g. as in the example 37, 38, 39...)
	* Info file has to have 5 columns: file number, exposure time, number of accumulations, gain and gate width. If these parameters do not apply for you, write them as 1-s (except for gain, write gain as 0). The file has to be .txt file.
	* stopcscript.txt is for stopping the script without quitting Fityk. If the file has any content, script will exit the processing loop. If you write something in stopscript.txt you also have to save the file for changes to be applied.
3. Edit the script through Fityk or with a text editor. Change the constants at the beginning. You might have to try out multiple different constant values so that the script will work for your application. It is advisable to list the lines in the order where the most intense peak is the first. The script creates funtions in the order of the list and this way intense and weak peaks don't accidentaly swich places. 
4. Run Fityk and use the script.
	* If you want to plot and draw images from the graphs, you have to use "analyze_and_plot.lua". To change the look of drawn .png files you have to manually import a spectra to Fityk (in the GUI) and add the number of functions you want to have. plot_helper.lua takes care of that automatically. Then you have to modify the look of everything (like colours) except the ranges of the plot. Finally make sure you click on dataset @0 so that it is selected (highlighted) and then run the analyzing script. 

---

## Tips and tricks

* plot_helper.lua plots 40 gaussian functions and a constant. You can colour them as you like the output to be because running analyze_and_plot after that will keep the colours.
* If you started the script and it won't stop for a long time and you don't want to quit the program since then you would lose the colourcode, you can write something in the stopscript.txt in the input folder. The script reads the file and if the file isn't empty then the script will exit the loop. Note that when you write something in the file you also have to save the file. Otherwise changes won't be applied.
* Fityk uses only 1 core thread (at least the LUA part). If you want to squeeze more juice out of your computer, run multiple instances of Fityk and the script in different regions of experiment numbers effectively using multithreading and multiple cores manually. There isn't a native LUA workaround since LUA doesn't support hardware multithreading. However, this way you have to apply the colours to every instance again.
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
If some peaks are coloured the same and are situated next to eachother because of peak location ordering, you can colour one of them white (snow).

* Once the script took 5 minutes to process 1 experiment with 37 functions. When I quit Fityk and reopened it everything was about 5 times quicker. So if you think the script works absurdly slow, try to quit Fityk and reopen it (might have been something with RAM usage).
