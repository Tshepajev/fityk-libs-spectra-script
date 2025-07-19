Two examples are provided: narrow spectral region with few lines and wide spectral region with many lines. 
For both examples, the folders contained Input_info folder and Input_data folder.
There is also an Excel file which I used to create Lines_info*.csv, for your and (my future) convenience.
All other folders and files were created by the script, including Stopscript.txt in Input_info folder.

Note that the data consists of real data from experiments but the instructions for fitting for the script in Input_info folder 
have been changed to show the examples and haven't been meticulously checked if it would make sense in real data processing.
Therefore, the Input_info itself isn't ideal (not fine tuned), so also the resulting fit isn't ideal.
In other words, the examples give an idea of real spectra fitting, but you shouldn't focus on some functions being offset from 
the actual line or some functions trying to fit lines where there are none or when some functions are fitted too wide etc.
I want to give you an idea of the capabilities of the script but I don't want to spend multiple days fine-tuning the input info
just for these examples. I've copy-pasted parts of the Input_info files from actual data analysis but haven't fine tuned these
for current examples. E.g. for the wide region examples, the Lines_info*.csv file contains lines for HFGC_1c_P1 and 14IWG1A_3a_P1 
spectra from one research mission but 492_2X8_R7C3C7_0001 2X08 - R7 C3-C7 spectra from a different research mission, but in a 
broad sense contain same lines. Also, the Pixel_info*.csv for these is approximate and introduces some deviation from ideal case.

The reported times are gained with Intel i5 processor, and depend heavily on the amount of used lines, active datapoints, and links
because links can avtivate multiple windows.

The first example, "656 nm with separate background" has relatively small spectrum (1024 px) with only few lines appearing in the series.
The input data files are Solis files which have many spectra in one file. 
The spectra aren't background corrected, so separate background spectra are provided.
There are links between many lines, so multiple spectral windows are active simultaneously for the fitting.
In the linked lines case, it took 11 minutes to process the 60 test spectra.
Without links between the spectral lines in the Lines_info*.csv file the processing took 6 minutes.


The second example is for wide spectra (about 40 000 px) with many lines.
This is an extreme example which takes a long time to process (3-6 minutes per spectrum while doing other things on the PC).
The input data files are Sophi nXt files which have one spectrum per file.
This example also contains an experiment series with a complex filename (index in the middle of the name).
The wide example folder has only a few spectra to save space in Github but I have processed 3000 of these in one series 
(and about 50 experiment series after that) with the same script.
The output images in this case are too crowded because of the view settings and the amount of lines used. 
In that case, it's best to save images without the line function labels but on the other hand, 
the labels are useful for the session files.
The spectra in the wide region example contain some Be and Ar lines that experience Stark Shift - the line is shifted from its natural location and
is asymmetrical due to the gate width of the camera.
Also note that the spectrum was gained with an echelle spectrometer and the wavelengths were broadly calibrated but not
precisely for every diffraction order (non-ideal Pixel_info*.csv, as mentioned earlier). 
This mean that some lines in Lines_info*.csv don't point to the exact location of the peak because Pixel_info*.csv multipliers
aren't completerly accurate.


Many images and sessions in output folder are deleted to save space in Github, but the ones left give the idea of the capabilities of the script.
I have batch-processed hundreds of spectra series (e.g. 500 spectra in each) in one go with the script successfully.
Also, once the input info is fine-tuned then the script can do wonders in fitting, especially now that it has variable linking feature (as of v4).
Variable linking means that in theory you could apply a proper spectroscopic model (e.g. LIBS emission depending on plasma temperature) 
to all of the lines in the spectra - it won't be fast but will use a complex model for all lines simultaneously.