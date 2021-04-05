# Spectra analyzer script for Fityk

Author: Jasper Ristkok

Licence: MIT - do whatever you want with the script. It's nice if you mention me if your work is largely based on my script but I won't come looking for you if you don't.

Fityk homepage: [https://fityk.nieto.pl/](https://fityk.nieto.pl/)

If you want to read the code, I advise to read Fityk's [manual](https://fityk.nieto.pl/fityk-manual.html). In the script I assume you have thoroughly read the manual.

## Script features

* Batch processing for HUGE amounts of data
* Automatic image output through script
* Outputting every parameter of every function and all associated errors
* Configurable bounds for every function with default Levenberg-Marquardt (couldn't get MPFIT to work reliably)
* Stopping running script through text file (basically set flag to stop)
* Every spectra experiment-wise and point-wise correction
* Variable amounts of fittable Voigt profiles
* Smaller features not worth mentioning

## General info

There are 2 scripts.

1. "analyze.lua" is foolproof and should work with cfityk. However, I primarily use the next one so analyze.lua is waaaaaaaay behind in features (about 1 year of features). I won't use or talk about this code anymore.
2. "analyze_and_plot.lua" is meant to be used with the GUI version. I can't guarantee that the script will work for all different computers because I'm using GUI through script, athough plotting with scripts isn't (fully) supported. Also I have only tested the script on my MacOS laptop.

The script is half hardcoded. That means you might have to dive into the code to have it do exactly what you want. Also I have used a few hacks (at least in my opinion) because I couldn't find any better solutions or more info about Fityk. This is also the primary purpose of sharing this script. Moreover, EVERYTHING I write might be critical for the code. Finally, please bear in mind that I'm not a programmer so the code will be sub-optimal.

The script is written for spectra files gained from SOLIS software using Andor iStar340T ICCD camera. The files are generic columnar files where 1st column is pixel value and all other columns are different experiments' intensities.

Also the GUI is unresponsive while Fityk is calculating stuff. That's why you won't see progress in the command line output. Although you can see how far the process is by checking the output file or drawn images. Depending on your computer and how many datapoints and functions you have, the process might take a long time. 

For me (Macbook Pro 3,1 GHz Intel Core i5, using 1 instance of Fityk (a.k.a 25-50% of CPU power)) it took 16 seconds to analyze and draw 16 spectra in the old example folder (you can probably see it in Git commit history). Using analyze_and_plot script v1.3 with 36 Voigt functions and a constant, the script processed 72 experiments in 84 minutes. The processing time seems to scale exponentially with the number of functions. In script v1.8 processing 1 spectra with 140 Voigt lines takes about 5 minutes but in v1.8 there's also a big improvement (c.a 100x) in performance. Also I've noticed that processing time depends also a bit on the shape of the spectra.

Roughly the time it takes to process 1 spectra in seconds is:
processing time (s) = 3.174 * exp(0.031 * nr_of_lines)
---

## Example folder

I added an example folder in which there are 2 different cases (different spectral region) with 3 spectra series (6 spectra in 1 file), an example info, sensitivity and stopscript file. For both cases there is an output folder in which you can see the results for those inputs. Also for both examples I added the script with necessary constants. This means the example scripts are ready to be excecuted with the example inputs for testing.

In the 387 nm folder I have shown 3 different situations.
2 - many high peaks
3 - HUGE noise
4 - few peaks
Processing 3 files e.g 18 spectra e.g 2502 lines took c.a 70 min.

In the 656 nm folder I have shown the next situations.
582 - clean spectra with thin H-line
583 - clean spectra with low noise
584 - noisy spectra with wide H-line and large continuum signal
Processing 3 files e.g 18 spectra e.g 2862 lines took c.a 130 min.


(Note to my future self: corresponding names are 2=2; 3=13; 4=291; 582=582; 583=593; 584=604)

---

## Using the script

1. Download and install Fityk
2. Put the spectra files, info file, sensitivity file and stopscript.txt in an input folder.
	* The spectra files have to be named as subsequent integers (e.g. as in the example 37, 38, 39...)
	* Info file has to have 5 columns: file number, pre-a,plification, exposure time, number of accumulations, gain, gate width and additional multiplier. If these parameters do not apply for you, write them as 1-s (except for gain, write gain as 0). Currently exposure time isn't used but I haven't changed the indexes either so it remains as required column.
	* stopcscript.txt is for stopping the script without quitting Fityk. If the file has any content, script will exit the processing loop after outputting data. If you write something in stopscript.txt you also have to save the file for changes to be applied.
3. Edit the script through Fityk or with a text editor. Change the constants at the beginning. You might have to try out multiple different constant values so that the script will work for your application. The 1 experiment mode is good for testing constant values.  Also I found out that for my application it's best to fill the spectra with Voigt lines. Most of these might not be physical but oh boy does it improve fitting of the physical lines. That's why 656 nm example files have so many lines.
4. Run Fityk and use the script.
	* If you want to plot and draw images from the graphs, you have to use "analyze_and_plot.lua". To change the look of drawn .png files you have to manually import a spectra to Fityk (in the GUI) and add the number of functions you want to have (or use 1 experiment mode). plot_helper.lua takes care of latter automatically. Then you have to modify the look of everything (like colours) except the ranges of the plot. Finally make sure you click on dataset @0 so that it is selected (highlighted) and then run the analyzing script. 

---

## Tips and tricks

* plot_helper.lua plots nr_of_lines gaussian functions and a constant. You can colour them as you like the output to be because running analyze_and_plot after that will keep the colours. I like to connect datapoints with a line too. Also if you colour the lines and then in the Gui use GUI => Save Current Config => As Default then Fityk will alway open with that config.
* If you started the script and it won't stop for a long time and you don't want to quit the program (e.g since then you would lose your temporary colourcode), you can write something in the stopscript.txt in the input folder. The script reads the file and if the file isn't empty then the script will exit the loop. Note that when you write something in the file you also have to save the file. Otherwise changes won't be applied.
* Fityk uses only 1 core thread (at least the LUA part). If you want to squeeze more juice out of your computer, run multiple instances of Fityk and the script in different regions of experiment numbers effectively using multithreading and multiple cores manually. There isn't a native LUA workaround since LUA doesn't support hardware multithreading.
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


* I have noted that when processing large amount of data Fityk's memory use goes up. This might be an issue for older computers. Also I had a problem where each subsequent processed spectra took exponentially longer up to some constant level. I found that the issue was that deleting a function didn't automatically delete associated variables and re-defining a variable didn't overwrite old variable somehow like I'm used with Python (probably mistake in my code). Now I delete all variables after each experiment and increasing processing time shouldn't be an issue.